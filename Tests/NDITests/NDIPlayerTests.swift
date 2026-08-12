import ConcurrencyExtras
import Dependencies
import Foundation
import libNDI
import Synchronization
import Testing
@testable import NDI

struct NDIPlayerTests {
	@Test
	func sharesOneReceiveLoopAndWaitsForItToStopBeforeRestarting() async throws {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)

		let firstConsumer = consume(player.frames())
		#expect(await startEvents.next() == 1)

		let secondConsumer = consume(player.frames())
		await Task.megaYield()
		#expect(await player.activeSubscriptionCount == 2)
		#expect(probe.startCount == 1)

		firstConsumer.cancel()
		await firstConsumer.value
		await Task.megaYield()
		#expect(await player.activeSubscriptionCount == 1)
		#expect(probe.cancelCount == 0)

		secondConsumer.cancel()
		await secondConsumer.value
		await Task.megaYield()
		#expect(await player.activeSubscriptionCount == 0)
		#expect(probe.cancelCount == 1)

		let thirdConsumer = consume(player.frames())
		await Task.megaYield()
		#expect(await player.activeSubscriptionCount == 1)
		#expect(probe.startCount == 1)

		await probe.stopLoop(at: 0)
		#expect(await startEvents.next() == 2)
		#expect(probe.maximumActiveLoopCount == 1)

		thirdConsumer.cancel()
		await thirdConsumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 1)
	}

	@Test
	func reportsFramesEvictedFromEachSubscribersBuffer() async {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let droppedFrameCount = Mutex(0)
		let stream = player.frames(bufferingPolicy: .bufferingNewest(1)) { _ in
			droppedFrameCount.withLock { $0 += 1 }
		}
		#expect(await startEvents.next() == 1)

		await probe.send(.none, toLoopAt: 0)
		await probe.send(.statusChange, toLoopAt: 0)
		await probe.send(.unknown, toLoopAt: 0)

		#expect(droppedFrameCount.withLock { $0 } == 2)
		var iterator = stream.makeAsyncIterator()
		let frame = await iterator.next()
		if case .unknown? = frame {
			// Expected: the newest frame remains buffered.
		} else {
			Issue.record("Expected the newest frame to remain buffered")
		}

		let consumer = consume(stream)
		consumer.cancel()
		await consumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 0)
	}

	@Test
	func doesNotReplayTheLastVideoFrameToANewSubscriber() async throws {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let firstStream = player.frames()
		#expect(await startEvents.next() == 1)

		let videoFrame = try makeVideoFrame()
		await probe.send(.video(videoFrame), toLoopAt: 0)

		let secondStream = player.frames()
		await Task.megaYield()
		#expect(await player.activeSubscriptionCount == 2)
		await probe.send(.unknown, toLoopAt: 0)

		var secondIterator = secondStream.makeAsyncIterator()
		let firstFrameForSecondSubscriber = await secondIterator.next()
		if case .unknown? = firstFrameForSecondSubscriber {
			// Expected: only a frame received after subscribing is delivered.
		} else {
			Issue.record("A new subscriber received a stale video frame")
		}

		let firstConsumer = consume(firstStream)
		let secondConsumer = consume(secondStream)
		firstConsumer.cancel()
		secondConsumer.cancel()
		await firstConsumer.value
		await secondConsumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 0)
	}

	@Test
	func filtersFramesBeforeTheyConsumeBufferCapacity() async {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let droppedFrameCount = Mutex(0)
		let stream = player.frames(
			bufferingPolicy: .bufferingNewest(1),
			including: { frame in
				if case .unknown = frame {
					return true
				}
				return false
			},
			onDroppedFrame: { _ in
				droppedFrameCount.withLock { $0 += 1 }
			}
		)
		#expect(await startEvents.next() == 1)

		await probe.send(.unknown, toLoopAt: 0)
		await probe.send(.statusChange, toLoopAt: 0)

		#expect(droppedFrameCount.withLock { $0 } == 0)
		var iterator = stream.makeAsyncIterator()
		let frame = await iterator.next()
		if case .unknown? = frame {
			// Expected: the excluded status did not evict the included frame.
		} else {
			Issue.record("An excluded frame consumed subscriber buffer capacity")
		}

		let consumer = consume(stream)
		consumer.cancel()
		await consumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 0)
	}

	@Test
	func markerIsOrderedWithReceivedFrames() async throws {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let stream = player.frames(bufferingPolicy: .bufferingNewest(3))
		#expect(await startEvents.next() == 1)

		await probe.send(.statusChange, toLoopAt: 0)
		let marker = try NDIFrameMarker(id: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")))
		#expect(await player.yieldMarker(marker) == marker)
		await probe.send(.unknown, toLoopAt: 0)

		var iterator = stream.makeAsyncIterator()
		if case .statusChange? = await iterator.next() {
			// Expected first frame.
		} else {
			Issue.record("Expected the received frame before the marker")
		}
		if case let .marker(receivedMarker)? = await iterator.next() {
			#expect(receivedMarker == marker)
		} else {
			Issue.record("Expected the marker between received frames")
		}
		if case .unknown? = await iterator.next() {
			// Expected final frame.
		} else {
			Issue.record("Expected the received frame after the marker")
		}

		let consumer = consume(stream)
		consumer.cancel()
		await consumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 0)
	}

	@Test
	func evictedMarkerIsDeliveredToDropHandler() async throws {
		let probe = ReceiveLoopProbe()
		var startEvents = probe.startEvents.makeAsyncIterator()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let droppedMarkers = Mutex<[NDIFrameMarker]>([])
		let stream = player.frames(
			bufferingPolicy: .bufferingNewest(1),
			onDroppedFrame: { frame in
				guard case let .marker(marker) = frame else { return }
				droppedMarkers.withLock { $0.append(marker) }
			}
		)
		#expect(await startEvents.next() == 1)

		let marker = try NDIFrameMarker(id: #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555")))
		await player.yieldMarker(marker)
		await probe.send(.unknown, toLoopAt: 0)

		#expect(droppedMarkers.withLock { $0 } == [marker])
		var iterator = stream.makeAsyncIterator()
		if case .unknown? = await iterator.next() {
			// Expected: the later frame evicted the marker.
		} else {
			Issue.record("Expected the newest received frame")
		}

		let consumer = consume(stream)
		consumer.cancel()
		await consumer.value
		await Task.megaYield()
		await probe.stopLoop(at: 0)
	}

	@Test
	func registeredStreamReceivesMarkerYieldedImmediatelyWithAnotherSubscriber() async throws {
		let probe = ReceiveLoopProbe()
		let player = NDIPlayer(
			name: "Test",
			capture: NDIFrameCapture { .none },
			startReceiveLoop: probe.starter
		)
		let existingStream = await player.registeredFrames(bufferingPolicy: .bufferingNewest(1))
		let stream = await player.registeredFrames(
			bufferingPolicy: .bufferingNewest(1),
			including: { frame in
				if case .marker = frame {
					return true
				}
				return false
			}
		)

		let marker = try NDIFrameMarker(id: #require(UUID(uuidString: "99999999-8888-7777-6666-555555555555")))
		await player.yieldMarker(marker)

		var iterator = stream.makeAsyncIterator()
		if case let .marker(receivedMarker)? = await iterator.next() {
			#expect(receivedMarker == marker)
		} else {
			Issue.record("Expected the marker yielded immediately after registration")
		}
		#expect(await player.activeSubscriptionCount == 2)

		let existingConsumer = consume(existingStream)
		let consumer = consume(stream)
		existingConsumer.cancel()
		consumer.cancel()
		await existingConsumer.value
		await consumer.value
	}

	private func consume(_ stream: NDIPlayer.FrameStream) -> Task<Void, Never> {
		Task {
			for await _ in stream {}
		}
	}

	private func makeVideoFrame() throws -> NDIReceivedVideoFrame {
		var ndi = NDI()
		ndi.NDIlib_recv_create_v3 = { _ in
			NDIlib_recv_instance_t(bitPattern: 123)
		}
		ndi.NDIlib_recv_destroy = { _ in }
		ndi.NDIlib_recv_free_video_v2 = { _, _ in }

		let receiver = try #require(withDependencies {
			$0.ndi = ndi
		} operation: {
			NDIReceiver()
		})
		let frame = NDIlib_video_frame_v2_t(
			xres: 1,
			yres: 1,
			FourCC: NDIlib_FourCC_video_type_UYVY,
			frame_rate_N: 60,
			frame_rate_D: 1,
			picture_aspect_ratio: 1,
			frame_format_type: NDIlib_frame_format_type_progressive,
			timecode: 0,
			p_data: nil,
			NDIlib_video_frame_v2_t.__Unnamed_union___Anonymous_field9(),
			p_metadata: nil,
			timestamp: 0
		)
		return NDIReceivedVideoFrame(frame, receiver: receiver)
	}
}

private final class ReceiveLoopProbe: @unchecked Sendable {
	private struct Loop: Sendable {
		var callbacks: NDIReceiveLoopCallbacks
		var isActive = true
	}

	private struct State: Sendable {
		var loops: [Loop] = []
		var cancelCount = 0
		var activeLoopCount = 0
		var maximumActiveLoopCount = 0
	}

	private let state = Mutex(State())
	private let startEventsContinuation: AsyncStream<Int>.Continuation
	let startEvents: AsyncStream<Int>

	init() {
		(startEvents, startEventsContinuation) = AsyncStream.makeStream()
	}

	deinit {
		startEventsContinuation.finish()
	}

	var starter: NDIReceiveLoopStarter {
		NDIReceiveLoopStarter { [self] _, callbacks in
			let index = state.withLock { state in
				let index = state.loops.endIndex
				state.loops.append(Loop(callbacks: callbacks))
				state.activeLoopCount += 1
				state.maximumActiveLoopCount = max(state.maximumActiveLoopCount, state.activeLoopCount)
				return index
			}
			startEventsContinuation.yield(index + 1)

			return NDIReceiveLoopHandle { [self] in
				state.withLock { $0.cancelCount += 1 }
			}
		}
	}

	var startCount: Int {
		state.withLock { $0.loops.count }
	}

	var cancelCount: Int {
		state.withLock { $0.cancelCount }
	}

	var maximumActiveLoopCount: Int {
		state.withLock { $0.maximumActiveLoopCount }
	}

	func send(_ frame: NDIReceivedFrame, toLoopAt index: Int) async {
		let callbacks = state.withLock { $0.loops[index].callbacks }
		await callbacks.receive(frame)
	}

	func stopLoop(at index: Int) async {
		let callbacks = state.withLock { state in
			if state.loops[index].isActive {
				state.loops[index].isActive = false
				state.activeLoopCount -= 1
			}
			return state.loops[index].callbacks
		}
		await callbacks.didStop()
	}
}
