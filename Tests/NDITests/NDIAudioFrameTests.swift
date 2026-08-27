import AVFoundation
import CoreMedia
import libNDI
import Testing
@testable import NDI

struct NDIAudioFrameTests {
	@Test
	func interleavedSampleBufferUsesPerSampleTiming() throws {
		let sampleRate: Int32 = 48000
		let numberOfChannels: Int32 = 2
		let numberOfSamples: Int32 = 960
		let timecode: Int64 = 10_000_000

		let audioData = UnsafeMutablePointer<Float32>.allocate(capacity: Int(numberOfChannels * numberOfSamples))
		defer { audioData.deallocate() }

		for channel in 0 ..< Int(numberOfChannels) {
			for sample in 0 ..< Int(numberOfSamples) {
				audioData[channel * Int(numberOfSamples) + sample] = Float32(channel + sample)
			}
		}

		let frame = NDIAudioFrame(ref: NDIlib_audio_frame_v3_t(
			sample_rate: sampleRate,
			no_channels: numberOfChannels,
			no_samples: numberOfSamples,
			timecode: timecode,
			FourCC: NDIlib_FourCC_audio_type_FLTP,
			p_data: UnsafeMutableRawPointer(audioData).assumingMemoryBound(to: UInt8.self),
			.init(channel_stride_in_bytes: numberOfSamples * Int32(MemoryLayout<Float32>.size)),
			p_metadata: nil,
			timestamp: NDIlib_recv_timestamp_undefined
		))

		let sampleBuffer = try frame.sampleBuffer(interleaved: true)

		#expect(sampleBuffer.numSamples == Int(numberOfSamples))
		#expect(sampleBuffer.outputPresentationTimeStamp == CMTime(value: timecode, timescale: CMTimeScale(NDI.timescale)))
		#expect(sampleBuffer.outputDuration == CMTime(value: CMTimeValue(numberOfSamples), timescale: sampleRate))
	}

	@Test
	func interleavedSampleBufferInterleavesPlanarAudio() throws {
		let sampleRate: Int32 = 48000
		let numberOfChannels: Int32 = 2
		let numberOfSamples: Int32 = 3

		let audioData = UnsafeMutablePointer<Float32>.allocate(capacity: Int(numberOfChannels * numberOfSamples))
		defer { audioData.deallocate() }

		audioData[0] = 1
		audioData[1] = 2
		audioData[2] = 3
		audioData[3] = 10
		audioData[4] = 20
		audioData[5] = 30

		let frame = NDIAudioFrame(ref: NDIlib_audio_frame_v3_t(
			sample_rate: sampleRate,
			no_channels: numberOfChannels,
			no_samples: numberOfSamples,
			timecode: 0,
			FourCC: NDIlib_FourCC_audio_type_FLTP,
			p_data: UnsafeMutableRawPointer(audioData).assumingMemoryBound(to: UInt8.self),
			.init(channel_stride_in_bytes: numberOfSamples * Int32(MemoryLayout<Float32>.size)),
			p_metadata: nil,
			timestamp: NDIlib_recv_timestamp_undefined
		))

		let sampleBuffer = try frame.sampleBuffer(interleaved: true)
		let blockBuffer = try #require(sampleBuffer.dataBuffer)
		var interleavedData = [Float32](repeating: 0, count: Int(numberOfChannels * numberOfSamples))

		let status = interleavedData.withUnsafeMutableBytes { bytes in
			CMBlockBufferCopyDataBytes(
				blockBuffer,
				atOffset: 0,
				dataLength: bytes.count,
				destination: bytes.baseAddress!
			)
		}

		#expect(status == kCMBlockBufferNoErr)
		#expect(interleavedData == [1, 10, 2, 20, 3, 30])
	}
}
