import AVFoundation
import Combine
import Foundation

enum JarvisProcessingSoundPattern {
    static let sampleRate = 44_100.0
    static let duration = 1.6

    static func samples(
        sampleRate: Double = sampleRate,
        duration: Double = duration
    ) -> [Float] {
        let count = max(1, Int(sampleRate * duration))
        let glitchStarts = [0.08, 0.17, 0.43, 0.51, 0.84, 1.08, 1.17, 1.42]

        return (0 ..< count).map { index in
            let time = Double(index) / sampleRate
            let edgeFade = min(1, time / 0.018, (duration - time) / 0.018)
            let hum = sin(.pi * 2 * 62 * time) * 0.055
                + sin(.pi * 2 * 124 * time) * 0.022
            var glitches = 0.0

            for (pulse, start) in glitchStarts.enumerated() {
                let elapsed = time - start
                let width = 0.028 + Double(pulse % 3) * 0.009
                guard elapsed >= 0, elapsed < width else { continue }
                let envelope = 1 - elapsed / width
                let carrier = sin(.pi * 2 * (1_080 + Double(pulse) * 137) * elapsed)
                let digital = carrier >= 0 ? 1.0 : -1.0
                let staticGrain = sin(.pi * 2 * (4_700 + Double(pulse) * 211) * elapsed)
                glitches += (digital * 0.27 + staticGrain * 0.09) * envelope
            }

            let stepped = ((hum + glitches) * 18).rounded() / 18
            return Float(max(-0.42, min(0.42, stepped)) * max(0, edgeFade))
        }
    }
}

@MainActor
final class JarvisProcessingSoundController: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?
    private var isPlaying = false

    init() {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: JarvisProcessingSoundPattern.sampleRate,
            channels: 2
        )
        buffer = Self.makeBuffer(format: format)
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        player.volume = 0.16
    }

    func setThinking(_ thinking: Bool) {
        thinking ? start() : stop()
    }

    func stop() {
        guard isPlaying || engine.isRunning else { return }
        player.stop()
        engine.pause()
        isPlaying = false
    }

    private func start() {
        guard !isPlaying, let buffer else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isPlaying = true
        } catch {
            stop()
        }
    }

    private static func makeBuffer(format: AVAudioFormat?) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let samples = JarvisProcessingSoundPattern.samples(sampleRate: format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        guard let channels = buffer.floatChannelData else { return nil }
        for channel in 0 ..< Int(format.channelCount) {
            for (index, sample) in samples.enumerated() {
                channels[channel][index] = sample
            }
        }
        return buffer
    }
}
