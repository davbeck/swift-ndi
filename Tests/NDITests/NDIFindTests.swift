import ConcurrencyExtras
import Dependencies
import libNDI
import Synchronization
import Testing
@testable import NDI

struct NDIFindTests {
	struct waitForSources {
		@Test
		func withTimout() throws {
			var ndi = NDI()
			ndi.NDIlib_find_create_v2 = { _ in
				NDIlib_find_instance_t(bitPattern: 123)
			}
			ndi.NDIlib_find_destroy = { ref in
				#expect(ref == NDIlib_find_instance_t(bitPattern: 123))
			}
			ndi.NDIlib_find_wait_for_sources = { ref, timeout in
				#expect(ref == NDIlib_find_instance_t(bitPattern: 123))

				#expect(timeout == 1200, "timeout is passed as millisecondds")

				return false
			}

			let find = try #require(withDependencies {
				$0.ndi = ndi
			} operation: {
				NDIFind()
			})

			_ = find.waitForSources(timeout: .seconds(1.2))
		}

		@Test
		func withDefaultTimeout() throws {
			var ndi = NDI()
			ndi.NDIlib_find_create_v2 = { _ in
				NDIlib_find_instance_t(bitPattern: 123)
			}
			ndi.NDIlib_find_destroy = { ref in
				#expect(ref == NDIlib_find_instance_t(bitPattern: 123))
			}
			ndi.NDIlib_find_wait_for_sources = { ref, timeout in
				#expect(ref == NDIlib_find_instance_t(bitPattern: 123))

				#expect(timeout == 0, "timeout is passed as millisecondds")

				return false
			}

			let find = try #require(withDependencies {
				$0.ndi = ndi
			} operation: {
				NDIFind()
			})

			_ = find.waitForSources()
		}
	}

	struct getSource {
		@Test
		func withoutTimeout() async throws {
			var ndi = NDI()
			
			let findMock = NDIFindMockInstance()
			ndi.use(findMock)

			let clock = TestClock()

			let find = try #require(withDependencies {
				$0.ndi = ndi
				$0.suspendingClock = clock
			} operation: {
				NDIFind()
			})

			let _sources = Mutex<NDISource?>(nil)
			let task = Task {
				let source = await find.getSource(named: "test.local (1)")
				_sources.withLock { $0 = source }
			}

			await clock.advance(by: .seconds(1))
			#expect(_sources.withLock { $0 } == nil)
			
			findMock.sources = [
				.init(name: "test.local (2)", url: "ndi://name=TEST.LOCAL%20(2)"),
			]
			#expect(_sources.withLock { $0 } == nil)
			
			findMock.sources = [
				.init(name: "test.local (1)", url: "ndi://name=TEST.LOCAL%20(1)"),
			]
			await clock.advance(by: .seconds(0.1))
			#expect(_sources.withLock { $0 } == .init(name: "test.local (1)", url: "ndi://name=TEST.LOCAL%20(1)"))
			
			task.cancel()
			await clock.run()
		}
		
		@Test
		func timeout() async throws {
			var ndi = NDI()
			
			let findMock = NDIFindMockInstance()
			ndi.use(findMock)

			let clock = TestClock()

			let find = try #require(withDependencies {
				$0.ndi = ndi
				$0.suspendingClock = clock
			} operation: {
				NDIFind()
			})

			let _sources = Mutex<NDISource?>(nil)
			Task {
				let source = await find.getSource(named: "test.local (1)", timeout: .seconds(10))
				_sources.withLock { $0 = source }
			}

			await clock.advance(by: .seconds(11))
			#expect(_sources.withLock { $0 } == nil)
			
			await clock.run()
		}
	}

	struct getCurrentSources {
		@Test
		func mapsResults() async throws {
			var ndi = NDI()

			let findMock = NDIFindMockInstance()
			findMock.sources = [
				.init(name: "test.local (1)", url: "ndi://name=TEST.LOCAL%20(1)"),
				.init(name: "test.local (2)", url: "ndi://name=TEST.LOCAL%20(2)"),
				.init(name: "test.local (3)", url: "ndi://name=TEST.LOCAL%20(3)"),
			]
			ndi.use(findMock)

			let find = try #require(withDependencies {
				$0.ndi = ndi
			} operation: {
				NDIFind()
			})

			let sources = find.getCurrentSources()
			try #require(sources.count == 3)
			#expect(sources[0].name == "test.local (1)")
		}
	}
}
