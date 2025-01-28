import libNDI
import Observation
import Synchronization

@MainActor
@Observable
public final class NDIFindManager {
	private static let _shared = Mutex(Weak<NDIFindManager>())
	public static var shared: NDIFindManager? {
		_shared.withLock { box in
			if let value = box.value {
				return value
			} else if let value = NDIFindManager() {
				box.value = value

				return value
			} else {
				return nil
			}
		}
	}

	private let instance: NDIFind

	public private(set) var sources: [NDISource] = []

	init?() {
		guard let instance = NDIFind() else {
			return nil
		}

		self.instance = instance

		self.sources = instance.getCurrentSources()
		Task.detached(priority: .background) { [weak self] in
			while !Task.isCancelled {
				guard let self else { return }
				if instance.waitForSources(timeout: .zero) {
					let sources = instance.getCurrentSources()
					await self.apply(sources: sources)
				}

				await Task.yield()
			}
		}
	}

	private func apply(sources: [NDISource]) {
		self.sources = sources
	}
}
