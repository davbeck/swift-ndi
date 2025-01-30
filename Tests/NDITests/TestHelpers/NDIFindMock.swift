import IssueReporting
import libNDI
import Synchronization
@testable import NDI

enum NDIInstanceState {
	case uninitialized
	case initialized
	case destroyed
}

final class NDIFindMockInstance: @unchecked Sendable {
	struct State: @unchecked Sendable {
		var state: NDIInstanceState = .uninitialized

		var sourceBuffer = UnsafeMutablePointer<NDIlib_source_t>.allocate(capacity: 0)

		var sourcesHaveChanged: Bool = false
		var sources: [NDISource] = [] {
			didSet {
				sourcesHaveChanged = true

				guard sources != oldValue else { return }

				sourceBuffer.deallocate()

				sourceBuffer = .allocate(capacity: sources.count)
				for (index, source) in sources.enumerated() {
					sourceBuffer[index] = source.ref
				}
			}
		}
	}

	let _state = Mutex(State())

	let ref = NDIlib_find_instance_t.test

	var sources: [NDISource] {
		get { _state.withLock { $0.sources } }
		set { _state.withLock { $0.sources = newValue } }
	}

	init() {}

	deinit {
		_state.withLock { state in
			state.sourceBuffer.deallocate()
		}
	}

	var NDIlib_find_create_v2: @Sendable (UnsafePointer<NDIlib_find_create_t>?) -> NDIlib_find_instance_t? {
		{ [self] options in
			self._state.withLock { state in
				guard state.state == .uninitialized else {
					IssueReporting.reportIssue("Already initialized \(String(describing: ref)): 'NDI.NDIlib_find_create_v2'")
					return
				}
				state.state = .initialized
			}

			return ref
		}
	}

	var NDIlib_find_destroy: @Sendable (NDIlib_find_instance_t?) -> Void {
		{ ref in
			self._state.withLock { state in
				guard state.state == .initialized else {
					IssueReporting.reportIssue("Invalid state \(state.state) for \(String(describing: ref)): 'NDI.NDIlib_find_destroy'")
					return
				}
				state.state = .destroyed
			}
		}
	}

	var NDIlib_find_wait_for_sources: @Sendable (NDIlib_find_instance_t?, UInt32) -> Bool {
		{ ref, timeout in
			self._state.withLock { state in
				guard state.state == .initialized else {
					IssueReporting.reportIssue("Invalid state \(state.state) for \(String(describing: ref)): 'NDI.NDIlib_find_wait_for_sources'")
					return false
				}
				let sourcesHaveChanged = state.sourcesHaveChanged
				state.sourcesHaveChanged = false
				return sourcesHaveChanged
			}
		}
	}

	var NDIlib_find_get_current_sources: @Sendable (NDIlib_find_instance_t?, UnsafeMutablePointer<UInt32>?) -> UnsafePointer<NDIlib_source_t>? {
		{ ref, count -> UnsafePointer<NDIlib_source_t>? in
			self._state.withLock { state -> UnsafePointer<NDIlib_source_t>? in
				guard state.state == .initialized else {
					IssueReporting.reportIssue("Invalid state \(state.state) for \(String(describing: ref)): 'NDI.NDIlib_find_get_current_sources'")
					return nil
				}

				state.sourcesHaveChanged = false

				count?.pointee = UInt32(state.sources.count)
				return .init(state.sourceBuffer)
			}
		}
	}
}

extension NDI {
	mutating func use(_ mock: NDIFindMockInstance) {
		NDIlib_find_create_v2 = mock.NDIlib_find_create_v2
		NDIlib_find_destroy = mock.NDIlib_find_destroy
		NDIlib_find_wait_for_sources = mock.NDIlib_find_wait_for_sources
		NDIlib_find_get_current_sources = mock.NDIlib_find_get_current_sources
	}
}
