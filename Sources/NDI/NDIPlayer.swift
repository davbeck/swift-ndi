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

	nonisolated
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

	private var lastVideoFrame: NDIReceivedVideoFrame?

	private var receiveThread: Thread? {
		didSet {
			oldValue?.cancel()
		}
	}

	private func updateReceiving() async {
		if framesContinuations.isEmpty {
			receiveThread = nil
		} else {
			await self.receive()
		}
	}

	private func receive() async {
		guard let receiver = await getReceiver() else { return }

		// It is much more efficient to let NDIlib_recv_capture_v3 wait for a new frame
		// but that will block the thread it is running on
		// to avoid blocking a thread from the general executor pool, we create our own thread to wait on
		let thread = Thread { [weak self] in
			while !Thread.current.isCancelled {
				// this timeout will determine how long it takes after cancellation to clean up resources
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

	private func receive(frame: NDIReceivedFrame) {
		for (_, continuation) in framesContinuations {
			continuation.yield(frame)
		}

		switch frame {
		case let .video(frame):
			lastVideoFrame = frame
		default:
			break
		}
	}

	@discardableResult
	public func connect() async -> Bool {
		await getReceiver() != nil
	}

	public typealias FrameStream = AsyncStream<NDIReceivedFrame>

	private var framesContinuations: [UUID: FrameStream.Continuation] = [:]

	private func registerContinuation(_ continuation: FrameStream.Continuation) async {
		if let lastVideoFrame {
			continuation.yield(.video(lastVideoFrame))
		}

		let id = UUID()
		framesContinuations[id] = continuation

		continuation.onTermination = { reason in
			Task {
				await self.unregisterContinuation(id)
			}
		}

		await updateReceiving()
	}

	private func unregisterContinuation(_ id: UUID) async {
		self.framesContinuations.removeValue(forKey: id)

		await updateReceiving()
	}

	public nonisolated func frames(bufferingNewest: Int = 60) -> FrameStream {
		let (stream, continuation) = FrameStream.makeStream(bufferingPolicy: .bufferingNewest(bufferingNewest))

		Task {
			await self.registerContinuation(continuation)
		}

		return stream
	}

	public nonisolated var videoFrames: some (AsyncSequence<NDIReceivedVideoFrame, Never> & Sendable) {
		frames()
			.compactMap { frame in
				switch frame {
				case let .video(frame):
					frame
				default:
					nil
				}
			}
	}

	public nonisolated var audioFrames: some (AsyncSequence<NDIReceivedAudioFrame, Never> & Sendable) {
		frames()
			.compactMap { frame in
				switch frame {
				case let .audio(frame):
					frame
				default:
					nil
				}
			}
	}

	public nonisolated var metadataFrames: some (AsyncSequence<NDIMetadataFrame, Never> & Sendable) {
		frames()
			.compactMap { frame in
				switch frame {
				case let .metadata(frame):
					frame
				default:
					nil
				}
			}
	}
}
