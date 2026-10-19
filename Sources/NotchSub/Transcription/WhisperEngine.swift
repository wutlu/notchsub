import Foundation
import WhisperKit

enum EngineState: Equatable {
    case idle
    case downloading(Double)
    case loading
    case ready
    case failed(String)
}

/// WhisperKit sarmalayıcısı: modeli indirir, yükler ve ses parçalarını yazıya döker.
final class WhisperEngine: @unchecked Sendable {
    private var whisper: WhisperKit?
    private(set) var loadedVariant: String?

    static let modelsBase: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchSub", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let repo = "argmaxinc/whisperkit-coreml"

    /// Daha önce indirilmiş model klasörü (çevrimdışı açılış için ağa gitmeden kullanılır).
    private static func localModelFolder(_ variant: String) -> URL? {
        let folder = modelsBase
            .appendingPathComponent("models/\(repo)/\(variant)", isDirectory: true)
        let required = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        let complete = required.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        return complete ? folder : nil
    }

    func load(variant: String, onState: @escaping @Sendable (EngineState) -> Void) async {
        whisper = nil
        loadedVariant = nil
        do {
            let folder: URL
            if let local = Self.localModelFolder(variant) {
                folder = local
            } else {
                onState(.downloading(0))
                folder = try await WhisperKit.download(
                    variant: variant,
                    downloadBase: Self.modelsBase,
                    from: Self.repo
                ) { progress in
                    onState(.downloading(progress.fractionCompleted))
                }
            }
            onState(.loading)
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            whisper = try await WhisperKit(config)
            loadedVariant = variant
            onState(.ready)
        } catch {
            onState(.failed(error.localizedDescription))
        }
    }

    struct Output {
        var segments: [TranscriptionSegment]
        var language: String?
    }

    /// - Parameter language: Whisper dil kodu; `nil` ise dil otomatik algılanır.
    func transcribe(_ samples: [Float], language: String?) async throws -> Output {
        guard let whisper else { return Output(segments: [], language: nil) }
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return Output(
            segments: results.flatMap(\.segments),
            language: results.first?.language
        )
    }
}
