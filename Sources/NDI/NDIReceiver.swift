import CoreGraphics
import CoreImage
import Dependencies
import libNDI
import OSLog

public final class NDIReceiver: @unchecked Sendable {
	private let logger = Logger(category: "NDIReceiver")

	let ndi: NDI

	let pNDI_recv: NDIlib_recv_instance_t

	public init?(source: NDISource? = nil) {
		@Dependency(\.ndi) var ndi
		guard let ndi else { return nil }

		self.ndi = ndi

		var recv_desc = NDIlib_recv_create_v3_t(
			source_to_connect_to: source?.ref ?? NDIlib_source_t(),
			color_format: NDIlib_recv_color_format_UYVY_BGRA,
			bandwidth: NDIlib_recv_bandwidth_highest,
			allow_video_fields: true,
			p_ndi_recv_name: nil
		)
		guard let pNDI_recv = ndi.NDIlib_recv_create_v3(&recv_desc) else { return nil }
		self.pNDI_recv = pNDI_recv
	}

	deinit {
		ndi.NDIlib_recv_destroy(pNDI_recv)
	}

	public func connect(name: String) async {
		guard let find = NDIFind() else { return }
		guard let source = await find.getSource(named: name) else { return }

		self.connect(source)
	}

	public func connect(_ source: NDISource) {
		var sourceRef = source.ref

		ndi.NDIlib_recv_connect(pNDI_recv, &sourceRef)
	}

	public func capture(types: Set<NDICaptureType> = Set(NDICaptureType.allCases), timeout: Duration = .zero) -> NDIReceivedFrame {
		// The descriptors
		var video_frame: NDIlib_video_frame_v2_t = .init(
			xres: 0,
			yres: 0,
			FourCC: .init(0),
			frame_rate_N: 0,
			frame_rate_D: 0,
			picture_aspect_ratio: 0,
			frame_format_type: .init(0),
			timecode: 0,
			p_data: nil,
			NDIlib_video_frame_v2_t.__Unnamed_union___Anonymous_field9(),
			p_metadata: nil,
			timestamp: 0
		)
		var audio_frame: NDIlib_audio_frame_v3_t = .init(
			sample_rate: 48000,
			no_channels: 2,
			no_samples: 0,
			timecode: NDIlib_send_timecode_synthesize,
			FourCC: NDIlib_FourCC_audio_type_FLTP,
			p_data: nil,
			.init(channel_stride_in_bytes: 0),
			p_metadata: nil,
			timestamp: 0
		)
		var metadata_frame: NDIlib_metadata_frame_t = .init(
			length: 0,
			timecode: 0,
			p_data: nil
		)

		let frameType = withUnsafeMutablePointer(to: &video_frame) { video_frame in
			withUnsafeMutablePointer(to: &audio_frame) { audio_frame in
				withUnsafeMutablePointer(to: &metadata_frame) { metadata_frame in
					ndi.NDIlib_recv_capture_v3(
						pNDI_recv,
						types.contains(.video) ? video_frame : nil,
						types.contains(.audio) ? audio_frame : nil,
						types.contains(.metadata) ? metadata_frame : nil,
						.init(timeout.seconds * 1000)
					)
				}
			}
		}

		switch frameType {
		case NDIlib_frame_type_none:
			return .none
		case NDIlib_frame_type_video:
			let videoFrame = NDIReceivedVideoFrame(video_frame, receiver: self)

			return .video(videoFrame)
		case NDIlib_frame_type_audio:
			let audioFrame = NDIReceivedAudioFrame(audio_frame, receiver: self)

			return .audio(audioFrame)
		case NDIlib_frame_type_metadata:
			let metadataFrame = NDIMetadataFrame(metadata_frame, receiver: self)

			return .metadata(metadataFrame)
		case NDIlib_frame_type_status_change:
			logger.debug("Status changed")

			return .statusChange
		default:
			logger.debug("Other \(frameType.rawValue)")

			return .unknown
		}
	}
}

public enum NDICaptureType: CaseIterable, Sendable {
	case video
	case audio
	case metadata
}

public enum NDIReceivedFrame: Sendable {
	case none
	case video(NDIReceivedVideoFrame)
	case audio(NDIReceivedAudioFrame)
	case metadata(NDIMetadataFrame)
	case statusChange
	case unknown
}
