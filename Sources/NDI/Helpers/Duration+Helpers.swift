import Foundation

extension Duration {
	var seconds: TimeInterval {
		TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1e18)
	}

	var milliseconds: Double {
		TimeInterval(components.seconds * 1000) + (TimeInterval(components.attoseconds) / 1e15)
	}
}
