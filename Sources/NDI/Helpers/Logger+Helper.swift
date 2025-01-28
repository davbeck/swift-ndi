import OSLog

extension Logger {
	init(category: String) {
		self.init(
			subsystem: "swift-ndi",
			category: category
		)
	}
}
