import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// An error that prevents an audio frame from being represented by NDI.
public enum NDISendAudioFrameError: Error, Equatable, Sendable {
	/// The sample rate is not a positive 32-bit integer.
	case invalidSampleRate
	/// No channel samples were supplied.
	case noChannels
	/// The channels do not all contain the same number of samples.
	case inconsistentSampleCounts
	/// The number of channels cannot be represented by the NDI SDK.
	case tooManyChannels
	/// The number of samples per channel cannot be represented by the NDI SDK.
	case tooManySamples
}

/// A frame of planar, 32-bit floating-point audio to send over NDI.
///
/// Samples are stored channel by channel. Each channel must contain the same
/// number of samples, and the frame keeps the sample storage alive until a
/// synchronous send completes.
public struct NDISendAudioFrame: Sendable {
	/// The number of samples per second, in hertz.
	public let sampleRate: Int
	/// The number of audio channels in the frame.
	public let numberOfChannels: Int
	/// The number of audio samples in each channel.
	public let numberOfSamples: Int
	/// The frame's timecode, expressed in 100-nanosecond intervals.
	public let timecode: NDITimecode
	/// Per-frame metadata as a null-terminated UTF-8 XML string, or `nil` when absent.
	public let metadata: String?

	private let samples: [Float]

	/// Creates a planar floating-point audio frame.
	///
	/// - Parameters:
	///   - planarSamples: One array per channel. Every channel must contain the
	///     same number of samples.
	///   - sampleRate: The sample rate in hertz.
	///   - timecode: The frame timecode. The default uses the current system time.
	///   - metadata: Optional per-frame metadata in UTF-8 XML format.
	/// - Throws: ``NDISendAudioFrameError`` when the sample rate, channel count,
	///   or per-channel sample counts cannot form a valid NDI audio frame.
	public init(
		planarSamples: [[Float]],
		sampleRate: Int = 48000,
		timecode: NDITimecode = .now,
		metadata: String? = nil
	) throws {
		guard sampleRate > 0, Int32(exactly: sampleRate) != nil else {
			throw NDISendAudioFrameError.invalidSampleRate
		}
		guard let firstChannel = planarSamples.first else {
			throw NDISendAudioFrameError.noChannels
		}
		guard Int32(exactly: planarSamples.count) != nil else {
			throw NDISendAudioFrameError.tooManyChannels
		}
		guard Int32(exactly: firstChannel.count) != nil else {
			throw NDISendAudioFrameError.tooManySamples
		}
		guard planarSamples.allSatisfy({ $0.count == firstChannel.count }) else {
			throw NDISendAudioFrameError.inconsistentSampleCounts
		}

		self.sampleRate = sampleRate
		numberOfChannels = planarSamples.count
		numberOfSamples = firstChannel.count
		self.timecode = timecode
		self.metadata = metadata
		samples = planarSamples.flatMap { $0 }
	}

	func withNDIFrame<R>(_ operation: (UnsafePointer<NDIlib_audio_frame_v3_t>) -> R) -> R {
		samples.withUnsafeBufferPointer { samples in
			withMetadataCString { metadata in
				var frame = NDIlib_audio_frame_v3_t(
					sample_rate: Int32(sampleRate),
					no_channels: Int32(numberOfChannels),
					no_samples: Int32(numberOfSamples),
					timecode: timecode.rawValue,
					FourCC: NDIlib_FourCC_audio_type_FLTP,
					p_data: samples.baseAddress.map {
						UnsafeMutableRawPointer(mutating: $0).assumingMemoryBound(to: UInt8.self)
					},
					.init(channel_stride_in_bytes: Int32(numberOfSamples * MemoryLayout<Float>.stride)),
					p_metadata: metadata,
					timestamp: 0
				)
				return withUnsafePointer(to: &frame, operation)
			}
		}
	}

	private func withMetadataCString<R>(_ operation: (UnsafePointer<CChar>?) -> R) -> R {
		if let metadata {
			return metadata.withCString(operation)
		}
		return operation(nil)
	}
}
