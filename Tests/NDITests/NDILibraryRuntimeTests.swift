import Synchronization
import Testing
@testable import NDI

struct NDILibraryRuntimeTests {
	@Test
	func searchesTheApplicationFrameworksDirectoryFirst() {
		#expect(NDI.libraryPaths == [
			"@executable_path/../Frameworks/libndi.dylib",
			"libndi.dylib",
			"/usr/local/lib/libndi.dylib",
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
