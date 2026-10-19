import Foundation
import Observation
import WhisperKit

/// Bir dil. `code` BCP-47 kimliğidir (ör. "en", "tr", "zh-Hant"); adlar sistem dilinde gösterilir.
struct LanguageOption: Identifiable, Hashable {
    let code: String
    var id: String { code }

    var localeLanguage: Locale.Language { Locale.Language(identifier: code) }
    /// Whisper'ın döndürdüğü kodla karşılaştırmak için yalın dil kodu ("zh-Hant" → "zh").
    var baseCode: String { localeLanguage.languageCode?.identifier ?? code }

    var name: String {
        if self == .auto { return L("Detect automatically") }
        let name = Locale.current.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: Locale.current) + name.dropFirst()
    }

    var short: String {
        self == .auto ? L("AUTO") : code.uppercased()
    }

    static let auto = LanguageOption(code: "auto")

    /// Whisper'ın tanıyabildiği tüm diller (~99), sistem dilinde alfabetik.
    static let spokenLanguages: [LanguageOption] = Constants.languageCodes
        .map { LanguageOption(code: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static func find(_ code: String) -> LanguageOption {
        LanguageOption(code: code)
    }

    /// Mac'in birincil dili (ör. "tr", "en", "zh-Hans").
    static var system: LanguageOption {
        let language = Locale.Language(identifier: Locale.preferredLanguages.first ?? "en")
        let code = language.languageCode?.identifier ?? "en"
        if code == "zh" {
            return LanguageOption(code: language.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans")
        }
        return LanguageOption(code: code)
    }
}

/// Whisper model seçenekleri (argmaxinc/whisperkit-coreml deposundaki klasör adları).
struct ModelOption: Identifiable, Hashable {
    let variant: String
    let nameKey: String
    let detailKey: String
    var id: String { variant }

    var name: String { L(nameKey) }
    var detail: String { L(detailKey) }

    static let all: [ModelOption] = [
        .init(variant: "openai_whisper-large-v3-v20240930_turbo_632MB",
              nameKey: "Large v3 Turbo (compressed)",
              detailKey: "~630 MB · best quality/speed balance (recommended)"),
        .init(variant: "openai_whisper-large-v3-v20240930_turbo",
              nameKey: "Large v3 Turbo (full)",
              detailKey: "~1.6 GB · highest quality"),
        .init(variant: "openai_whisper-small_216MB",
              nameKey: "Small",
              detailKey: "~216 MB · fastest, lower quality"),
    ]

    static let `default` = all[0]
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var sourceLanguage: String { didSet { defaults.set(sourceLanguage, forKey: "sourceLanguage") } }
    var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: "targetLanguage") } }
    var modelVariant: String { didSet { defaults.set(modelVariant, forKey: "modelVariant") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var showOriginal: Bool { didSet { defaults.set(showOriginal, forKey: "showOriginal") } }
    /// Dinleme sürerken dışarı tıklanınca bölme kapanmasın.
    var keepOpenWhileListening: Bool { didSet { defaults.set(keepOpenWhileListening, forKey: "keepOpenWhileListening") } }

    private init() {
        // Varsayılan: Mac'in dilinde altyazı. Sistem İngilizceyse kaynak dil otomatik algılanır.
        let system = LanguageOption.system
        defaults.register(defaults: [
            "sourceLanguage": system.baseCode == "en" ? LanguageOption.auto.code : "en",
            "targetLanguage": system.code,
            "modelVariant": ModelOption.default.variant,
            "fontSize": 17.0,
            "showOriginal": true,
            "keepOpenWhileListening": true,
        ])
        sourceLanguage = defaults.string(forKey: "sourceLanguage")!
        targetLanguage = defaults.string(forKey: "targetLanguage")!
        modelVariant = defaults.string(forKey: "modelVariant")!
        fontSize = defaults.double(forKey: "fontSize")
        showOriginal = defaults.bool(forKey: "showOriginal")
        keepOpenWhileListening = defaults.bool(forKey: "keepOpenWhileListening")
    }

    var source: LanguageOption { LanguageOption.find(sourceLanguage) }
    var target: LanguageOption { LanguageOption.find(targetLanguage) }
}
