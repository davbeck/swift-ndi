import Dependencies
import libNDI
import Synchronization
import Testing
@testable import NDI

struct NDIReceiverTests {
	@Test
	func initConnectsToProvidedSource() throws {
		let recvRefBitPattern = 1001
		let source = NDISource(name: "Camera A", url: "ndi://camera-a.local")

		var ndi = NDI()
		ndi.NDIlib_recv_create_v3 = { descriptor in
			#expect(String(cString: descriptor!.pointee.source_to_connect_to.p_ndi_name) == "Camera A")
			#expect(String(cString: descriptor!.pointee.source_to_connect_to.p_url_address) == "ndi://camera-a.local")
			#expect(descriptor!.pointee.color_format == NDIlib_recv_color_format_UYVY_BGRA)
			#expect(descriptor!.pointee.bandwidth == NDIlib_recv_bandwidth_highest)
			#expect(descriptor!.pointee.allow_video_fields)
			return NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!
		}
		ndi.NDIlib_recv_destroy = { ref in
			#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
		}

		_ = try #require(withDependencies {
			$0.ndi = ndi
		} operation: {
			NDIReceiver(source: source)
		})
	}

	@Test
	func connectPassesSourceToReceiver() throws {
		let recvRefBitPattern = 1002
		let source = NDISource(name: "Camera A", url: "ndi://camera-a.local")

		var ndi = NDI()
		ndi.NDIlib_recv_create_v3 = { _ in NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)! }
		ndi.NDIlib_recv_destroy = { _ in }
		ndi.NDIlib_recv_connect = { ref, source in
			#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
			#expect(String(cString: source!.pointee.p_ndi_name) == "Camera A")
			#expect(String(cString: source!.pointee.p_url_address) == "ndi://camera-a.local")
		}

		let receiver = try #require(withDependencies {
			$0.ndi = ndi
		} operation: {
			NDIReceiver()
		})

		receiver.connect(source)
	}

	@Test
	func capturePassesRequestedFramePointersAndTimeout() throws {
		let recvRefBitPattern = 1003

		var ndi = NDI()
		ndi.NDIlib_recv_create_v3 = { _ in NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)! }
		ndi.NDIlib_recv_destroy = { _ in }
		ndi.NDIlib_recv_capture_v3 = { ref, video, audio, metadata, timeout in
			#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
			#expect(video != nil)
			#expect(audio == nil)
			#expect(metadata != nil)
			#expect(timeout == 1250)
			return NDIlib_frame_type_none
		}

		let receiver = try #require(withDependencies {
			$0.ndi = ndi
		} operation: {
			NDIReceiver()
		})

		guard case .none = receiver.capture(types: [.video, .metadata], timeout: .seconds(1.25)) else {
			Issue.record("Expected no frame")
			return
		}
	}

	@Test
	func captureMapsFrameTypes() throws {
		let frameTypes: [(NDIlib_frame_type_e, String)] = [
			(NDIlib_frame_type_none, "none"),
			(NDIlib_frame_type_video, "video"),
			(NDIlib_frame_type_audio, "audio"),
			(NDIlib_frame_type_metadata, "metadata"),
			(NDIlib_frame_type_status_change, "statusChange"),
			(NDIlib_frame_type_error, "unknown"),
		]

		for (frameType, expectedFrame) in frameTypes {
			let recvRefBitPattern = 1100 + frameType.rawValue

			var ndi = NDI()
			ndi.NDIlib_recv_create_v3 = { _ in NDIlib_recv_instance_t(bitPattern: Int(recvRefBitPattern))! }
			ndi.NDIlib_recv_destroy = { _ in }
			ndi.NDIlib_recv_capture_v3 = { _, video, audio, metadata, _ in
				video?.pointee = .init(
					xres: 1920,
					yres: 1080,
					FourCC: NDIlib_FourCC_video_type_UYVY,
					frame_rate_N: 30000,
					frame_rate_D: 1001,
					picture_aspect_ratio: 16.0 / 9.0,
					frame_format_type: NDIlib_frame_format_type_progressive,
					timecode: 123,
					p_data: nil,
					.init(line_stride_in_bytes: 3840),
					p_metadata: nil,
					timestamp: NDIlib_recv_timestamp_undefined
				)
				audio?.pointee = .init(
					sample_rate: 48000,
					no_channels: 2,
					no_samples: 0,
					timecode: 456,
					FourCC: NDIlib_FourCC_audio_type_FLTP,
					p_data: nil,
					.init(channel_stride_in_bytes: 0),
					p_metadata: nil,
					timestamp: NDIlib_recv_timestamp_undefined
				)
				metadata?.pointee = .init(length: 0, timecode: 789, p_data: nil)
				return frameType
			}
			ndi.NDIlib_recv_free_video_v2 = { _, _ in }
			ndi.NDIlib_recv_free_audio_v3 = { _, _ in }
			ndi.NDIlib_recv_free_metadata = { _, _ in }

			let receiver = try #require(withDependencies {
				$0.ndi = ndi
			} operation: {
				NDIReceiver()
			})

			#expect(receiver.capture().caseName == expectedFrame)
		}
	}

	@Test
	func receivedFramesFreeCapturedStorageOnDeinit() throws {
		let recvRefBitPattern = 1004
		let freedVideo = Mutex(false)
		let freedAudio = Mutex(false)
		let freedMetadata = Mutex(false)

		for frameType in [NDIlib_frame_type_video, NDIlib_frame_type_audio, NDIlib_frame_type_metadata] {
			var ndi = NDI()
			ndi.NDIlib_recv_create_v3 = { _ in NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)! }
			ndi.NDIlib_recv_destroy = { _ in }
			ndi.NDIlib_recv_capture_v3 = { _, _, _, _, _ in frameType }
			ndi.NDIlib_recv_free_video_v2 = { ref, _ in
				#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
				freedVideo.withLock { $0 = true }
			}
			ndi.NDIlib_recv_free_audio_v3 = { ref, _ in
				#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
				freedAudio.withLock { $0 = true }
			}
			ndi.NDIlib_recv_free_metadata = { ref, _ in
				#expect(ref == NDIlib_recv_instance_t(bitPattern: recvRefBitPattern)!)
				freedMetadata.withLock { $0 = true }
			}

			let receiver = try #require(withDependencies {
				$0.ndi = ndi
			} operation: {
				NDIReceiver()
			})

			_ = receiver.capture()
		}

		#expect(freedVideo.withLock { $0 })
		#expect(freedAudio.withLock { $0 })
		#expect(freedMetadata.withLock { $0 })
	}
}

private extension NDIReceivedFrame {
	var caseName: String {
		switch self {
		case .none:
			"none"
		case .video:
			"video"
		case .audio:
			"audio"
		case .metadata:
			"metadata"
		case .statusChange:
			"statusChange"
		case .unknown:
			"unknown"
		}
	}
}
