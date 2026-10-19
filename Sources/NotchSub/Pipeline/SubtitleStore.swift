import Foundation
import Observation

struct SubtitleLine: Identifiable, Equatable {
    let id = UUID()
    var original: String
    var translation: String?
    /// Konuşma dili hedef dille aynıysa çeviri gösterilmez.
    var needsTranslation: Bool
}

@MainActor
@Observable
final class SubtitleStore {
    var lines: [SubtitleLine] = []
    var partialOriginal = ""
    var partialTranslation: String?
    var partialNeedsTranslation = true

    var engineState: EngineState = .idle
    /// Kullanıcı dinlemek istiyor (model hazır değilse hazır olunca başlar).
    var wantsListening = false
    /// Ses gerçekten yakalanıyor.
    var isCapturing = false
    var level: Float = 0
    var errorMessage: String?

    func appendConfirmed(_ line: SubtitleLine) {
        lines.append(line)
        if lines.count > 60 { lines.removeFirst(lines.count - 60) }
    }

    func setTranslation(_ translation: String, for id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translation = translation
    }

    func clearPartial() {
        partialOriginal = ""
        partialTranslation = nil
    }

    func clearAll() {
        lines.removeAll()
        clearPartial()
    }
}
