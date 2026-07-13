import AVFoundation
import Foundation

func configureAudioSession() {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    do {
        try session.setCategory(
            .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker]
        )
        try session.setActive(true)
    } catch {
        print("audio: session configuration failed: \(error)")
    }
    #endif
}

@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double
    private(set) var bytesPlayed = 0
    private var started = false

    init(sampleRate: Double = 24000) {
        self.sampleRate = sampleRate
        self.format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        )!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ pcm16: Data) {
        if !started {
            configureAudioSession()
            do {
                try engine.start()
                player.play()
                started = true
            } catch {
                print("audio: engine start failed: \(error)")
                return
            }
        }
        let frames = pcm16.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm16.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<frames {
                channel[index] = Float(Int16(littleEndian: samples[index])) / 32768
            }
        }
        player.scheduleBuffer(buffer)
        bytesPlayed += pcm16.count
    }

    var playedMilliseconds: Int {
        Int(Double(bytesPlayed / 2) * 1000 / sampleRate)
    }

    func stop() {
        player.stop()
        if started { engine.stop() }
        started = false
    }
}

final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false

    func start(
        sampleRate: Double = 24000,
        onChunk: @escaping @Sendable (Data) -> Void
    ) throws {
        guard !isRunning else { return }
        configureAudioSession()
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0 else {
            throw NSError(
                domain: "RealtimeDemo", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No microphone input available"]
            )
        }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
            channels: 1, interleaved: true
        ), let converter = AVAudioConverter(from: hardware, to: target) else {
            throw NSError(
                domain: "RealtimeDemo", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not build audio converter"]
            )
        }

        input.installTap(onBus: 0, bufferSize: 2400, format: hardware) { buffer, _ in
            let capacity = AVAudioFrameCount(
                Double(buffer.frameLength) * sampleRate / hardware.sampleRate
            ) + 16
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: target, frameCapacity: capacity
            ) else { return }
            var fed = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard conversionError == nil,
                  converted.frameLength > 0,
                  let channel = converted.int16ChannelData?[0]
            else { return }
            onChunk(Data(bytes: channel, count: Int(converted.frameLength) * 2))
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
