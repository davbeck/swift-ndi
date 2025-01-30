import Dependencies
import libNDI
import Observation

/// This is provided to locate sources available on the network and is normally used in conjunction with NDI-Receive. Internally, it uses a cross-process P2P mDNS implementation to locate sources on the network. (It commonly takes a few seconds to locate all the sources available since this requires other running machines to send response messages.)
///
/// Although discovery uses mDNS, the client is entirely self-contained; Bonjour (etc.) is not required. mDNS is a P2P system that exchanges located network sources and provides a highly robust and bandwidth-efficient way to perform discovery on a local network.
///
/// On mDNS initialization (often done using the NDI-FIND SDK), a few seconds might elapse before all sources on the network are located. Be aware that some network routers might block mDNS traffic between network segments.
class NDIFind: @unchecked Sendable {
	@Dependency(\.suspendingClock) private var clock

	let ndi: NDI

	private let pNDI_find: NDIlib_find_instance_t

	public init?() {
		@Dependency(\.ndi) var ndi

		guard let ndi else { return nil }

		self.ndi = ndi

		guard let pNDI_find = ndi.NDIlib_find_create_v2(nil) else {
			return nil
		}

		self.pNDI_find = pNDI_find
	}

	deinit {
		ndi.NDIlib_find_destroy(pNDI_find)
	}

	func _waitForSources(timeout: Duration = .zero) -> Bool {
		ndi.NDIlib_find_wait_for_sources(pNDI_find, UInt32(timeout.milliseconds))
	}

	/// This will allow you to wait until the number of online sources have changed.
	func waitForSources(timeout: Duration = .zero) -> Bool {
		_waitForSources(timeout: timeout)
	}
	
	func waitForSources(timeout: Duration? = nil) async -> Bool {
		let deadline = timeout.map { clock.now.advanced(by: $0) }

		return await self.waitForSources(deadline: deadline)
	}

	private func waitForSources(deadline: (any InstantProtocol<Duration>)?) async -> Bool {
		while !Task.isCancelled {
			if let deadline {
				guard clock.now.isBefore(deadline) else { return false }
			}

			if _waitForSources(timeout: .zero) {
				return true
			}

			try? await clock.sleep(for: .seconds(0.01))
		}

		return false
	}

	func getCurrentSources() -> [NDISource] {
		var no_sources: UInt32 = 0
		guard let p_sources: UnsafePointer<NDIlib_source_t> = ndi.NDIlib_find_get_current_sources(pNDI_find, &no_sources) else {
			return []
		}

		return (0 ..< no_sources).compactMap { i in
			NDISource(p_sources[Int(i)], find: self)
		}
	}

	func getSource(named name: String, timeout: Duration? = nil) async -> NDISource? {
		let deadline = timeout.map { clock.now.advanced(by: $0) }
		
		if let source = getCurrentSources().first(where: { $0.name == name }) {
			return source
		}

		while !Task.isCancelled {
			if let deadline {
				guard clock.now.isBefore(deadline) else { return nil }
			}

			if await waitForSources(deadline: deadline), let source = getCurrentSources().first(where: { $0.name == name }) {
				return source
			}
		}

		return nil
	}
}

private extension InstantProtocol where Duration == Duration {
	func isBefore(_ other: any InstantProtocol<Duration>) -> Bool {
		guard let other = other as? Self else { return false }
		return self < other
	}
}
