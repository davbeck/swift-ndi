import Foundation

extension Duration {
	var seconds: TimeInterval {
		TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / TimeInterval(NSEC_PER_SEC))
	}
}
