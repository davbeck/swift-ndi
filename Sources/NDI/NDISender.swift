import CoreMedia
import CoreVideo
import Dependencies
import libNDI

public enum NDISendVideoFrameError: Error, Equatable, Sendable {
	case unsupportedPixelFormat(OSType)
	case invalidFrameRate
	case couldNotLockPixelBuffer(CVReturn)
	case missingPixelBufferBaseAddress
}

/// A video frame that keeps its pixel buffer alive until the synchronous NDI send completes.
public struct NDISendVideoFrame: @unchecked Sendable {
	private let pixelBuffer: CVPixelBuffer
	private let fourCC: NDIlib_FourCC_video_type_e
	private let frameRateNumerator: Int32
	private let frameRateDenominator: Int32
	private let timecode: NDITimecode

	public init(
		pixelBuffer: CVPixelBuffer,
		frameRate: CMTime,
		timecode: NDITimecode = .now
	) throws {
		guard
			frameRate.isValid,
			frameRate.value > 0,
			frameRate.timescale > 0,
			let numerator = Int32(exactly: frameRate.value)
		else {
			throw NDISendVideoFrameError.invalidFrameRate
		}

		let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
		switch pixelFormat {
		case kCVPixelFormatType_32BGRA:
			fourCC = NDIlib_FourCC_video_type_BGRA
		case kCVPixelFormatType_422YpCbCr8:
			fourCC = NDIlib_FourCC_video_type_UYVY
		default:
			throw NDISendVideoFrameError.unsupportedPixelFormat(pixelFormat)
		}

		self.pixelBuffer = pixelBuffer
		frameRateNumerator = numerator
		frameRateDenominator = frameRate.timescale
		self.timecode = timecode
	}

	fileprivate func withNDIFrame<R>(
		_ operation: (UnsafePointer<NDIlib_video_frame_v2_t>) -> R
	) throws -> R {
		let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
		guard lockResult == kCVReturnSuccess else {
			throw NDISendVideoFrameError.couldNotLockPixelBuffer(lockResult)
		}
		defer {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
		}

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw NDISendVideoFrameError.missingPixelBufferBaseAddress
		}

		var frame = NDIlib_video_frame_v2_t(
			xres: Int32(CVPixelBufferGetWidth(pixelBuffer)),
			yres: Int32(CVPixelBufferGetHeight(pixelBuffer)),
			FourCC: fourCC,
			frame_rate_N: frameRateNumerator,
			frame_rate_D: frameRateDenominator,
			picture_aspect_ratio: Float(CVPixelBufferGetWidth(pixelBuffer)) / Float(CVPixelBufferGetHeight(pixelBuffer)),
			frame_format_type: NDIlib_frame_format_type_progressive,
			timecode: timecode.rawValue,
			p_data: baseAddress.assumingMemoryBound(to: UInt8.self),
			NDIlib_video_frame_v2_t.__Unnamed_union___Anonymous_field9(
				line_stride_in_bytes: Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))
			),
			p_metadata: nil,
			timestamp: 0
		)
		return withUnsafePointer(to: &frame, operation)
	}
}

public enum NDISendAudioFrameError: Error, Equatable, Sendable {
	case invalidSampleRate
	case noChannels
	case inconsistentSampleCounts
	case tooManyChannels
	case tooManySamples
}

/// Planar, 32-bit floating-point audio that remains alive until a synchronous NDI send completes.
public struct NDISendAudioFrame: Sendable {
	public let sampleRate: Int
	public let numberOfChannels: Int
	public let numberOfSamples: Int
	public let timecode: NDITimecode
	public let metadata: String?

	private let samples: [Float]

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

	fileprivate func withNDIFrame<R>(_ operation: (UnsafePointer<NDIlib_audio_frame_v3_t>) -> R) -> R {
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

public struct NDISendMetadataFrame: Hashable, Sendable {
	public var value: String
	public var timecode: NDITimecode

	public init(value: String, timecode: NDITimecode = .now) {
		self.value = value
		self.timecode = timecode
	}

	fileprivate func withNDIFrame<R>(_ operation: (UnsafePointer<NDIlib_metadata_frame_t>) -> R) -> R {
		value.utf8CString.withUnsafeBufferPointer { value in
			var frame = NDIlib_metadata_frame_t(
				length: Int32(value.count),
				timecode: timecode.rawValue,
				p_data: value.baseAddress.map(UnsafeMutablePointer.init(mutating:))
			)
			return withUnsafePointer(to: &frame, operation)
		}
	}
}

public struct NDISenderTally: Equatable, Sendable {
	public var isOnProgram: Bool
	public var isOnPreview: Bool

	public init(isOnProgram: Bool, isOnPreview: Bool) {
		self.isOnProgram = isOnProgram
		self.isOnPreview = isOnPreview
	}
}

public enum NDISenderCaptureResult: Sendable {
	case none
	case metadata(NDISenderCapturedMetadataFrame)
	case statusChange
	case error
	case unknown
}

public final class NDISenderCapturedMetadataFrame: @unchecked Sendable {
	private var ref: NDIlib_metadata_frame_t
	private let sender: NDISender

	fileprivate init(ref: NDIlib_metadata_frame_t, sender: NDISender) {
		self.ref = ref
		self.sender = sender
	}

	deinit {
		sender.freeMetadata(&ref)
	}

	public var timecode: NDITimecode {
		NDITimecode(rawValue: ref.timecode)
	}

	public var value: String? {
		guard let data = ref.p_data else { return nil }
		if ref.length == 0 {
			return String(cString: data)
		}
		let length = max(0, Int(ref.length) - 1)
		return String(bytes: Data(bytes: data, count: length), encoding: .utf8)
	}
}

public final class NDISender: @unchecked Sendable {
	// NDIlib_send_instance_t is generally thread safe as long as it's not freed before NDIlib_send_send_video_v2_async finishes  (https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-send).

	private let ndi: NDI
	private let sender: NDIlib_send_instance_t

	/// Creates a sender using the process-wide NDI runtime.
	///
	/// Returns `nil` when the NDI runtime cannot be loaded or the SDK cannot create
	/// a sender with the supplied name.
	public convenience init?(name: String) {
		@Dependency(\.ndi) var ndi
		guard let ndi else { return nil }
		self.init(name: name, ndi: ndi)
	}

	init?(name: String, ndi: NDI) {
		self.ndi = ndi

		let sender = name.withCString { name in
			var descriptor = NDIlib_send_create_t(
				p_ndi_name: name,
				p_groups: nil,
				clock_video: false,
				clock_audio: false
			)
			return ndi.NDIlib_send_create(&descriptor)
		}
		guard let sender else { return nil }
		self.sender = sender
	}

	deinit {
		ndi.NDIlib_send_destroy(sender)
	}

	public func connectionCount(timeout: Duration = .zero) -> Int {
		Int(ndi.NDIlib_send_get_no_connections(
			sender,
			UInt32(timeout.seconds * 1000)
		))
	}

	public func sourceName() -> String? {
		guard let source = ndi.NDIlib_send_get_source_name(sender) else {
			return nil
		}

		return String(cString: source.pointee.p_ndi_name)
	}

	/// Adds a video frame synchronously.
	public func send(_ frame: NDISendVideoFrame) throws {
		try frame.withNDIFrame { frame in
			ndi.NDIlib_send_send_video_v2(sender, frame)
		}
	}

	/// Adds a planar floating-point audio frame synchronously.
	public func send(_ frame: NDISendAudioFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_send_audio_v3(sender, $0) }
	}

	/// Sends metadata to all connected receivers.
	public func send(_ frame: NDISendMetadataFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_send_metadata(sender, $0) }
	}

	/// Receives metadata sent back by a connected receiver.
	public func capture(timeout: Duration = .zero) -> NDISenderCaptureResult {
		var metadata = NDIlib_metadata_frame_t(length: 0, timecode: 0, p_data: nil)
		let frameType = ndi.NDIlib_send_capture(
			sender,
			&metadata,
			UInt32(timeout.seconds * 1000)
		)

		switch frameType {
		case NDIlib_frame_type_none:
			return .none
		case NDIlib_frame_type_metadata:
			return .metadata(NDISenderCapturedMetadataFrame(ref: metadata, sender: self))
		case NDIlib_frame_type_status_change:
			return .statusChange
		case NDIlib_frame_type_error:
			return .error
		default:
			return .unknown
		}
	}

	/// Returns a tally update, or `nil` if the state did not change before the timeout.
	public func tally(timeout: Duration = .zero) -> NDISenderTally? {
		var tally = NDIlib_tally_t(on_program: false, on_preview: false)
		guard ndi.NDIlib_send_get_tally(sender, &tally, UInt32(timeout.seconds * 1000)) else {
			return nil
		}
		return NDISenderTally(isOnProgram: tally.on_program, isOnPreview: tally.on_preview)
	}

	/// Clears all metadata automatically sent to newly connected receivers.
	public func clearConnectionMetadata() {
		ndi.NDIlib_send_clear_connection_metadata(sender)
	}

	/// Adds metadata that is sent to existing and future receiver connections.
	public func addConnectionMetadata(_ frame: NDISendMetadataFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_add_connection_metadata(sender, $0) }
	}

	/// Sets the source receivers should use if this sender becomes unavailable.
	public func setFailoverSource(_ source: NDISource?) {
		guard var source = source?.ref else {
			ndi.NDIlib_send_set_failover(sender, nil)
			return
		}
		ndi.NDIlib_send_set_failover(sender, &source)
	}

	fileprivate func freeMetadata(_ metadata: UnsafePointer<NDIlib_metadata_frame_t>) {
		ndi.NDIlib_send_free_metadata(sender, metadata)
	}
}

private final class NDISenderConnectionSubscriptionToken: @unchecked Sendable {
	let id = UUID()
	private let lock = NSLock()
	private var cancelled = false

	func cancel() {
		lock.lock()
		cancelled = true
		lock.unlock()
	}

	var isCancelled: Bool {
		lock.lock()
		defer { lock.unlock() }
		return cancelled
	}
}
