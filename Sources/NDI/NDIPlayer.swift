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

public struct NDIFrameMarker: Equatable, Hashable, Identifiable, Sendable {
	public let id: UUID

	public init(id: UUID = UUID()) {
		self.id = id
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
	private struct PoolKey: Hashable {
		var sourceName: String
		var configuration: NDIReceiverConfiguration
	}

	private static let playerPool: Mutex<[PoolKey: Weak<NDIPlayer>]> = .init([:])

	public static func player(
		for name: String,
		configuration: NDIReceiverConfiguration = .init()
	) -> NDIPlayer {
		let key = PoolKey(sourceName: name, configuration: configuration)
		return playerPool.withLock { pool in
			if let player = pool[key]?.value {
				return player
			} else {
				let player = NDIPlayer(name: name, configuration: configuration)
				pool[key] = .init(value: player)
				return player
			}
		}
	}

	public nonisolated let sourceName: String
	public nonisolated let configuration: NDIReceiverConfiguration
	private var source: NDISource?

	private let makeCapture: @Sendable (NDISource?, String, NDIReceiverConfiguration) async -> NDIFrameCapture?
	private let startReceiveLoop: NDIReceiveLoopStarter

	public init(name: String, configuration: NDIReceiverConfiguration = .init()) {
		self.sourceName = name
		self.configuration = configuration
		self.makeCapture = Self.liveCapture
		self.startReceiveLoop = .live
	}

	public init(source: NDISource, configuration: NDIReceiverConfiguration = .init()) {
		self.sourceName = source.name
		self.source = source
		self.configuration = configuration
		self.makeCapture = Self.liveCapture
		self.startReceiveLoop = .live
	}

	init(
		name: String,
		configuration: NDIReceiverConfiguration = .init(),
		capture: NDIFrameCapture,
		startReceiveLoop: NDIReceiveLoopStarter
	) {
		self.sourceName = name
		self.configuration = configuration
		self.makeCapture = { _, _, _ in capture }
		self.startReceiveLoop = startReceiveLoop
	}

	private static func liveCapture(
		source: NDISource?,
		sourceName: String,
		configuration: NDIReceiverConfiguration
	) async -> NDIFrameCapture? {
		let receiver: NDIReceiver
		if let source {
			guard let sourceReceiver = NDIReceiver(source: source, configuration: configuration) else { return nil }
			receiver = sourceReceiver
		} else {
			guard let namedReceiver = NDIReceiver(configuration: configuration) else { return nil }
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
		let configuration = self.configuration
		let makeCapture = self.makeCapture
		let task = Task {
			await makeCapture(source, sourceName, configuration)
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
		broadcast(frame)
	}

	private func broadcast(_ frame: NDIReceivedFrame) {
		for subscription in frameSubscriptions.values {
			guard subscription.including?(frame) ?? true else { continue }

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
	public typealias FrameInclusion = @Sendable (NDIReceivedFrame) -> Bool

	private struct FrameSubscription {
		var continuation: FrameStream.Continuation
		var onDroppedFrame: DroppedFrameHandler?
		var including: FrameInclusion?
	}

	private var frameSubscriptions: [UUID: FrameSubscription] = [:]

	var activeSubscriptionCount: Int {
		frameSubscriptions.count
	}

	private func registerContinuation(
		_ continuation: FrameStream.Continuation,
		token: NDIFrameSubscriptionToken,
		onDroppedFrame: DroppedFrameHandler?,
		including: FrameInclusion?
	) async {
		guard !token.isCancelled else { return }

		frameSubscriptions[token.id] = FrameSubscription(
			continuation: continuation,
			onDroppedFrame: onDroppedFrame,
			including: including
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
		makeFrameStream(
			bufferingPolicy: bufferingPolicy,
			including: nil,
			onDroppedFrame: onDroppedFrame
		)
	}

	/// Creates a filtered frame stream with a policy specific to this subscriber.
	///
	/// `including` runs before buffering, so excluded frames cannot consume capacity
	/// or evict an included frame. `including` and `onDroppedFrame` run on the player
	/// actor and should return quickly.
	public nonisolated func frames(
		bufferingPolicy: NDIFrameBufferingPolicy,
		including: @escaping FrameInclusion,
		onDroppedFrame: DroppedFrameHandler? = nil
	) -> FrameStream {
		makeFrameStream(
			bufferingPolicy: bufferingPolicy,
			including: including,
			onDroppedFrame: onDroppedFrame
		)
	}

	private nonisolated func makeFrameStream(
		bufferingPolicy: NDIFrameBufferingPolicy,
		including: FrameInclusion?,
		onDroppedFrame: DroppedFrameHandler?
	) -> FrameStream {
		let preparedStream = prepareFrameStream(bufferingPolicy: bufferingPolicy)

		Task { [weak self, token = preparedStream.token] in
			await self?.registerContinuation(
				preparedStream.continuation,
				token: token,
				onDroppedFrame: onDroppedFrame,
				including: including
			)
		}

		return preparedStream.stream
	}

	/// Creates a frame stream after registering this specific subscription.
	///
	/// A frame or marker yielded after this method returns is visible to this
	/// subscription, subject to its buffering policy.
	public func registeredFrames(
		bufferingPolicy: NDIFrameBufferingPolicy,
		onDroppedFrame: DroppedFrameHandler? = nil
	) async -> FrameStream {
		await makeRegisteredFrameStream(
			bufferingPolicy: bufferingPolicy,
			including: nil,
			onDroppedFrame: onDroppedFrame
		)
	}

	/// Creates a filtered frame stream after registering this specific subscription.
	///
	/// `including` runs before buffering. A frame or marker included and yielded
	/// after this method returns is visible to this subscription, subject to its
	/// buffering policy.
	public func registeredFrames(
		bufferingPolicy: NDIFrameBufferingPolicy,
		including: @escaping FrameInclusion,
		onDroppedFrame: DroppedFrameHandler? = nil
	) async -> FrameStream {
		await makeRegisteredFrameStream(
			bufferingPolicy: bufferingPolicy,
			including: including,
			onDroppedFrame: onDroppedFrame
		)
	}

	private func makeRegisteredFrameStream(
		bufferingPolicy: NDIFrameBufferingPolicy,
		including: FrameInclusion?,
		onDroppedFrame: DroppedFrameHandler?
	) async -> FrameStream {
		let preparedStream = prepareFrameStream(bufferingPolicy: bufferingPolicy)
		await registerContinuation(
			preparedStream.continuation,
			token: preparedStream.token,
			onDroppedFrame: onDroppedFrame,
			including: including
		)
		return preparedStream.stream
	}

	private nonisolated func prepareFrameStream(
		bufferingPolicy: NDIFrameBufferingPolicy
	) -> (stream: FrameStream, continuation: FrameStream.Continuation, token: NDIFrameSubscriptionToken) {
		let token = NDIFrameSubscriptionToken()
		let (stream, continuation) = FrameStream.makeStream(bufferingPolicy: bufferingPolicy.streamPolicy)

		continuation.onTermination = { [weak self, token] _ in
			token.cancel()
			Task {
				await self?.unregisterContinuation(token.id)
			}
		}

		return (stream, continuation, token)
	}

	/// Places a marker after frames already delivered to each current subscriber.
	///
	/// The marker uses each subscriber's normal filtering and buffering policy. If
	/// it is evicted later, it is delivered to that subscriber's drop handler.
	@discardableResult
	public func yieldMarker(_ marker: NDIFrameMarker = NDIFrameMarker()) -> NDIFrameMarker {
		broadcast(.marker(marker))
		return marker
	}

	/// Provides an actor barrier for frame delivery.
	///
	/// After this method returns, drop handlers for frames received or yielded
	/// before the call have completed.
	public func synchronizeFrameDelivery() {}

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
