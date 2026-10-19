import Foundation
import Observation

/// Ses → yazı → çeviri → arayüz akışını yönetir.
@MainActor
final class AppController {
    let settings: AppSettings
    let store = SubtitleStore()
    let translator = AppleTranslator()

    private let engine = WhisperEngine()
    private let capture = SystemAudioCapture()
    private let buffer = SampleBuffer()
    private lazy var transcriber = StreamingTranscriber(engine: engine, buffer: buffer)
    private var transcriptionTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings

        let buffer = buffer
        capture.onSamples = { samples in buffer.append(samples) }
        capture.onLevel = { [weak store] level in
            Task { @MainActor in store?.level = level }
        }
        capture.onDefaultOutputChanged = { [weak self] in
            Task { @MainActor in self?.restartCaptureIfNeeded() }
        }
    }

    func bootstrap() {
        translator.configure(source: settings.source, target: settings.target)
        Task { await translator.loadTargetLanguages() }
        loadModel()
    }

    // MARK: - Model

    func loadModel() {
        let variant = settings.modelVariant
        guard engine.loadedVariant != variant else { return }
        let resume = store.wantsListening
        stopCapture()
        store.wantsListening = resume
        loadTask?.cancel()
        let engine = engine
        loadTask = Task {
            await engine.load(variant: variant) { state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.store.engineState = state
                    if state == .ready, self.store.wantsListening { self.startCapture() }
                }
            }
        }
    }

    // MARK: - Dinleme

    func startListening() {
        store.wantsListening = true
        store.errorMessage = nil
        if store.engineState == .ready { startCapture() }
    }

    func stopListening() {
        store.wantsListening = false
        stopCapture()
    }

    func toggleListening() {
        store.wantsListening ? stopListening() : startListening()
    }

    private func startCapture() {
        guard !store.isCapturing else { return }
        buffer.clear()
        do {
            try capture.start()
        } catch {
            store.errorMessage = error.localizedDescription
            return
        }
        store.isCapturing = true
        startTranscription()
    }

    private func stopCapture() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        capture.stop()
        buffer.clear()
        store.isCapturing = false
        store.level = 0
        // Ekranda yarım kalan metni kesin satıra taşı.
        if !store.partialOriginal.isEmpty {
            confirm(store.partialOriginal, language: nil)
        }
        store.clearPartial()
    }

    private func restartCaptureIfNeeded() {
        guard store.isCapturing else { return }
        transcriptionTask?.cancel()
        capture.stop()
        store.isCapturing = false
        startCapture()
    }

    private func startTranscription() {
        transcriptionTask?.cancel()
        let language = settings.source == .auto ? nil : settings.source.code
        let transcriber = transcriber
        let events = StreamingTranscriber.Events(
            partial: { text, language in
                Task { @MainActor [weak self] in self?.updatePartial(text, language: language) }
            },
            confirmed: { text, language in
                Task { @MainActor [weak self] in self?.confirm(text, language: language) }
            },
            error: { message in
                Task { @MainActor [weak self] in self?.store.errorMessage = message }
            }
        )
        transcriptionTask = Task.detached(priority: .userInitiated) {
            await transcriber.run(language: language, events: events)
        }
    }

    // MARK: - Altyazı akışı

    private func updatePartial(_ text: String, language: String?) {
        guard store.isCapturing || text.isEmpty else { return }
        store.partialOriginal = text
        guard !text.isEmpty else {
            store.partialTranslation = nil
            return
        }
        let needs = translator.needsTranslation(detectedLanguage: language)
        store.partialNeedsTranslation = needs
        guard needs else { return }
        translator.translatePartial(text) { [weak store] translation in
            guard let store, !store.partialOriginal.isEmpty, let translation else { return }
            store.partialTranslation = translation
        }
    }

    private func confirm(_ text: String, language: String?) {
        let needs = translator.needsTranslation(detectedLanguage: language)
        var line = SubtitleLine(original: text, translation: nil, needsTranslation: needs)
        // Geçici çeviri aynı metne aitse, kesin çeviri gelene kadar onu göster.
        if needs, store.partialOriginal == text { line.translation = store.partialTranslation }
        store.appendConfirmed(line)
        if store.partialOriginal == text { store.clearPartial() }
        guard needs else { return }
        let id = line.id
        translator.translate(text) { [weak store] translation in
            guard let translation else { return }
            store?.setTranslation(translation, for: id)
        }
    }

    // MARK: - Ayar değişiklikleri

    func languagesChanged() {
        translator.cancelPending()
        translator.configure(source: settings.source, target: settings.target)
        if store.isCapturing { startTranscription() }
    }
}
