import Dependencies
import DependenciesMacros
import libNDI
import OSLog

private let logger = Logger(subsystem: "swift-ndi", category: "library")

@DependencyClient
public struct NDI: Sendable {
	/// The units that time is represented in (100ns) per second
	public static let timescale: Int64 = 10_000_000

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

	// MARK: - SEND

	var NDIlib_send_create: @Sendable (UnsafePointer<NDIlib_send_create_t>?) -> NDIlib_send_instance_t?

	var NDIlib_send_destroy: @Sendable (NDIlib_send_instance_t?) -> Void

	var NDIlib_send_send_video_v2: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_video_frame_v2_t>?) -> Void

	var NDIlib_send_send_audio_v3: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_audio_frame_v3_t>?) -> Void

	var NDIlib_send_send_metadata: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_metadata_frame_t>?) -> Void

	var NDIlib_send_capture: @Sendable (NDIlib_send_instance_t?, UnsafeMutablePointer<NDIlib_metadata_frame_t>?, UInt32) -> NDIlib_frame_type_e = { _, _, _ in NDIlib_frame_type_none }

	var NDIlib_send_free_metadata: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_metadata_frame_t>?) -> Void

	var NDIlib_send_get_tally: @Sendable (NDIlib_send_instance_t?, UnsafeMutablePointer<NDIlib_tally_t>?, UInt32) -> Bool = { _, _, _ in false }

	var NDIlib_send_get_no_connections: @Sendable (NDIlib_send_instance_t?, UInt32) -> Int32 = { _, _ in 0 }

	var NDIlib_send_clear_connection_metadata: @Sendable (NDIlib_send_instance_t?) -> Void

	var NDIlib_send_add_connection_metadata: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_metadata_frame_t>?) -> Void

	var NDIlib_send_set_failover: @Sendable (NDIlib_send_instance_t?, UnsafePointer<NDIlib_source_t>?) -> Void

	var NDIlib_send_get_source_name: @Sendable (NDIlib_send_instance_t?) -> UnsafePointer<NDIlib_source_t>?
}

public enum NDILoadError: Error, Equatable, LocalizedError, Sendable {
	case dlopenFailed(String?)
	case loadMethodNotFound(String?)
	case loadFailed
	case initializationFailed

	public var errorDescription: String? {
		switch self {
		case let .dlopenFailed(message):
			if let message {
				String(localized: "Failed to open the NDI library: \(message)")
			} else {
				String(localized: "Failed to open the NDI library.")
			}
		case let .loadMethodNotFound(message):
			if let message {
				String(localized: "Failed to find the NDI loader: \(message)")
			} else {
				String(localized: "Failed to find the NDI loader.")
			}
		case .loadFailed:
			String(localized: "The NDI loader did not return a function table.")
		case .initializationFailed:
			String(localized: "The NDI library failed to initialize.")
		}
	}
}

final class NDILibraryRuntime: @unchecked Sendable {
	private let destroy: @Sendable () -> Void
	private let close: @Sendable () -> Void

	init(
		initialize: () -> Bool,
		destroy: @escaping @Sendable () -> Void,
		close: @escaping @Sendable () -> Void = {}
	) throws(NDILoadError) {
		guard initialize() else {
			close()
			throw NDILoadError.initializationFailed
		}

		self.destroy = destroy
		self.close = close
	}

	deinit {
		destroy()
		close()
	}
}

#if os(macOS)
	private final class NDIDynamicLibraryHandle: @unchecked Sendable {
		let rawValue: UnsafeMutableRawPointer

		init(rawValue: UnsafeMutableRawPointer) {
			self.rawValue = rawValue
		}

		func close() {
			dlclose(rawValue)
		}
	}
#endif

public extension NDI {
	init(_ lib: NDIlib_v5) {
		self.init(lib, retaining: nil)
	}

	private init(_ lib: NDIlib_v5, retaining runtime: NDILibraryRuntime?) {
		self.init(
			NDIlib_initialize: { [runtime] in
				if runtime != nil {
					return true
				}
				return lib.NDIlib_initialize()
			},
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
			NDIlib_recv_free_metadata: { lib.NDIlib_recv_free_metadata($0, $1) },

			NDIlib_send_create: { lib.NDIlib_send_create($0) },
			NDIlib_send_destroy: { lib.NDIlib_send_destroy($0) },
			NDIlib_send_send_video_v2: { lib.NDIlib_send_send_video_v2($0, $1) },
			NDIlib_send_send_audio_v3: { lib.NDIlib_send_send_audio_v3($0, $1) },
			NDIlib_send_send_metadata: { lib.NDIlib_send_send_metadata($0, $1) },
			NDIlib_send_capture: { lib.NDIlib_send_capture($0, $1, $2) },
			NDIlib_send_free_metadata: { lib.NDIlib_send_free_metadata($0, $1) },
			NDIlib_send_get_tally: { lib.NDIlib_send_get_tally($0, $1, $2) },
			NDIlib_send_get_no_connections: { lib.NDIlib_send_get_no_connections($0, $1) },
			NDIlib_send_clear_connection_metadata: { lib.NDIlib_send_clear_connection_metadata($0) },
			NDIlib_send_add_connection_metadata: { lib.NDIlib_send_add_connection_metadata($0, $1) },
			NDIlib_send_set_failover: { lib.NDIlib_send_set_failover($0, $1) },
			NDIlib_send_get_source_name: { lib.NDIlib_send_get_source_name($0) }
		)
	}

	#if os(macOS)
		init(libraryPath: String) throws(NDILoadError) {
			typealias LoadFunc = @convention(c) () -> UnsafePointer<NDIlib_v5>?

			guard let rawHandle = dlopen(libraryPath, RTLD_NOW) else {
				if let errorMessage = dlerror() {
					throw NDILoadError.dlopenFailed(String(cString: errorMessage))
				}

				throw NDILoadError.dlopenFailed(nil)
			}
			let handle = NDIDynamicLibraryHandle(rawValue: rawHandle)
			guard let sym = dlsym(handle.rawValue, "NDIlib_v5_load") else {
				let errorMessage = dlerror().map { String(cString: $0) }
				handle.close()
				throw NDILoadError.loadMethodNotFound(errorMessage)
			}
			let NDIlib_v5_load = unsafeBitCast(sym, to: LoadFunc.self)

			guard let libPointer = NDIlib_v5_load() else {
				handle.close()
				throw NDILoadError.loadFailed
			}

			let lib = libPointer.pointee
			let runtime = try NDILibraryRuntime(
				initialize: { lib.NDIlib_initialize() },
				destroy: { lib.NDIlib_destroy() },
				close: { handle.close() }
			)

			self.init(lib, retaining: runtime)
		}

		static let libraryPaths = [
			"@executable_path/../Frameworks/libndi.dylib",
			"libndi.dylib",
			"/usr/local/lib/libndi.dylib",
		]

		static let sharedResult: Result<NDI, NDILoadError> = {
			var lastError = NDILoadError.dlopenFailed(nil)
			for path in libraryPaths {
				do {
					return try .success(NDI(libraryPath: path))
				} catch {
					let loadError = error as? NDILoadError ?? .loadFailed
					if loadError == .initializationFailed {
						return .failure(loadError)
					}
					lastError = loadError
				}
			}

			return .failure(lastError)
		}()
	#else
		static let sharedResult: Result<NDI, NDILoadError> = {
			guard let libPointer = NDIlib_v5_load() else {
				return .failure(.loadFailed)
			}

			let lib = libPointer.pointee
			do {
				let runtime = try NDILibraryRuntime(
					initialize: { lib.NDIlib_initialize() },
					destroy: { lib.NDIlib_destroy() }
				)
				return .success(NDI(lib, retaining: runtime))
			} catch {
				return .failure(error as? NDILoadError ?? .initializationFailed)
			}
		}()
	#endif

	static let shared: NDI? = {
		switch sharedResult {
		case let .success(ndi):
			return ndi
		case let .failure(error):
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

public extension DependencyValues {
	var ndi: NDI? {
		get { self[NDI.self] }
		set { self[NDI.self] = newValue }
	}
}
