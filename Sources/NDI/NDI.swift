import Dependencies
import DependenciesMacros
import libNDI
import OSLog

private let logger = Logger(subsystem: "swift-ndi", category: "library")

@DependencyClient
public struct NDI: Sendable {
	/// The units that time is represented in (100ns) per second
	public static let timescale: Int64 = 10_000_000

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

public enum NDILoadError: Error, LocalizedError {
	case dlopenFailed(String?)
	case loadMethodNotFound(String?)
	case loadFailed
	
	public var errorDescription: String? {
		String(localized: "Failed to load NDI library.")
	}
}

extension NDI {
	public init(libraryPath: String) throws(NDILoadError) {
		typealias LoadFunc = @convention(c) () -> UnsafePointer<NDIlib_v5>?

		guard let handle = dlopen(libraryPath, RTLD_NOW) else {
			if let errorMessage = dlerror() {
				throw NDILoadError.dlopenFailed(String(cString: errorMessage))
			}
			
			throw NDILoadError.dlopenFailed(nil)
		}
		defer { dlclose(handle) }
		guard let sym = dlsym(handle, "NDIlib_v5_load") else {
			if let errorMessage = dlerror() {
				throw NDILoadError.loadMethodNotFound(String(cString: errorMessage))
			}
			
			throw NDILoadError.loadMethodNotFound(nil)
		}
		let NDIlib_v5_load = unsafeBitCast(sym, to: LoadFunc.self)

		guard let libPointer = NDIlib_v5_load() else {
			throw NDILoadError.loadFailed
		}

		self.init(libPointer.pointee)
	}

	public init(_ lib: NDIlib_v5) {
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

	public static let shared: NDI? = {
		do {
			do {
				return try NDI(libraryPath: "libndi.dylib")
			} catch {
				return try NDI(libraryPath: "/usr/local/lib/libndi.dylib")
			}
		} catch {
			logger.error("Failed to load NDI: \(error)")
			return nil
		}
	}()
}

extension NDI: DependencyKey {
	public static var liveValue: NDI? {
		shared
	}

	public static let testValue: NDI? = NDI()
}

extension DependencyValues {
	public var ndi: NDI? {
		get { self[NDI.self] }
		set { self[NDI.self] = newValue }
	}
}
