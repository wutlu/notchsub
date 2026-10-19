import Foundation
import Observation
import SwiftUI
import Translation

/// Apple'ın cihaz üstü (ücretsiz, çevrimdışı) çeviri motoru.
///
/// macOS 15'te `TranslationSession` yalnızca SwiftUI `.translationTask` ile alınabiliyor.
/// Bu yüzden bölmenin içinde görünmez bir `TranslationHost` view'ı oturumu açık tutar
/// ve `run(session:)` döngüsü kuyruktaki işleri sırayla çevirir.
@MainActor
@Observable
final class AppleTranslator {
    enum PackStatus: Equatable {
        case unknown, installed, notInstalled, unsupported, sameLanguage
    }

    private struct Job {
        let text: String
        let completion: (String?) -> Void
    }

    private(set) var configuration: TranslationSession.Configuration?
    private(set) var packStatus: PackStatus = .unknown
    private(set) var isSessionActive = false

    private(set) var source: LanguageOption = .auto
    private(set) var target: LanguageOption = .system
    /// Bu Mac'te cihaz üstü çeviri yapılabilen hedef diller.
    private(set) var targetLanguages: [LanguageOption] = []

    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var partialJob: Job?

    func configure(source: LanguageOption, target: LanguageOption) {
        self.source = source
        self.target = target
        if source.baseCode == target.baseCode {
            configuration = nil
            packStatus = .sameLanguage
            return
        }
        let newConfig = TranslationSession.Configuration(
            source: source == .auto ? nil : source.localeLanguage,
            target: target.localeLanguage
        )
        if configuration != newConfig {
            configuration = newConfig
        }
        Task { await refreshStatus() }
    }

    func loadTargetLanguages() async {
        var seen = Set<String>()
        let options = await LanguageAvailability().supportedLanguages.compactMap { language -> LanguageOption? in
            guard let code = language.languageCode?.identifier else { return nil }
            let id = code == "zh"
                ? (language.maximalIdentifier.contains("Hant") ? "zh-Hant" : "zh-Hans")
                : code
            return seen.insert(id).inserted ? LanguageOption(code: id) : nil
        }
        targetLanguages = options.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func refreshStatus() async {
        guard source.baseCode != target.baseCode else {
            packStatus = .sameLanguage
            return
        }
        // Otomatik kaynakta en sık kullanılan çift (İngilizce) için kontrol et.
        let from = source == .auto ? Locale.Language(identifier: "en") : source.localeLanguage
        let status = await LanguageAvailability().status(from: from, to: target.localeLanguage)
        switch status {
        case .installed: packStatus = .installed
        case .supported: packStatus = .notInstalled
        case .unsupported: packStatus = .unsupported
        @unknown default: packStatus = .unknown
        }
    }

    /// Konuşulan dil hedef dille aynıysa çeviri gerekmez.
    func needsTranslation(detectedLanguage: String?) -> Bool {
        guard configuration != nil, packStatus == .installed else { return false }
        if let detectedLanguage, detectedLanguage == target.baseCode { return false }
        return true
    }

    func translate(_ text: String, completion: @escaping (String?) -> Void) {
        jobs.append(Job(text: text, completion: completion))
        if jobs.count > 20 { jobs.removeFirst(jobs.count - 20) }
    }

    /// Geçici metin: yalnızca en sonuncusu çevrilir.
    func translatePartial(_ text: String, completion: @escaping (String?) -> Void) {
        partialJob = Job(text: text, completion: completion)
    }

    func cancelPending() {
        jobs.removeAll()
        partialJob = nil
    }

    func run(session: TranslationSession) async {
        isSessionActive = true
        defer { isSessionActive = false }
        while !Task.isCancelled {
            let job: Job
            if !jobs.isEmpty {
                job = jobs.removeFirst()
            } else if let partial = partialJob {
                partialJob = nil
                job = partial
            } else {
                try? await Task.sleep(for: .milliseconds(40))
                continue
            }
            do {
                let response = try await session.translate(job.text)
                job.completion(response.targetText)
            } catch {
                job.completion(nil)
            }
        }
    }
}

/// Bölmenin içine yerleştirilen görünmez view; çeviri oturumunu canlı tutar.
struct TranslationHost: View {
    let translator: AppleTranslator

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .translationTask(translator.configuration) { session in
                await translator.run(session: session)
            }
    }
}
