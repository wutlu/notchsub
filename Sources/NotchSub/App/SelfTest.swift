import Foundation
import WhisperKit

/// Geliştirme aracı: `NotchSub --selftest <ses dosyası>`
/// Dosyayı gerçek zamanlı hızda akış motoruna verir ve olayları yazdırır (hoparlör kullanmaz).
enum SelfTest {
    static func run(path: String, variant: String) async {
        let engine = WhisperEngine()
        let start = Date()
        await engine.load(variant: variant) { state in print("[engine]", state) }
        print("[load] \(String(format: "%.1f", Date().timeIntervalSince(start))) sn")

        guard let samples = try? AudioProcessor.loadAudioAsFloatArray(fromPath: path) else {
            print("Ses dosyası okunamadı"); return
        }
        let buffer = SampleBuffer()
        let transcriber = StreamingTranscriber(engine: engine, buffer: buffer)
        let t0 = Date()
        let stamp = { String(format: "%5.2f", Date().timeIntervalSince(t0)) }
        let events = StreamingTranscriber.Events(
            partial: { text, _ in if !text.isEmpty { print("\(stamp()) ~ \(text)") } },
            confirmed: { text, lang in print("\(stamp()) ✓ [\(lang ?? "?")] \(text)") },
            error: { print("hata:", $0) }
        )
        let task = Task.detached { await transcriber.run(language: "en", events: events) }
        let chunk = 1600 // 100 ms
        for offset in stride(from: 0, to: samples.count, by: chunk) {
            buffer.append(Array(samples[offset ..< min(offset + chunk, samples.count)]))
            try? await Task.sleep(for: .milliseconds(100))
        }
        buffer.append([Float](repeating: 0, count: 16000 * 2)) // sondaki sessizlik
        try? await Task.sleep(for: .seconds(4))
        task.cancel()
    }
}
