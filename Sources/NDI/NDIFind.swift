import libNDI
import Observation

/// This is provided to locate sources available on the network and is normally used in conjunction with NDI-Receive. Internally, it uses a cross-process P2P mDNS implementation to locate sources on the network. (It commonly takes a few seconds to locate all the sources available since this requires other running machines to send response messages.)
///
/// Although discovery uses mDNS, the client is entirely self-contained; Bonjour (etc.) is not required. mDNS is a P2P system that exchanges located network sources and provides a highly robust and bandwidth-efficient way to perform discovery on a local network.
///
/// On mDNS initialization (often done using the NDI-FIND SDK), a few seconds might elapse before all sources on the network are located. Be aware that some network routers might block mDNS traffic between network segments.
class NDIFind: @unchecked Sendable {
	let ndi: NDI

	private let pNDI_find: NDIlib_find_instance_t

	convenience init?() {
		guard let ndi = NDI.shared else {
			return nil
		}

		self.init(ndi: ndi)
	}

	init?(ndi: NDI) {
		self.ndi = ndi

		guard let pNDI_find = NDIlib_find_create_v2(nil) else {
			assertionFailure("NDIlib_find_create_v2 failed")
			return nil
		}

		self.pNDI_find = pNDI_find
	}

	deinit {
		NDIlib_find_destroy(pNDI_find)
	}

	/// This will allow you to wait until the number of online sources have changed.
	func waitForSources(timeout: Duration = .zero) -> Bool {
		NDIlib_find_wait_for_sources(pNDI_find, UInt32(timeout.seconds * 1000))
	}

	func getCurrentSources() -> [NDISource] {
		var no_sources: UInt32 = 0
		guard let p_sources: UnsafePointer<NDIlib_source_t> = NDIlib_find_get_current_sources(pNDI_find, &no_sources) else {
			assertionFailure("NDIlib_find_get_current_sources failed")
			return []
		}

		return (0 ..< no_sources).compactMap { i in
			NDISource(p_sources[Int(i)], find: self)
		}
	}

	func getSource(named name: String) async -> NDISource? {
		while !Task.isCancelled {
			if waitForSources() {
				let sources = getCurrentSources()

				if let source = sources.first(where: { $0.name == name }) {
					return source
				}
			}

			await Task.yield()
		}

		return nil
	}
}
