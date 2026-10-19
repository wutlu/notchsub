import Foundation
import WhisperKit

/// Sürekli gelen sesi kayan bir pencereyle Whisper'a verir ve sonuçları
/// "geçici" (hâlâ değişebilir) ve "kesin" (onaylanmış) olarak ayırır.
///
/// Strateji:
/// - Son onaylanan noktadan itibaren biriken ses her turda baştan yazıya dökülür.
/// - Birden fazla segment varsa sonuncusu hariç hepsi onaylanır ve sesi tampondan atılır.
/// - Sonda ≥0.6 sn sessizlik varsa ya da pencere 20 sn'yi aştıysa hepsi onaylanır.
final class StreamingTranscriber: @unchecked Sendable {
    struct Events {
        var partial: @Sendable (_ text: String, _ language: String?) -> Void
        var confirmed: @Sendable (_ text: String, _ language: String?) -> Void
        var error: @Sendable (_ message: String) -> Void
    }

    private let engine: WhisperEngine
    private let buffer: SampleBuffer
    private let sampleRate = SystemAudioCapture.targetSampleRate

    private let minAudioSeconds = 0.6
    private let minNewAudioSeconds = 0.35
    private let finalizeSilenceSeconds = 0.6
    private let maxWindowSeconds = 20.0

    init(engine: WhisperEngine, buffer: SampleBuffer) {
        self.engine = engine
        self.buffer = buffer
    }

    func run(language: String?, events: Events) async {
        var lastTotal = 0
        var pendingPartial = ""
        var pendingLanguage: String?

        func flushPartial() {
            if !pendingPartial.isEmpty {
                events.confirmed(pendingPartial, pendingLanguage)
                pendingPartial = ""
                events.partial("", nil)
            }
        }

        while !Task.isCancelled {
            let (audio, total) = buffer.snapshot()
            let newSeconds = Double(total - lastTotal) / sampleRate
            let duration = Double(audio.count) / sampleRate

            guard duration >= minAudioSeconds, newSeconds >= minNewAudioSeconds else {
                try? await Task.sleep(for: .milliseconds(80))
                continue
            }
            lastTotal = total

            // Konuşma yoksa bekleyen metni kesinleştir, sessiz sesi at.
            guard EnergyVAD.hasVoice(audio) else {
                flushPartial()
                buffer.dropFirst(audio.count - Int(0.3 * sampleRate))
                continue
            }

            let output: WhisperEngine.Output
            do {
                output = try await engine.transcribe(audio, language: language)
            } catch {
                if Task.isCancelled { break }
                events.error(error.localizedDescription)
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }
            if Task.isCancelled { break }

            let segments = output.segments.compactMap(Self.clean)
            let detected = output.language ?? language

            if segments.isEmpty {
                if duration > 8 {
                    flushPartial()
                    buffer.dropFirst(audio.count - Int(0.3 * sampleRate))
                }
                continue
            }

            let silence = EnergyVAD.trailingSilence(audio)
            if silence >= finalizeSilenceSeconds || duration >= maxWindowSeconds {
                // Cümle bitti: hepsini onayla.
                for segment in segments { events.confirmed(segment.text, detected) }
                pendingPartial = ""
                events.partial("", nil)
                let lastEnd = Double(segments.last!.end)
                let endSample = silence >= finalizeSilenceSeconds
                    ? audio.count - Int(0.2 * sampleRate)
                    : EnergyVAD.quietestPoint(in: audio, from: lastEnd - 0.4, to: lastEnd + 0.2)
                buffer.dropFirst(min(endSample, audio.count))
            } else if segments.count >= 2 {
                // Son segment hariç hepsini onayla.
                let stable = segments.dropLast()
                for segment in stable { events.confirmed(segment.text, detected) }
                // Zaman damgaları kelime sınırına tam oturmaz; sınır civarındaki en sessiz noktadan kes.
                let cut = EnergyVAD.quietestPoint(
                    in: audio,
                    from: Double(min(stable.last!.end, segments.last!.start)) - 0.4,
                    to: Double(max(stable.last!.end, segments.last!.start)) + 0.2
                )
                buffer.dropFirst(min(cut, audio.count))
                pendingPartial = segments.last!.text
                pendingLanguage = detected
                events.partial(pendingPartial, detected)
            } else {
                pendingPartial = segments[0].text
                pendingLanguage = detected
                events.partial(pendingPartial, detected)
            }
        }
    }

    // MARK: - Temizlik ve halüsinasyon filtresi

    private struct CleanSegment {
        var text: String
        var start: Float
        var end: Float
    }

    private static let specialTokens = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>")

    /// Whisper'ın sessizlik/müzikte sık uydurduğu kalıplar.
    private static let hallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching", "thank you very much",
        "please subscribe", "subtitles by the amaraorg community", "you", "bye",
        "altyazı mk", "izlediğiniz için teşekkürler", "teşekkürler",
    ]

    private static func clean(_ segment: TranscriptionSegment) -> CleanSegment? {
        var text = segment.text
        text = specialTokens.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // [Music], (applause), ♪ ... gibi açıklamalar
        if let first = text.first, let last = text.last,
           "[(*♪".contains(first), "])*♪".contains(last) { return nil }
        if text.allSatisfy({ $0.isPunctuation || $0.isWhitespace || $0 == "♪" }) { return nil }

        if segment.noSpeechProb > 0.6, segment.avgLogprob < -0.7 { return nil }
        if segment.compressionRatio > 2.6 { return nil }

        let normalized = text.lowercased()
            .filter { $0.isLetter || $0.isWhitespace }
            .trimmingCharacters(in: .whitespaces)
        if hallucinations.contains(normalized) { return nil }

        return CleanSegment(text: text, start: segment.start, end: segment.end)
    }
}
