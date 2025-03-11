import AVFoundation
import CoreMedia
import libNDI

public class NDIAudioFrame: @unchecked Sendable {
	fileprivate var ref: NDIlib_audio_frame_v3_t

	fileprivate init(ref: NDIlib_audio_frame_v3_t) {
		self.ref = ref
	}

	/// The sample-rate of this buffer.
	public var sampleRate: Int {
		.init(ref.sample_rate)
	}

	/// The number of audio channels.
	public var numberOfChannels: Int {
		.init(ref.no_channels)
	}

	/// The number of audio samples per channel.
	public var numberOfSamples: Int {
		.init(ref.no_samples)
	}

	/// Per frame metadata for this frame. This is a NULL terminated UTF8 string that should be in XML format.
	/// If you do not want any metadata then you may specify NULL here.
	public var metadata: String? {
		guard let p_metadata = ref.p_metadata else { return nil }
		return String(cString: p_metadata)
	}

	public var dataByteSize: Int {
		.init(ref.no_channels * ref.channel_stride_in_bytes)
	}

	public var duration: Duration {
		.nanoseconds((Int64(ref.no_samples) * 1_000_000_000) / Int64(ref.sample_rate))
	}

	public func sampleBuffer(in clock: CMSyncProtocol? = nil) throws -> CMSampleBuffer {
		switch ref.FourCC {
		case NDIlib_FourCC_audio_type_FLTP:
			var context = CFAllocatorContext(
				version: 0,
				info: Unmanaged.passRetained(self).toOpaque(),
				retain: nil,
				release: nil,
				copyDescription: nil,
				allocate: nil,
				reallocate: nil,
				deallocate: { _, info in
					guard let info else { return }
					Unmanaged<NDIAudioFrame>.fromOpaque(info).release()
				},
				preferredSize: nil
			)
			let blockAllocator = CFAllocatorCreate(kCFAllocatorDefault, &context)
				.takeUnretainedValue()

			let dataByteSize = ref.no_channels * ref.channel_stride_in_bytes

			var blockBuffer: CMBlockBuffer?
			let status = CMBlockBufferCreateWithMemoryBlock(
				allocator: kCFAllocatorDefault,
				memoryBlock: ref.p_data,
				blockLength: Int(dataByteSize),
				blockAllocator: blockAllocator,
				customBlockSource: nil,
				offsetToData: 0,
				dataLength: Int(dataByteSize),
				flags: 0,
				blockBufferOut: &blockBuffer
			)

			guard status == kCMBlockBufferNoErr, let blockBuffer else {
				throw CMBlockBufferCreateWithMemoryBlockError(status: status)
			}

			var sampleBuffer: CMSampleBuffer?
			let sampleSizeArray: [Int] = [MemoryLayout<Float32>.size]

			var outputDescription = AudioStreamBasicDescription(
				mSampleRate: .init(sampleRate),
				mFormatID: kAudioFormatLinearPCM,
				mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
				mBytesPerPacket: 4, // 32-bit (4 bytes) per sample, per channel
				mFramesPerPacket: 1,
				mBytesPerFrame: 4, // 32-bit (4 bytes) per sample, per channel
				mChannelsPerFrame: .init(numberOfChannels),
				mBitsPerChannel: 32,
				mReserved: 0
			)
			var formatDescription: CMAudioFormatDescription?
			let cmAudioFormatDescriptionCreateStatus = CMAudioFormatDescriptionCreate(
				allocator: nil,
				asbd: &outputDescription,
				layoutSize: 0,
				layout: nil,
				magicCookieSize: 0,
				magicCookie: nil,
				extensions: nil,
				formatDescriptionOut: &formatDescription
			)
			guard cmAudioFormatDescriptionCreateStatus == noErr else {
				throw CMAudioFormatDescriptionCreateError(status: status)
			}

			var presentationTime = CMTime(
				value: ref.timecode,
				timescale: CMTimeScale(NDI.timescale)
			)
			
			if let clock, let ndiClock = CMTimebase.ndi {
				presentationTime = ndiClock.convertTime(presentationTime, to: clock)
			}

			var timingInfo = CMSampleTimingInfo(
				duration: CMTime(value: 1, timescale: ref.sample_rate),
				presentationTimeStamp: presentationTime,
				decodeTimeStamp: presentationTime
			)

			let sampleBufferStatus = CMSampleBufferCreateReady(
				allocator: kCFAllocatorDefault,
				dataBuffer: blockBuffer,
				formatDescription: formatDescription,
				sampleCount: .init(ref.no_samples),
				sampleTimingEntryCount: 1,
				sampleTimingArray: &timingInfo,
				sampleSizeEntryCount: 1,
				sampleSizeArray: sampleSizeArray,
				sampleBufferOut: &sampleBuffer
			)

			guard let sampleBuffer, sampleBufferStatus == noErr else {
				throw CMSampleBufferCreateReadyError(status: sampleBufferStatus)
			}

			return sampleBuffer
		default:
			throw NDIAudioFrameUnrecognizedTypeError(FourCC: ref.FourCC)
		}
	}
}

public final class NDIReceivedAudioFrame: NDIAudioFrame, @unchecked Sendable {
	public let receiver: NDIReceiver

	init(_ ref: NDIlib_audio_frame_v3_t, receiver: NDIReceiver) {
		self.receiver = receiver
		super.init(ref: ref)
	}

	deinit {
		receiver.ndi.NDIlib_recv_free_audio_v3(receiver.pNDI_recv, &ref)
	}

	/// The timecode of this frame.
	public var timecode: NDITimecode {
		NDITimecode(rawValue: ref.timecode)
	}

	/// This is only valid when receiving a frame and is specified as the time that was the exact
	/// moment that the frame was submitted by the sending side and is generated by the SDK.
	public var timestamp: NDITimecode? {
		guard ref.timestamp != NDIlib_recv_timestamp_undefined else { return nil }
		return NDITimecode(rawValue: ref.timestamp)
	}
}

extension NDIAudioFrame: CustomStringConvertible {
	public var description: String {
		let timecode = ref.timecode == NDIlib_send_timecode_synthesize ? "synthesize" : ref.timecode.formatted()
		let timestamp = ref.timestamp == NDIlib_recv_timestamp_undefined ? "undefined" : ref.timestamp.formatted()

		return "<NDIAudioFrame sample_rate: \(sampleRate), no_channels: \(numberOfChannels), no_samples: \(numberOfSamples), timecode: \(ref.timecode), channel_stride_in_bytes: \(ref.channel_stride_in_bytes), p_metadata: \(metadata ?? ""), timestamp: \(timestamp)>"
	}
}

struct NDIAudioFrameUnrecognizedTypeError: Error {
	var FourCC: NDIlib_FourCC_audio_type_e
}

struct CMBlockBufferCreateWithMemoryBlockError: Error {
	var status: OSStatus
}

struct CMAudioFormatDescriptionCreateError: Error {
	var status: OSStatus
}

struct CMSampleBufferCreateReadyError: Error {
	var status: OSStatus
}
