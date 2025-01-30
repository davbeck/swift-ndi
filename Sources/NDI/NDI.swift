import Dependencies
import DependenciesMacros
import libNDI
import OSLog

@DependencyClient
struct NDI: Sendable {
	/// The units that time is represented in (100ns) per second
	static let timescale: Int64 = 10_000_000

	// TODO: actually call thses

	var NDIlib_initialize: @Sendable () -> Bool = { false }

	var NDIlib_destroy: @Sendable () -> Void

	// MARK: - FIND

	var NDIlib_find_create_v2: @Sendable (UnsafePointer<NDIlib_find_create_t>?) -> NDIlib_find_instance_t?

	var NDIlib_find_destroy: @Sendable (NDIlib_find_instance_t?) -> Void

	var NDIlib_find_wait_for_sources: @Sendable (NDIlib_find_instance_t?, UInt32) -> Bool = { _, _ in false }

	var NDIlib_find_get_current_sources: @Sendable (NDIlib_find_instance_t?, UnsafeMutablePointer<UInt32>?) -> UnsafePointer<NDIlib_source_t>?

	// MARK: - RECV

	var NDIlib_recv_create_v3: @Sendable (UnsafePointer<NDIlib_recv_create_v3_t>?) -> NDIlib_recv_instance_t?

	var NDIlib_recv_destroy: @Sendable (NDIlib_recv_instance_t?) -> Void

	var NDIlib_recv_connect: @Sendable (NDIlib_recv_instance_t?, UnsafePointer<NDIlib_source_t>?) -> Void

	var NDIlib_recv_capture_v3: @Sendable (
		NDIlib_recv_instance_t?,
		UnsafeMutablePointer<NDIlib_video_frame_v2_t>?,
		UnsafeMutablePointer<NDIlib_audio_frame_v3_t>?,
		UnsafeMutablePointer<NDIlib_metadata_frame_t>?,
		UInt32
	) -> NDIlib_frame_type_e = { _, _, _, _, _ in NDIlib_frame_type_none }

	var NDIlib_recv_free_video_v2: @Sendable (NDIlib_recv_instance_t?, UnsafePointer<NDIlib_video_frame_v2_t>?) -> Void

	var NDIlib_recv_free_audio_v3: @Sendable (NDIlib_recv_instance_t?, UnsafePointer<NDIlib_audio_frame_v3_t>?) -> Void

	var NDIlib_recv_free_metadata: @Sendable (NDIlib_recv_instance_t?, UnsafePointer<NDIlib_metadata_frame_t>?) -> Void
}

extension NDI {
	init?(libraryPath: String) {
		typealias LoadFunc = @convention(c) () -> UnsafePointer<NDIlib_v5>?

		guard let handle = dlopen(libraryPath, RTLD_NOW) else { return nil }
		defer { dlclose(handle) }
		guard let sym = dlsym(handle, "NDIlib_v5_load") else { return nil }
		let NDIlib_v5_load = unsafeBitCast(sym, to: LoadFunc.self)

		guard let libPointer = NDIlib_v5_load() else { return nil }

		self.init(libPointer.pointee)
	}

	init(_ lib: NDIlib_v5) {
		self.init(
			NDIlib_initialize: { lib.NDIlib_initialize() },
			NDIlib_destroy: { lib.NDIlib_destroy() },

			NDIlib_find_create_v2: { lib.NDIlib_find_create_v2($0) },
			NDIlib_find_destroy: { lib.NDIlib_find_destroy($0) },
			NDIlib_find_wait_for_sources: { lib.NDIlib_find_wait_for_sources($0, $1) },
			NDIlib_find_get_current_sources: { lib.NDIlib_find_get_current_sources($0, $1) },

			NDIlib_recv_create_v3: { lib.NDIlib_recv_create_v3($0) },
			NDIlib_recv_destroy: { lib.NDIlib_recv_destroy($0) },
			NDIlib_recv_connect: { lib.NDIlib_recv_connect($0, $1) },
			NDIlib_recv_capture_v3: { lib.NDIlib_recv_capture_v3($0, $1, $2, $3, $4) },
			NDIlib_recv_free_video_v2: { lib.NDIlib_recv_free_video_v2($0, $1) },
			NDIlib_recv_free_audio_v3: { lib.NDIlib_recv_free_audio_v3($0, $1) },
			NDIlib_recv_free_metadata: { lib.NDIlib_recv_free_metadata($0, $1) }
		)
	}

	static let shared: NDI? = NDI(libraryPath: "/usr/local/lib/libndi.dylib")
}

extension NDI: DependencyKey {
	static var liveValue: NDI? {
		shared
	}

	static let testValue: NDI? = NDI()
}

extension DependencyValues {
	var ndi: NDI? {
		get { self[NDI.self] }
		set { self[NDI.self] = newValue }
	}
}
