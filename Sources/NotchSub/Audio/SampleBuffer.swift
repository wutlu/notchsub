import Foundation

/// Ses kuyruğundan yazılan, transkripsiyon döngüsünden okunan, kilitli örnek tamponu.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    /// Şimdiye kadar eklenen toplam örnek sayısı (yeni ses gelip gelmediğini anlamak için).
    private var totalAppended = 0
    private let maxSamples: Int

    init(maxSeconds: Double = 30, sampleRate: Double = SystemAudioCapture.targetSampleRate) {
        maxSamples = Int(maxSeconds * sampleRate)
    }

    func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
        totalAppended += newSamples.count
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func snapshot() -> (samples: [Float], total: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, totalAppended)
    }

    /// Baştan `count` örneği atar (onaylanmış konuşma).
    func dropFirst(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        samples.removeFirst(min(max(count, 0), samples.count))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}

/// Basit enerji tabanlı ses etkinliği algılayıcı. Sistem sesi dijital ve temiz olduğu için yeterli.
enum EnergyVAD {
    static let frameLength = 480 // 30 ms @ 16 kHz
    static let threshold: Float = 0.006

    private static func frameEnergies(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameLength else { return [] }
        return stride(from: 0, to: samples.count - frameLength + 1, by: frameLength).map { start in
            var sum: Float = 0
            for i in start ..< start + frameLength { sum += samples[i] * samples[i] }
            return sqrt(sum / Float(frameLength))
        }
    }

    /// En az ~150 ms sesli bölüm var mı?
    static func hasVoice(_ samples: [Float]) -> Bool {
        frameEnergies(samples).filter { $0 > threshold }.count >= 5
    }

    /// [from, to] saniye aralığında en düşük enerjili ~90 ms'lik pencerenin ortası (örnek indeksi).
    static func quietestPoint(
        in samples: [Float],
        from: Double,
        to: Double,
        sampleRate: Double = SystemAudioCapture.targetSampleRate
    ) -> Int {
        let energies = frameEnergies(samples)
        let window = 3
        let first = max(0, Int(from * sampleRate) / frameLength)
        let last = min(energies.count - window, Int(to * sampleRate) / frameLength)
        guard first <= last else { return Int(max(0, from) * sampleRate) }
        var best = first
        var bestEnergy = Float.greatestFiniteMagnitude
        for start in first ... last {
            let energy = energies[start ..< start + window].reduce(0, +)
            if energy < bestEnergy {
                bestEnergy = energy
                best = start
            }
        }
        return (best + window / 2) * frameLength + frameLength / 2
    }

    /// Sondaki kesintisiz sessizlik süresi (saniye).
    static func trailingSilence(_ samples: [Float], sampleRate: Double = SystemAudioCapture.targetSampleRate) -> Double {
        let energies = frameEnergies(samples)
        var silentFrames = 0
        for energy in energies.reversed() {
            if energy > threshold { break }
            silentFrames += 1
        }
        return Double(silentFrames * frameLength) / sampleRate
    }
}
