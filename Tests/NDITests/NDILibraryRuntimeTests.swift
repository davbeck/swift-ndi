import Synchronization
import Testing
@testable import NDI

struct NDILibraryRuntimeTests {
	@Test
	func searchesTheApplicationFrameworksDirectoryFirst() {
		#expect(NDI.libraryPaths(environment: [:]) == [
			"@executable_path/../Frameworks/libndi.dylib",
			"/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
			"/usr/local/lib/libndi.dylib",
			"libndi.dylib",
		])
	}

	@Test
	func honorsTheNDIRuntimeDirectoryEnvironmentVariable() {
		#expect(NDI.libraryPaths(environment: ["NDI_RUNTIME_DIR_V6": "/opt/ndi/runtime"]) == [
			"@executable_path/../Frameworks/libndi.dylib",
			"/opt/ndi/runtime/libndi.dylib",
			"/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
			"/usr/local/lib/libndi.dylib",
			"libndi.dylib",
		])
	}

	@Test
	func initializesOnceAndDestroysBeforeClosing() throws {
		let events = Mutex<[String]>([])
		var runtime: NDILibraryRuntime? = try NDILibraryRuntime(
			initialize: {
				events.withLock { $0.append("initialize") }
				return true
			},
			destroy: {
				events.withLock { $0.append("destroy") }
			},
			close: {
				events.withLock { $0.append("close") }
			}
		)

		#expect(events.withLock { $0 } == ["initialize"])
		#expect(runtime != nil)

		runtime = nil

		#expect(events.withLock { $0 } == ["initialize", "destroy", "close"])
	}

	@Test
	func closesWithoutDestroyingWhenInitializationFails() {
		let events = Mutex<[String]>([])

		#expect(throws: NDILoadError.initializationFailed) {
			_ = try NDILibraryRuntime(
				initialize: {
					events.withLock { $0.append("initialize") }
					return false
				},
				destroy: {
					events.withLock { $0.append("destroy") }
				},
				close: {
					events.withLock { $0.append("close") }
				}
			)
		}

		#expect(events.withLock { $0 } == ["initialize", "close"])
	}
}
