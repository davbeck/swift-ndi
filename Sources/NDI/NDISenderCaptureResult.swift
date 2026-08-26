//
//  NDISenderCaptureResult.swift
//  SignalGenerator
//
//  Created by David Beck on 8/26/26.
//

import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// The result of polling a sender for messages from connected receivers.
public enum NDISenderCaptureResult: Sendable {
	/// No message arrived before the timeout expired.
	case none
	/// A receiver sent a metadata frame upstream.
	case metadata(NDISenderCapturedMetadataFrame)
	/// The sender's connection status changed.
	case statusChange
	/// The NDI SDK reported an error.
	case error
	/// The NDI SDK returned a frame type this package does not recognize.
	case unknown
}

/// A metadata frame sent upstream by a connected NDI receiver.
///
/// The object owns the SDK buffer and releases it when the object is
/// deallocated. Copy ``value`` or ``timecode`` if they need to outlive the
/// captured frame.
public final class NDISenderCapturedMetadataFrame: @unchecked Sendable {
	private var ref: NDIlib_metadata_frame_t
	private let sender: NDISender

	init(ref: NDIlib_metadata_frame_t, sender: NDISender) {
		self.ref = ref
		self.sender = sender
	}

	deinit {
		sender.freeMetadata(&ref)
	}

	/// The metadata frame's timecode, expressed in 100-nanosecond intervals.
	public var timecode: NDITimecode {
		NDITimecode(rawValue: ref.timecode)
	}

	/// The received UTF-8 XML payload, or `nil` when the frame has no data or is
	/// not valid UTF-8.
	public var value: String? {
		guard let data = ref.p_data else { return nil }
		if ref.length == 0 {
			return String(cString: data)
		}
		let length = max(0, Int(ref.length) - 1)
		return String(bytes: Data(bytes: data, count: length), encoding: .utf8)
	}
}
