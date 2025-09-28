import CoreGraphics
import CoreImage
import libNDI

public final class NDIMetadataFrame: @unchecked Sendable {
	public let receiver: NDIReceiver
	fileprivate var ref: NDIlib_metadata_frame_t

	init(_ ref: NDIlib_metadata_frame_t, receiver: NDIReceiver) {
		self.ref = ref
		self.receiver = receiver
	}

	deinit {
		receiver.ndi.NDIlib_recv_free_metadata(receiver.pNDI_recv, &ref)
	}

	/// The timecode of this frame.
	public var timecode: NDITimecode {
		NDITimecode(rawValue: ref.timecode)
	}

	public var value: String? {
		guard let p_data = ref.p_data else { return nil }
		if ref.length == 0 {
			return String(cString: p_data)
		} else {
			return String(bytes: Data(bytes: p_data, count: Int(ref.length)), encoding: .utf8)
		}
	}
}
