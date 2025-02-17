import libNDI
import string_h

public struct NDISource: @unchecked Sendable {
	// referenced to keep ref alive
	// NDIlib_find_instance_t manages the memory of the sources it returns
	// NDISourceAllocator is a way for us to track a manually created source
	private var allocator: AnyObject

	var ref: NDIlib_source_t

	init?(_ ref: NDIlib_source_t, find: NDIFind) {
		self.ref = ref
		self.allocator = find
	}

	public init(name: String, url: String) {
		let allocator = NDISourceAllocator(name: name, url: url)
		self.allocator = allocator
		self.ref = NDIlib_source_t(
			p_ndi_name: allocator.p_ndi_name,
			.init(p_url_address: allocator.p_url_address)
		)
	}

	public var name: String {
		String(cString: ref.p_ndi_name)
	}

	public var url: String {
		String(cString: ref.p_url_address)
	}
}

extension NDISource: Equatable {
	public static func == (lhs: NDISource, rhs: NDISource) -> Bool {
		String(cString: lhs.ref.p_ndi_name) == String(cString: rhs.ref.p_ndi_name) && String(cString: lhs.ref.p_url_address) == String(cString: rhs.ref.p_url_address)
	}
}

extension NDISource: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(String(cString: ref.p_ndi_name))
		hasher.combine(String(cString: ref.p_url_address))
	}
}

extension NDISource: Identifiable {
	public var id: String { String(cString: ref.p_url_address) }
}

extension NDISource: CustomStringConvertible {
	public var description: String {
		#"NDISource(name: "\#(name)", url: "\#(url)")"#
	}
}

private final class NDISourceAllocator: @unchecked Sendable {
	fileprivate let p_ndi_name: UnsafeMutablePointer<CChar>
	fileprivate let p_url_address: UnsafeMutablePointer<CChar>

	init(name: String, url: String) {
		p_ndi_name = .allocate(from: name)
		p_url_address = .allocate(from: url)
	}

	deinit {
		p_ndi_name.deallocate()
		p_url_address.deallocate()
	}
}

private extension UnsafeMutablePointer<CChar> {
	static func allocate(from string: String) -> Self {
		string.utf8CString.withUnsafeBufferPointer { buffer in
			guard let baseAddress = buffer.baseAddress else { return .allocate(capacity: 1) }

			let p_ndi_name = UnsafeMutablePointer<CChar>.allocate(capacity: buffer.count)
			p_ndi_name.initialize(from: baseAddress, count: buffer.count)
			return p_ndi_name
		}
	}
}
