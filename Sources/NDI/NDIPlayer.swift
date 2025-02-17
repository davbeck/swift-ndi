import Foundation
import libNDI
import Synchronization

public actor NDIPlayer {
	private static let playerPool: Mutex<[String: Weak<NDIPlayer>]> = .init([:])

	public static func player(for name: String) -> NDIPlayer {
		playerPool.withLock { pool in
			if let player = pool[name]?.value {
				return player
			} else {
				let player = NDIPlayer(name: name)
				pool[name] = .init(value: player)
				return player
			}
		}
	}

	public let sourceName: String
	private var source: NDISource?

	public init(name: String) {
		self.sourceName = name
	}

	public init(source: NDISource) {
		self.sourceName = source.name
		self.source = source
	}

	private var getReceiverTask: Task<NDIReceiver?, Never>?

	private func getReceiver() async -> NDIReceiver? {
		if let getReceiverTask {
			return await getReceiverTask.value
		} else {
			let task = Task { () -> NDIReceiver? in
				if let source {
					guard let receiver = NDIReceiver(source: source) else { return nil }

					return receiver
				} else {
					guard let receiver = NDIReceiver() else { return nil }

					await receiver.connect(name: sourceName)

					return receiver
				}
			}
			getReceiverTask = task
			return await task.value
		}
	}

	private var lastVideoFrame: NDIVideoFrame?

	private var receiveThread: Thread? {
		didSet {
			oldValue?.cancel()
		}
	}

	private func updateReceiving() async {
		if videoFramesContinuations.isEmpty && audioFramesContinuations.isEmpty && metadataContinuations.isEmpty {
			receiveThread = nil
		} else {
			await self.receive()
		}
	}

	private func receive() async {
		guard let receiver = await getReceiver() else { return }

		let thread = Thread { [weak self] in
			while !Thread.current.isCancelled {
				let frame = receiver.capture(timeout: .seconds(1))

				if let self {
					Task {
						await self.receive(frame: frame)
					}
				} else {
					return
				}
			}
		}
		thread.start()
		receiveThread = thread
	}

	private func receive(frame: NDIFrame) {
		switch frame {
		case let .video(frame):
			lastVideoFrame = frame
			for (_, continuation) in videoFramesContinuations {
				continuation.yield(frame)
			}
		case let .audio(frame):
			for (_, continuation) in audioFramesContinuations {
				continuation.yield(frame)
			}
		case let .metadata(frame):
			for (_, continuation) in metadataContinuations {
				continuation.yield(frame)
			}
		default:
			break
		}
	}

	@discardableResult
	public func connect() async -> Bool {
		await getReceiver() != nil
	}

	// MARK: - Video

	public typealias VideoFrameStream = AsyncStream<NDIVideoFrame>

	private var videoFramesContinuations: [UUID: VideoFrameStream.Continuation] = [:]

	private func registerVideoContinuation(_ continuation: VideoFrameStream.Continuation) async {
		if let lastVideoFrame {
			continuation.yield(lastVideoFrame)
		}

		let id = UUID()
		videoFramesContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterVideoContinuation(id)
			}
		}

		await updateReceiving()
	}

	private func unregisterVideoContinuation(_ id: UUID) async {
		self.videoFramesContinuations.removeValue(forKey: id)

		await updateReceiving()
	}

	public nonisolated var videoFrames: VideoFrameStream {
		let (stream, continuation) = VideoFrameStream.makeStream(bufferingPolicy: .bufferingNewest(1))

		Task {
			await self.registerVideoContinuation(continuation)
		}

		return stream
	}

	// MARK: - Audio

	public typealias AudioFrameStream = AsyncStream<NDIAudioFrame>

	private var audioFramesContinuations: [UUID: AudioFrameStream.Continuation] = [:]

	private func registerAudioContinuation(_ continuation: AudioFrameStream.Continuation) async {
		let id = UUID()
		audioFramesContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterAudioContinuation(id)
			}
		}

		await updateReceiving()
	}

	private func unregisterAudioContinuation(_ id: UUID) async {
		self.audioFramesContinuations.removeValue(forKey: id)

		await updateReceiving()
	}

	nonisolated
	public var audioFrames: AudioFrameStream {
		let (stream, continuation) = AudioFrameStream.makeStream(bufferingPolicy: .bufferingNewest(1))

		Task {
			await self.registerAudioContinuation(continuation)
		}

		return stream
	}

	// MARK: - Metadata

	public typealias MetadataStream = AsyncStream<NDIMetadataFrame>

	private var metadataContinuations: [UUID: MetadataStream.Continuation] = [:]

	private func registerMetadataContinuation(_ continuation: MetadataStream.Continuation) async {
		let id = UUID()
		metadataContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterMetadataContinuation(id)
			}
		}

		await updateReceiving()
	}

	private func unregisterMetadataContinuation(_ id: UUID) async {
		self.metadataContinuations.removeValue(forKey: id)

		await updateReceiving()
	}

	public nonisolated var metadataFrames: MetadataStream {
		let (stream, continuation) = MetadataStream.makeStream(bufferingPolicy: .bufferingNewest(0))

		Task {
			await self.registerMetadataContinuation(continuation)
		}

		return stream
	}
}
