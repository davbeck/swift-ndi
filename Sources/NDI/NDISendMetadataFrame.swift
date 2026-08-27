import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// A UTF-8 XML metadata frame to send over NDI.
public struct NDISendMetadataFrame: Hashable, Sendable {
	/// The metadata payload in XML format.
	public var value: String
	/// The frame's timecode, expressed in 100-nanosecond intervals.
	public var timecode: NDITimecode

	/// Creates a metadata frame.
	///
	/// - Parameters:
	///   - value: The metadata payload in XML format.
	///   - timecode: The frame timecode. The default uses the current system time.
	public init(value: String, timecode: NDITimecode = .now) {
		self.value = value
		self.timecode = timecode
	}

	func withNDIFrame<R>(_ operation: (UnsafePointer<NDIlib_metadata_frame_t>) -> R) -> R {
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
