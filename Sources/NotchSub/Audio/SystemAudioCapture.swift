import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioCaptureError: LocalizedError {
    case coreAudio(String, OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case let .coreAudio(what, status): "\(what) (OSStatus \(status))"
        case .unsupportedFormat: L("Unsupported audio format")
        }
    }
}

/// Mikrofonu değil, yalnızca bilgisayarın çaldığı sesi (tüm uygulamalar) yakalar.
/// Core Audio Process Tap (macOS 14.2+) + özel bir aggregate device kullanır.
/// Çıkış: 16 kHz mono Float32 örnekler (Whisper'ın beklediği biçim).
final class SystemAudioCapture: @unchecked Sendable {
    static let targetSampleRate: Double = 16_000

    /// Ses işleme kuyruğunda çağrılır.
    var onSamples: (([Float]) -> Void)?
    /// RMS seviyesi (0...1), ses işleme kuyruğunda çağrılır.
    var onLevel: ((Float) -> Void)?
    /// Varsayılan çıkış aygıtı değişince (ör. kulaklık takıldı) çağrılır.
    var onDefaultOutputChanged: (() -> Void)?

    private let queue = DispatchQueue(label: "notchsub.audio", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var monoFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: SystemAudioCapture.targetSampleRate,
        channels: 1,
        interleaved: false
    )!
    private var outputListener: AudioObjectPropertyListenerBlock?

    private(set) var isRunning = false

    init() {
        installOutputListener()
    }

    deinit {
        stop()
    }

    // MARK: - Start / stop

    func start() throws {
        guard !isRunning else { return }
        do {
            try createTapAndAggregate()
            isRunning = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
        converter = nil
        isRunning = false
    }

    private func createTapAndAggregate() throws {
        // Tüm sistem sesini yakala (hiçbir süreci hariç tutma). Mikrofon dahil değildir.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "NotchSub System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), L("Could not create the system audio tap"))
        tapID = tap

        var tapFormat = try readTapFormat(tap)
        guard let sourceFormat = AVAudioFormat(streamDescription: &tapFormat),
              sourceFormat.commonFormat == .pcmFormatFloat32
        else { throw AudioCaptureError.unsupportedFormat }

        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchSub Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ],
            ],
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
            L("Could not create the audio device")
        )
        aggregateID = aggregate

        let mono = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!
        monoFormat = mono
        converter = AVAudioConverter(from: mono, to: outputFormat)

        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) { [weak self] _, inInputData, _, _, _ in
                self?.process(inInputData, sourceFormat: sourceFormat)
            },
            L("Could not create the audio handler")
        )
        try check(AudioDeviceStart(aggregate, procID), L("Could not start audio capture"))
    }

    // MARK: - Processing

    private func process(_ bufferList: UnsafePointer<AudioBufferList>, sourceFormat: AVAudioFormat) {
        guard let monoFormat, let converter,
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: bufferList, deallocator: nil),
              let channels = input.floatChannelData
        else { return }

        let frames = Int(input.frameLength)
        guard frames > 0, let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        mono.frameLength = AVAudioFrameCount(frames)

        // Kanalları tek kanala indir.
        let channelCount = Int(sourceFormat.channelCount)
        let out = mono.floatChannelData![0]
        let scale = 1 / Float(channelCount)
        var sumSquares: Float = 0
        if sourceFormat.isInterleaved {
            let data = channels[0]
            for i in 0 ..< frames {
                var sample: Float = 0
                for c in 0 ..< channelCount { sample += data[i * channelCount + c] }
                sample *= scale
                out[i] = sample
                sumSquares += sample * sample
            }
        } else {
            for i in 0 ..< frames {
                var sample: Float = 0
                for c in 0 ..< channelCount { sample += channels[c][i] }
                sample *= scale
                out[i] = sample
                sumSquares += sample * sample
            }
        }
        onLevel?(sqrt(sumSquares / Float(frames)))

        // 16 kHz'e dönüştür.
        let ratio = outputFormat.sampleRate / monoFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return mono
        }
        guard error == nil, converted.frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: converted.floatChannelData![0], count: Int(converted.frameLength)))
        onSamples?(samples)
    }

    // MARK: - Core Audio helpers

    private func readTapFormat(_ tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), L("Could not read the audio format"))
        return format
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw AudioCaptureError.coreAudio(L("Output device not found"), status) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw AudioCaptureError.coreAudio(L("Could not read the output device ID"), status) }
        return uid.takeRetainedValue() as String
    }

    private func installOutputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onDefaultOutputChanged?()
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
    }

    private func check(_ status: OSStatus, _ message: String) throws {
        guard status == noErr else { throw AudioCaptureError.coreAudio(message, status) }
    }
}
