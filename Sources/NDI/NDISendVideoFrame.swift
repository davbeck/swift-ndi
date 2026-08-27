//
//  NDISendVideoFrame.swift
//  swift-ndi
//
//  Created by David Beck on 8/26/26.
//

import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// An error that prevents a pixel buffer from being represented by NDI.
public enum NDISendVideoFrameError: Error, Equatable, Sendable {
	/// The pixel buffer uses a format other than BGRA or UYVY.
	case unsupportedPixelFormat(OSType)
	/// The frame rate is invalid, nonpositive, or cannot be represented by the NDI SDK.
	case invalidFrameRate
	/// Core Video could not lock the pixel buffer for reading.
	case couldNotLockPixelBuffer(CVReturn)
	/// The locked pixel buffer has no accessible base address.
	case missingPixelBufferBaseAddress
}

/// A progressive video frame to send over NDI.
///
/// The frame supports BGRA (`kCVPixelFormatType_32BGRA`) and UYVY
/// (`kCVPixelFormatType_422YpCbCr8`) pixel buffers. It uses the pixel buffer's
/// dimensions and row stride, and keeps the buffer alive until a synchronous
/// send completes.
public struct NDISendVideoFrame: @unchecked Sendable {
	private let pixelBuffer: CVPixelBuffer
	private let fourCC: NDIlib_FourCC_video_type_e
	private let frameRateNumerator: Int32
	private let frameRateDenominator: Int32
	private let timecode: NDITimecode

	/// Creates a progressive NDI video frame backed by a Core Video pixel buffer.
	///
	/// Express fractional rates as a rational `CMTime`. For example,
	/// `CMTime(value: 30_000, timescale: 1_001)` represents 29.97 fps.
	///
	/// - Parameters:
	///   - pixelBuffer: A BGRA or UYVY pixel buffer containing the video data.
	///   - frameRate: The frame-rate numerator and denominator, represented by
	///     the time's `value` and `timescale`, respectively.
	///   - timecode: The frame timecode. The default uses the current system time.
	/// - Throws: ``NDISendVideoFrameError`` when the frame rate or pixel format
	///   is unsupported.
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

	func withNDIFrame<R>(
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
