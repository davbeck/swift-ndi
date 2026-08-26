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
	private(set) var tally = NDISenderTally(isOnProgram: false, isOnPreview: false)
	private(set) var lastReceivedMetadata: String?
	private(set) var audioSamplesSent = 0
	private(set) var metadataFramesSent = 0

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
			var audioGenerator = SignalAudioGenerator()
			var audioSamplesSent = 0
			var metadataFramesSent = 0
			var lastMetadataSecond: Int?
			var tally = NDISenderTally(isOnProgram: false, isOnPreview: false)
			var lastReceivedMetadata: String?

			sender.clearConnectionMetadata()
			if configuration.sendsConnectionMetadata {
				sender.addConnectionMetadata(.init(value: configuration.connectionMetadata))
			}
			if configuration.usesFailover {
				sender.setFailoverSource(.init(name: configuration.failoverName, url: configuration.failoverURL))
			} else {
				sender.setFailoverSource(nil)
			}

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
					let timecode = NDITimecode.now

					let rendered = try SignalFrameRenderer.render(
						configuration: configuration,
						date: now,
						frameInSecond: frameInSecond
					)
					let frame = try NDISendVideoFrame(
						pixelBuffer: rendered.pixelBuffer,
						frameRate: configuration.frameRate.mediaTime,
						timecode: timecode
					)
					try sender.send(frame)

					if configuration.sendsAudio {
						let audioFrame = try audioGenerator.makeFrame(configuration: configuration, timecode: timecode)
						sender.send(audioFrame)
						audioSamplesSent += audioFrame.numberOfSamples
					}

					if configuration.sendsMetadata, lastMetadataSecond != currentSecond {
						sender.send(.init(value: configuration.metadata, timecode: timecode))
						metadataFramesSent += 1
						lastMetadataSecond = currentSecond
					}

					if let tallyUpdate = sender.tally() {
						tally = tallyUpdate
					}
					if case let .metadata(metadata) = sender.capture() {
						lastReceivedMetadata = metadata.value
					}

					let label = "\(frameInSecond) / \(configuration.frameRate.counterLabel)"
					let connections = sender.connectionCount()
					await self?.didSend(
						preview: rendered.image,
						frameLabel: label,
						connections: connections,
						tally: tally,
						lastReceivedMetadata: lastReceivedMetadata,
						audioSamplesSent: audioSamplesSent,
						metadataFramesSent: metadataFramesSent,
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
		tally = NDISenderTally(isOnProgram: false, isOnPreview: false)
		status = "Stopped"
	}

	func restartIfSending() {
		guard isSending else { return }
		let previousTask = sendTask
		previousTask?.cancel()
		status = "Updating…"
		launch(configuration: configuration, after: previousTask)
	}

	private func didSend(
		preview: CGImage,
		frameLabel: String,
		connections: Int,
		tally: NDISenderTally,
		lastReceivedMetadata: String?,
		audioSamplesSent: Int,
		metadataFramesSent: Int,
		generation: UUID
	) {
		guard self.generation == generation else { return }
		self.preview = preview
		self.frameLabel = frameLabel
		connectionCount = connections
		self.tally = tally
		self.lastReceivedMetadata = lastReceivedMetadata
		self.audioSamplesSent = audioSamplesSent
		self.metadataFramesSent = metadataFramesSent
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
		tally = NDISenderTally(isOnProgram: false, isOnPreview: false)
		self.status = status
	}
}
