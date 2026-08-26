import CoreMedia
import CoreVideo
import libNDI
@testable import NDI
import Synchronization
import Testing

struct NDISenderTests {
	@Test
	func createsAndDestroysTheSDKSenderOnce() async throws {
		let probe = SenderProbe()
		var sender: NDISender? = NDISender(name: "swift-ndi sender test", ndi: probe.ndi)

		#expect(sender != nil)
		#expect(probe.createCount == 1)

		sender = nil
		await Task.megaYield()
		#expect(probe.destroyCount == 1)
	}

	@Test
	func sendsVideoFramesSynchronously() throws {
		let probe = SenderProbe()
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))

		try sender.send(makeFrame())

		#expect(probe.sendCount == 1)
		#expect(probe.receivedVideoBuffer)
	}

	@Test
	func reportsConnectedReceivers() throws {
		let probe = SenderProbe()
		probe.connectionCount = 3
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))

		#expect(sender.connectionCount() == 3)
	}

	@Test
	func keepsPooledPlayersSeparateForEachReceiverConfiguration() {
		let highest = NDIPlayer.player(for: "Configuration Test")
		let lowest = NDIPlayer.player(
			for: "Configuration Test",
			configuration: .init(bandwidth: .lowest, capturedMedia: [.video])
		)
		let lowestAgain = NDIPlayer.player(
			for: "Configuration Test",
			configuration: .init(bandwidth: .lowest, capturedMedia: [.video])
		)

		#expect(highest !== lowest)
		#expect(lowest === lowestAgain)
	}

	private func makeFrame() throws -> NDISendVideoFrame {
		var pixelBuffer: CVPixelBuffer?
		#expect(CVPixelBufferCreate(
			kCFAllocatorDefault,
			2,
			2,
			kCVPixelFormatType_32BGRA,
			[kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
			&pixelBuffer
		) == kCVReturnSuccess)
		return try NDISendVideoFrame(
			pixelBuffer: #require(pixelBuffer),
			frameRate: CMTime(value: 2, timescale: 1),
			timecode: .init(rawValue: NDIlib_send_timecode_synthesize)
		)
	}
}

private final class SenderProbe: @unchecked Sendable {
	private struct State: Sendable {
		var createCount = 0
		var destroyCount = 0
		var sendCount = 0
		var connectionCount = 0
		var receivedVideoBuffer = false
	}

	private let state = Mutex(State())

	var createCount: Int { state.withLock(\.createCount) }
	var destroyCount: Int { state.withLock(\.destroyCount) }
	var sendCount: Int { state.withLock(\.sendCount) }
	var receivedVideoBuffer: Bool { state.withLock(\.receivedVideoBuffer) }

	var connectionCount: Int {
		get { state.withLock(\.connectionCount) }
		set { state.withLock { $0.connectionCount = newValue } }
	}

	var ndi: NDI {
		let probe = self
		var ndi = NDI()
		ndi.NDIlib_send_create = { [probe] _ in
			probe.state.withLock { $0.createCount += 1 }
			return NDIlib_send_instance_t(bitPattern: 1)
		}
		ndi.NDIlib_send_destroy = { [probe] _ in
			probe.state.withLock { $0.destroyCount += 1 }
		}
		ndi.NDIlib_send_get_no_connections = { [probe] _, _ in
			probe.state.withLock { Int32($0.connectionCount) }
		}
		ndi.NDIlib_send_send_video_v2 = { [probe] _, frame in
			probe.state.withLock { state in
				state.sendCount += 1
				state.receivedVideoBuffer = frame?.pointee.p_data != nil
			}
		}
		return ndi
	}
}
