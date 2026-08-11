import Foundation
import libNDI
import Synchronization

public enum NDIFrameBufferingPolicy: Equatable, Sendable {
	case unbounded
	case bufferingOldest(Int)
	case bufferingNewest(Int)

	/// Keeps only the frame a low-latency consumer can display next.
	public static let lowLatency = Self.bufferingNewest(1)

	fileprivate var streamPolicy: AsyncStream<NDIReceivedFrame>.Continuation.BufferingPolicy {
		switch self {
		case .unbounded:
			.unbounded
		case let .bufferingOldest(limit):
			.bufferingOldest(limit)
		case let .bufferingNewest(limit):
			.bufferingNewest(limit)
		}
	}
}

struct NDIFrameCapture: Sendable {
	var capture: @Sendable () -> NDIReceivedFrame

	func callAsFunction() -> NDIReceivedFrame {
		capture()
	}
}

struct NDIReceiveLoopCallbacks: Sendable {
	var receive: @Sendable (NDIReceivedFrame) async -> Void
	var didStop: @Sendable () async -> Void
}

struct NDIReceiveLoopHandle: Sendable {
	var cancelOperation: @Sendable () -> Void

	func cancel() {
		cancelOperation()
	}
}

struct NDIReceiveLoopStarter: Sendable {
	var start: @Sendable (NDIFrameCapture, NDIReceiveLoopCallbacks) -> NDIReceiveLoopHandle

	func callAsFunction(
		capture: NDIFrameCapture,
		callbacks: NDIReceiveLoopCallbacks
	) -> NDIReceiveLoopHandle {
		start(capture, callbacks)
	}

	static let live = Self { capture, callbacks in
		let loop = NDIThreadReceiveLoop(capture: capture, callbacks: callbacks)
		return NDIReceiveLoopHandle {
			loop.cancel()
		}
	}
}

private final class NDIThreadReceiveLoop: @unchecked Sendable {
	private let thread: Thread

	init(capture: NDIFrameCapture, callbacks: NDIReceiveLoopCallbacks) {
		let thread = Thread {
			defer {
				Self.wait {
					await callbacks.didStop()
				}
			}

			while !Thread.current.isCancelled {
				let frame = capture()
				guard !Thread.current.isCancelled else { return }

				Self.wait {
					await callbacks.receive(frame)
				}
			}
		}
		thread.name = "swift-ndi.receive"
		thread.qualityOfService = .userInitiated
		self.thread = thread
		thread.start()
	}

	deinit {
		thread.cancel()
	}

	func cancel() {
		thread.cancel()
	}

	private static func wait(for operation: @escaping @Sendable () async -> Void) {
		let semaphore = DispatchSemaphore(value: 0)
		Task {
			await operation()
			semaphore.signal()
		}
		semaphore.wait()
	}
}

private final class NDIFrameSubscriptionToken: @unchecked Sendable {
	let id = UUID()
	private let cancelled = Mutex(false)

	var isCancelled: Bool {
		cancelled.withLock { $0 }
	}

	func cancel() {
		cancelled.withLock { $0 = true }
	}
}

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

	public nonisolated let sourceName: String
	private var source: NDISource?

	private let makeCapture: @Sendable (NDISource?, String) async -> NDIFrameCapture?
	private let startReceiveLoop: NDIReceiveLoopStarter

	public init(name: String) {
		self.sourceName = name
		self.makeCapture = Self.liveCapture
		self.startReceiveLoop = .live
	}

	public init(source: NDISource) {
		self.sourceName = source.name
		self.source = source
		self.makeCapture = Self.liveCapture
		self.startReceiveLoop = .live
	}

	init(
		name: String,
		capture: NDIFrameCapture,
		startReceiveLoop: NDIReceiveLoopStarter
	) {
		self.sourceName = name
		self.makeCapture = { _, _ in capture }
		self.startReceiveLoop = startReceiveLoop
	}

	private static func liveCapture(source: NDISource?, sourceName: String) async -> NDIFrameCapture? {
		let receiver: NDIReceiver
		if let source {
			guard let sourceReceiver = NDIReceiver(source: source) else { return nil }
			receiver = sourceReceiver
		} else {
			guard let namedReceiver = NDIReceiver() else { return nil }
			await namedReceiver.connect(name: sourceName)
			receiver = namedReceiver
		}

		return NDIFrameCapture {
			receiver.capture(timeout: .seconds(1))
		}
	}

	private var getCaptureTask: Task<NDIFrameCapture?, Never>?

	private func getCapture() async -> NDIFrameCapture? {
		if let getCaptureTask {
			return await getCaptureTask.value
		}

		let source = self.source
		let sourceName = self.sourceName
		let makeCapture = self.makeCapture
		let task = Task {
			await makeCapture(source, sourceName)
		}
		getCaptureTask = task
		return await task.value
	}

	private enum ReceiveLoopState {
		case stopped
		case starting(UUID)
		case running(UUID, NDIReceiveLoopHandle)
		case stopping(UUID)
	}

	private var receiveLoopState = ReceiveLoopState.stopped

	private func reconcileReceiving() async {
		guard !frameSubscriptions.isEmpty else {
			if case let .running(id, loop) = receiveLoopState {
				receiveLoopState = .stopping(id)
				loop.cancel()
			} else if case let .starting(id) = receiveLoopState {
				receiveLoopState = .stopping(id)
			}
			return
		}

		guard case .stopped = receiveLoopState else { return }

		let id = UUID()
		receiveLoopState = .starting(id)
		guard let capture = await getCapture() else {
			if case .starting(id) = receiveLoopState {
				receiveLoopState = .stopped
			}
			return
		}

		guard case .starting(id) = receiveLoopState else {
			if case .stopping(id) = receiveLoopState {
				receiveLoopState = .stopped
				await reconcileReceiving()
			}
			return
		}

		let callbacks = NDIReceiveLoopCallbacks(
			receive: { [weak self] frame in
				await self?.receive(frame: frame, from: id)
			},
			didStop: { [weak self] in
				await self?.receiveLoopDidStop(id: id)
			}
		)
		let loop = startReceiveLoop(capture: capture, callbacks: callbacks)
		receiveLoopState = .running(id, loop)

		if frameSubscriptions.isEmpty {
			receiveLoopState = .stopping(id)
			loop.cancel()
		}
	}

	private func receiveLoopDidStop(id: UUID) async {
		switch receiveLoopState {
		case .running(id, _), .stopping(id):
			receiveLoopState = .stopped
			await reconcileReceiving()
		case .stopped, .starting, .running, .stopping:
			break
		}
	}

	private func receive(frame: NDIReceivedFrame, from id: UUID) {
		guard case .running(id, _) = receiveLoopState else { return }

		for subscription in frameSubscriptions.values {
			switch subscription.continuation.yield(frame) {
			case .enqueued, .terminated:
				break
			case let .dropped(droppedFrame):
				subscription.onDroppedFrame?(droppedFrame)
			@unknown default:
				break
			}
		}
	}

	@discardableResult
	public func connect() async -> Bool {
		await getCapture() != nil
	}

	public typealias FrameStream = AsyncStream<NDIReceivedFrame>
	public typealias DroppedFrameHandler = @Sendable (NDIReceivedFrame) -> Void

	private struct FrameSubscription {
		var continuation: FrameStream.Continuation
		var onDroppedFrame: DroppedFrameHandler?
	}

	private var frameSubscriptions: [UUID: FrameSubscription] = [:]

	var activeSubscriptionCount: Int {
		frameSubscriptions.count
	}

	private func registerContinuation(
		_ continuation: FrameStream.Continuation,
		token: NDIFrameSubscriptionToken,
		onDroppedFrame: DroppedFrameHandler?
	) async {
		guard !token.isCancelled else { return }

		frameSubscriptions[token.id] = FrameSubscription(
			continuation: continuation,
			onDroppedFrame: onDroppedFrame
		)
		await reconcileReceiving()
	}

	private func unregisterContinuation(_ id: UUID) async {
		frameSubscriptions.removeValue(forKey: id)
		await reconcileReceiving()
	}

	/// Creates a frame stream with a policy specific to this subscriber.
	///
	/// `onDroppedFrame` runs when this subscriber's buffer evicts a frame. It should
	/// return quickly so it does not delay delivery to the other subscribers.
	public nonisolated func frames(
		bufferingPolicy: NDIFrameBufferingPolicy,
		onDroppedFrame: DroppedFrameHandler? = nil
	) -> FrameStream {
		let token = NDIFrameSubscriptionToken()
		let (stream, continuation) = FrameStream.makeStream(bufferingPolicy: bufferingPolicy.streamPolicy)

		continuation.onTermination = { [weak self, token] _ in
			token.cancel()
			Task {
				await self?.unregisterContinuation(token.id)
			}
		}

		Task { [weak self, token] in
			await self?.registerContinuation(
				continuation,
				token: token,
				onDroppedFrame: onDroppedFrame
			)
		}

		return stream
	}

	/// Compatibility overload retaining the original 60-frame default.
	public nonisolated func frames(bufferingNewest: Int = 60) -> FrameStream {
		frames(bufferingPolicy: .bufferingNewest(bufferingNewest))
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
