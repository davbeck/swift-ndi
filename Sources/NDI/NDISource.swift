import libNDI

public struct NDISource {
	// referenced to keep ref alive
	private let find: NDIFind

	var ref: NDIlib_source_t

	init?(_ ref: NDIlib_source_t, find: NDIFind) {
		self.ref = ref
		self.find = find
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
		lhs.ref.p_ndi_name == rhs.ref.p_ndi_name && lhs.ref.p_url_address == rhs.ref.p_url_address
	}
}

extension NDISource: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(ref.p_ndi_name)
		hasher.combine(ref.p_url_address)
	}
}

extension NDISource: Identifiable {
	public var id: String { String(cString: ref.p_url_address) }
}
