import Dependencies
import libNDI
import Synchronization
import Testing
@testable import NDI

struct NDIReceiverConfigurationTests {
	@Test
	func appliesBandwidthAndLimitsTheDefaultCapturedMedia() throws {
		let probe = ReceiverProbe()
		var ndi = NDI()
		ndi.NDIlib_recv_create_v3 = probe.create
		ndi.NDIlib_recv_destroy = { _ in }
		ndi.NDIlib_recv_capture_v3 = probe.capture

		let receiver = try #require(withDependencies {
			$0.ndi = ndi
		} operation: {
			NDIReceiver(configuration: .init(bandwidth: .audioOnly, capturedMedia: [.audio]))
		})

		#expect(receiver.configuration == .init(bandwidth: .audioOnly, capturedMedia: [.audio]))
		#expect(probe.bandwidth == NDIlib_recv_bandwidth_audio_only)
		_ = receiver.capture()
		#expect(probe.capturedMedia == [.audio])
	}
}

private final class ReceiverProbe: @unchecked Sendable {
	private struct State: Sendable {
		var bandwidth: NDIlib_recv_bandwidth_e?
		var capturedMedia: Set<NDICaptureType> = []
	}

	private let state = Mutex(State())

	var bandwidth: NDIlib_recv_bandwidth_e? {
		state.withLock(\.bandwidth)
	}

	var capturedMedia: Set<NDICaptureType> {
		state.withLock(\.capturedMedia)
	}

	var create: @Sendable (UnsafePointer<NDIlib_recv_create_v3_t>?) -> NDIlib_recv_instance_t? {
		{ [self] descriptor in
			self.state.withLock { $0.bandwidth = descriptor?.pointee.bandwidth }
			return NDIlib_recv_instance_t(bitPattern: 1)
		}
	}

	var capture: @Sendable (
		NDIlib_recv_instance_t?,
		UnsafeMutablePointer<NDIlib_video_frame_v2_t>?,
		UnsafeMutablePointer<NDIlib_audio_frame_v3_t>?,
		UnsafeMutablePointer<NDIlib_metadata_frame_t>?,
		UInt32
	) -> NDIlib_frame_type_e {
		{ [self] _, video, audio, metadata, _ in
			self.state.withLock { state in
				if video != nil { state.capturedMedia.insert(.video) }
				if audio != nil { state.capturedMedia.insert(.audio) }
				if metadata != nil { state.capturedMedia.insert(.metadata) }
			}
			return NDIlib_frame_type_none
		}
	}
}
