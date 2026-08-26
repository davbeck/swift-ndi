import CoreGraphics
import Foundation
import NDI
import Observation

@MainActor
@Observable
final class SignalGeneratorModel {
	var configuration = SignalConfiguration()
	private(set) var isSending = false
	private(set) var preview: CGImage?
	private(set) var frameLabel = "— / —"
	private(set) var connectionCount = 0
	private(set) var status = "Ready"

	private var sendTask: Task<Void, Never>?
	private var generation: UUID?

	func toggleSending() {
		isSending ? stop() : start()
	}

	func start() {
		guard !isSending else { return }
		isSending = true
		status = "Starting…"
		launch(configuration: configuration, after: nil)
	}

	private func launch(configuration: SignalConfiguration, after previousTask: Task<Void, Never>?) {
		let generation = UUID()
		self.generation = generation

		sendTask = Task.detached(priority: .userInitiated) { [weak self] in
			await previousTask?.value
			guard !Task.isCancelled else { return }
			guard let sender = NDISender(name: configuration.sourceName) else {
				await self?.finish(generation: generation, with: "NDI runtime unavailable")
				return
			}

			let clock = ContinuousClock()
			let interval = Duration.seconds(1 / configuration.frameRate.framesPerSecond)
			var deadline = clock.now
			var second = Int(Date().timeIntervalSince1970)
			var frameInSecond = 0

			await self?.setStatus(
				"Sending as \(sender.sourceName() ?? configuration.sourceName)",
				generation: generation
			)

			do {
				while !Task.isCancelled {
					let now = Date()
					let currentSecond = Int(now.timeIntervalSince1970)
					if currentSecond != second {
						second = currentSecond
						frameInSecond = 0
					}
					frameInSecond += 1

					let rendered = try SignalFrameRenderer.render(
						configuration: configuration,
						date: now,
						frameInSecond: frameInSecond
					)
					let frame = try NDISendVideoFrame(
						pixelBuffer: rendered.pixelBuffer,
						frameRate: configuration.frameRate.mediaTime
					)
					try sender.send(frame)

					let label = "\(frameInSecond) / \(configuration.frameRate.counterLabel)"
					let connections = sender.connectionCount()
					await self?.didSend(
						preview: rendered.image,
						frameLabel: label,
						connections: connections,
						generation: generation
					)

					deadline += interval
					if deadline < clock.now {
						deadline = clock.now
					}
					try await clock.sleep(until: deadline)
				}
			} catch is CancellationError {
				// Stopping is the normal cancellation path.
			} catch {
				await self?.finish(generation: generation, with: error.localizedDescription)
			}
		}
	}

	func stop() {
		sendTask?.cancel()
		sendTask = nil
		generation = nil
		isSending = false
		connectionCount = 0
		status = "Stopped"
	}

	func restartIfSending() {
		guard isSending else { return }
		let previousTask = sendTask
		previousTask?.cancel()
		status = "Updating…"
		launch(configuration: configuration, after: previousTask)
	}

	private func didSend(preview: CGImage, frameLabel: String, connections: Int, generation: UUID) {
		guard self.generation == generation else { return }
		self.preview = preview
		self.frameLabel = frameLabel
		connectionCount = connections
	}

	private func setStatus(_ status: String, generation: UUID) {
		guard self.generation == generation else { return }
		self.status = status
	}

	private func finish(generation: UUID, with status: String) {
		guard self.generation == generation else { return }
		sendTask = nil
		self.generation = nil
		isSending = false
		connectionCount = 0
		self.status = status
	}
}
