import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// An NDI source that sends video, audio, and metadata to receivers on the network.
///
/// The sender does not clock audio or video submissions. Pace calls to `send(_:)`
/// at the rate represented by each frame. The sender remains advertised until it
/// is deallocated.
public final class NDISender: @unchecked Sendable {
	// NDIlib_send_instance_t is generally thread safe as long as it's not freed before NDIlib_send_send_video_v2_async finishes  (https://docs.ndi.video/all/developing-with-ndi/sdk/ndi-send).

	private let ndi: NDI
	private let sender: NDIlib_send_instance_t

	/// Creates a sender using the process-wide NDI runtime.
	///
	/// - Parameter name: The user-visible source name advertised on the NDI network.
	/// - Returns: A sender, or `nil` when the NDI runtime cannot be loaded or the
	///   SDK cannot create a sender with the supplied name.
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

	/// Returns the current number of receivers connected to this source.
	///
	/// Use the result to avoid rendering or generating media while there are no
	/// receivers. When `timeout` is greater than zero and no receiver is connected,
	/// the call waits up to that duration for a connection.
	///
	/// - Parameter timeout: How long to wait for a receiver connection. Pass zero
	///   to poll without waiting.
	/// - Returns: The number of connected receivers.
	public func connectionCount(timeout: Duration = .zero) -> Int {
		Int(ndi.NDIlib_send_get_no_connections(
			sender,
			UInt32(timeout.seconds * 1000)
		))
	}

	/// Returns the source name advertised by this sender.
	///
	/// NDI normally qualifies the configured name with the machine name when it
	/// advertises the source.
	///
	/// - Returns: The advertised source name, or `nil` if the SDK does not provide one.
	public func sourceName() -> String? {
		guard let source = ndi.NDIlib_send_get_source_name(sender) else {
			return nil
		}

		return String(cString: source.pointee.p_ndi_name)
	}

	/// Sends a video frame synchronously.
	///
	/// The call returns after NDI finishes accessing the frame's pixel buffer.
	///
	/// - Parameter frame: The video frame to send to connected receivers.
	/// - Throws: ``NDISendVideoFrameError`` if the pixel buffer cannot be locked
	///   or accessed for the send.
	public func send(_ frame: NDISendVideoFrame) throws {
		try frame.withNDIFrame { frame in
			ndi.NDIlib_send_send_video_v2(sender, frame)
		}
	}

	/// Sends a planar floating-point audio frame synchronously.
	///
	/// - Parameter frame: The audio frame to send to connected receivers.
	public func send(_ frame: NDISendAudioFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_send_audio_v3(sender, $0) }
	}

	/// Sends metadata to all connected receivers.
	///
	/// - Parameter frame: A UTF-8 XML metadata frame.
	public func send(_ frame: NDISendMetadataFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_send_metadata(sender, $0) }
	}

	/// Waits for a message sent upstream by a connected receiver.
	///
	/// - Parameter timeout: How long to wait for a message. Pass zero to poll
	///   without waiting.
	/// - Returns: The captured message or the reason no metadata was returned.
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

	/// Waits for the program or preview tally state to change.
	///
	/// - Parameter timeout: How long to wait for a change. Pass zero to poll the
	///   current tally state without waiting.
	/// - Returns: The current tally after a change, or `nil` when no change occurs
	///   before the timeout.
	public func tally(timeout: Duration = .zero) -> NDISenderTally? {
		var tally = NDIlib_tally_t(on_program: false, on_preview: false)
		guard ndi.NDIlib_send_get_tally(sender, &tally, UInt32(timeout.seconds * 1000)) else {
			return nil
		}
		return NDISenderTally(isOnProgram: tally.on_program, isOnPreview: tally.on_preview)
	}

	/// Clears all connection metadata queued for receivers.
	///
	/// Connection metadata is sent automatically whenever a new receiver connects.
	public func clearConnectionMetadata() {
		ndi.NDIlib_send_clear_connection_metadata(sender)
	}

	/// Adds metadata to send automatically with receiver connections.
	///
	/// The metadata is queued for each new connection and is also sent immediately
	/// to receivers that are already connected. Call ``clearConnectionMetadata()``
	/// to reset the queue.
	///
	/// - Parameter frame: A UTF-8 XML metadata frame describing the connection.
	public func addConnectionMetadata(_ frame: NDISendMetadataFrame) {
		frame.withNDIFrame { ndi.NDIlib_send_add_connection_metadata(sender, $0) }
	}

	/// Sets the source that receivers should use if this sender becomes unavailable.
	///
	/// Receivers can switch back automatically if this sender returns. Pass `nil`
	/// to clear the failover source.
	///
	/// - Parameter source: The fallback NDI source, or `nil` to remove the fallback.
	public func setFailoverSource(_ source: NDISource?) {
		guard var source = source?.ref else {
			ndi.NDIlib_send_set_failover(sender, nil)
			return
		}
		ndi.NDIlib_send_set_failover(sender, &source)
	}

	func freeMetadata(_ metadata: UnsafePointer<NDIlib_metadata_frame_t>) {
		ndi.NDIlib_send_free_metadata(sender, metadata)
	}
}
