import Synchronization

private let nextOpaquePointer = Mutex(1)
extension OpaquePointer {
	static var test: OpaquePointer {
		nextOpaquePointer.withLock { value in
			let next = value
			value += 1
			// should only be nil if bitPattern == 0
			return OpaquePointer(bitPattern: next)!
		}
	}
}
