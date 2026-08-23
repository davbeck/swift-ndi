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

public final class NDISender: @unchecked Sendable {
	// NDIlib_send_instance_t is generally thread safe as long as it's not freed before NDIlib_send_send_video_v2_async finishes  (https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-send).

	private let ndi: NDI
	private let sender: NDIlib_send_instance_t

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

	func connectionCount(timeout: Duration = .zero) -> Int {
		Int(ndi.NDIlib_send_get_no_connections(
			sender,
			UInt32(timeout.seconds * 1_000)
		))
	}

	func sourceName() -> String? {
		guard let source = ndi.NDIlib_send_get_source_name(sender) else {
			return nil
		}

		return String(cString: source.pointee.p_ndi_name)
	}

	/// This will add a video frame.
	func send(_ frame: NDISendVideoFrame) throws {
		do {
			try frame.withNDIFrame { frame in
				self.ndi.NDIlib_send_send_video_v2(self.sender, frame)
			}
		} catch {
			throw error
		}
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
