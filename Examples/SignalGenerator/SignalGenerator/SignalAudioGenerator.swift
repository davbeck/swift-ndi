import Foundation
import NDI

nonisolated struct SignalAudioGenerator {
	private var sampleIndex: Int64 = 0
	private var sampleRemainder: Int64 = 0

	mutating func makeFrame(
		configuration: SignalConfiguration,
		timecode: NDITimecode
	) throws -> NDISendAudioFrame {
		let sampleRate = configuration.audioSampleRate.value
		let scaledSamples = Int64(sampleRate) * Int64(configuration.frameRate.denominator) + sampleRemainder
		let numberOfSamples = Int(scaledSamples / Int64(configuration.frameRate.numerator))
		sampleRemainder = scaledSamples % Int64(configuration.frameRate.numerator)

		let amplitude = pow(10, configuration.toneLevel / 20)
		let angularFrequency = 2 * Double.pi * configuration.toneFrequency
		let samples = (0 ..< numberOfSamples).map { offset in
			let time = Double(sampleIndex + Int64(offset)) / Double(sampleRate)
			return Float(sin(angularFrequency * time) * amplitude)
		}
		sampleIndex += Int64(numberOfSamples)

		return try NDISendAudioFrame(
			planarSamples: Array(repeating: samples, count: configuration.audioChannels.count),
			sampleRate: sampleRate,
			timecode: timecode,
			metadata: #"<audio_source name="Sine Tone"/>"#
		)
	}
}
