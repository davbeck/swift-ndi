import CoreMedia
import CoreVideo
import libNDI
import Synchronization
import Testing
@testable import NDI

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
	func sendsPlanarAudio() throws {
		let probe = SenderProbe()
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))
		let frame = try NDISendAudioFrame(
			planarSamples: [[0, 0.25, 0.5], [1, 0.75, 0.5]],
			sampleRate: 48000,
			timecode: NDITimecode(rawValue: 42),
			metadata: "<audio/>"
		)

		sender.send(frame)

		let snapshot = try #require(probe.audio)
		#expect(snapshot.sampleRate == 48000)
		#expect(snapshot.numberOfChannels == 2)
		#expect(snapshot.numberOfSamples == 3)
		#expect(snapshot.timecode == 42)
		#expect(snapshot.metadata == "<audio/>")
		#expect(snapshot.samples == [0, 0.25, 0.5, 1, 0.75, 0.5])
	}

	@Test
	func sendsAndConfiguresConnectionMetadata() throws {
		let probe = SenderProbe()
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))
		let frame = NDISendMetadataFrame(value: "<product name=\"swift-ndi\"/>", timecode: .init(rawValue: 84))

		sender.send(frame)
		sender.addConnectionMetadata(frame)
		sender.clearConnectionMetadata()

		#expect(probe.sentMetadata == ["<product name=\"swift-ndi\"/>"])
		#expect(probe.sentMetadataTimecodes == [84])
		#expect(probe.connectionMetadata == ["<product name=\"swift-ndi\"/>"])
		#expect(probe.clearConnectionMetadataCount == 1)
	}

	@Test
	func capturesAndFreesReceiverMetadata() async throws {
		let probe = SenderProbe()
		probe.metadataToCapture = "<ndi_answer value=\"ok\"/>"
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))
		var frame: NDISenderCapturedMetadataFrame?

		if case let .metadata(capturedFrame) = sender.capture() {
			frame = capturedFrame
		} else {
			Issue.record("Expected captured metadata")
		}

		#expect(frame?.value == "<ndi_answer value=\"ok\"/>")
		frame = nil
		await Task.megaYield()
		#expect(probe.freeMetadataCount == 1)
	}

	@Test
	func reportsTallyChanges() throws {
		let probe = SenderProbe()
		probe.tally = NDISenderTally(isOnProgram: true, isOnPreview: false)
		probe.tallyDidChange = true
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))

		#expect(sender.tally() == NDISenderTally(isOnProgram: true, isOnPreview: false))

		probe.tallyDidChange = false
		#expect(sender.tally() == nil)
	}

	@Test
	func setsAndClearsFailoverSource() throws {
		let probe = SenderProbe()
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))

		sender.setFailoverSource(NDISource(name: "Backup", url: "ndi://backup"))
		#expect(probe.failoverSource == NDISourceSnapshot(name: "Backup", url: "ndi://backup"))

		sender.setFailoverSource(nil)
		#expect(probe.failoverSource == nil)
		#expect(probe.clearedFailover)
	}

	@Test
	func reportsSDKSourceName() throws {
		let probe = SenderProbe()
		let sender = try #require(NDISender(name: "swift-ndi sender test", ndi: probe.ndi))

		#expect(sender.sourceName() == "TEST-HOST (swift-ndi sender test)")
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

private struct AudioSnapshot: Equatable, Sendable {
	var sampleRate: Int32
	var numberOfChannels: Int32
	var numberOfSamples: Int32
	var timecode: Int64
	var metadata: String?
	var samples: [Float]
}

private struct NDISourceSnapshot: Equatable, Sendable {
	var name: String
	var url: String
}

private final class SenderProbe: @unchecked Sendable {
	private struct State: Sendable {
		var createCount = 0
		var destroyCount = 0
		var sendCount = 0
		var connectionCount = 0
		var receivedVideoBuffer = false
		var audio: AudioSnapshot?
		var sentMetadata: [String] = []
		var sentMetadataTimecodes: [Int64] = []
		var connectionMetadata: [String] = []
		var clearConnectionMetadataCount = 0
		var metadataToCapture: String?
		var freeMetadataCount = 0
		var tally = NDISenderTally(isOnProgram: false, isOnPreview: false)
		var tallyDidChange = false
		var failoverSource: NDISourceSnapshot?
		var clearedFailover = false
	}

	private let state = Mutex(State())
	private let sourceName = UnsafeMutablePointer<CChar>.allocate(from: "TEST-HOST (swift-ndi sender test)")
	private let sourceURL = UnsafeMutablePointer<CChar>.allocate(from: "ndi://test-host/source")
	private let source = UnsafeMutablePointer<NDIlib_source_t>.allocate(capacity: 1)

	init() {
		source.initialize(to: NDIlib_source_t(p_ndi_name: sourceName, .init(p_url_address: sourceURL)))
	}

	deinit {
		source.deinitialize(count: 1)
		source.deallocate()
		sourceName.deallocate()
		sourceURL.deallocate()
	}

	var createCount: Int { state.withLock(\.createCount) }
	var destroyCount: Int { state.withLock(\.destroyCount) }
	var sendCount: Int { state.withLock(\.sendCount) }
	var receivedVideoBuffer: Bool { state.withLock(\.receivedVideoBuffer) }
	var audio: AudioSnapshot? { state.withLock(\.audio) }
	var sentMetadata: [String] { state.withLock(\.sentMetadata) }
	var sentMetadataTimecodes: [Int64] { state.withLock(\.sentMetadataTimecodes) }
	var connectionMetadata: [String] { state.withLock(\.connectionMetadata) }
	var clearConnectionMetadataCount: Int { state.withLock(\.clearConnectionMetadataCount) }
	var freeMetadataCount: Int { state.withLock(\.freeMetadataCount) }
	var failoverSource: NDISourceSnapshot? { state.withLock(\.failoverSource) }
	var clearedFailover: Bool { state.withLock(\.clearedFailover) }

	var metadataToCapture: String? {
		get { state.withLock(\.metadataToCapture) }
		set { state.withLock { $0.metadataToCapture = newValue } }
	}

	var tally: NDISenderTally {
		get { state.withLock(\.tally) }
		set { state.withLock { $0.tally = newValue } }
	}

	var tallyDidChange: Bool {
		get { state.withLock(\.tallyDidChange) }
		set { state.withLock { $0.tallyDidChange = newValue } }
	}

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
		ndi.NDIlib_send_send_audio_v3 = { [probe] _, frame in
			guard let frame else { return }
			probe.state.withLock { $0.audio = Self.snapshot(frame.pointee) }
		}
		ndi.NDIlib_send_send_metadata = { [probe] _, frame in
			guard let frame else { return }
			probe.state.withLock {
				$0.sentMetadata.append(Self.metadataString(frame.pointee) ?? "")
				$0.sentMetadataTimecodes.append(frame.pointee.timecode)
			}
		}
		ndi.NDIlib_send_capture = { [probe] _, metadata, _ in
			guard let value = probe.state.withLock(\.metadataToCapture), let metadata else {
				return NDIlib_frame_type_none
			}
			let data = UnsafeMutablePointer<CChar>.allocate(from: value)
			metadata.pointee = NDIlib_metadata_frame_t(
				length: Int32(value.utf8.count + 1),
				timecode: 123,
				p_data: data
			)
			return NDIlib_frame_type_metadata
		}
		ndi.NDIlib_send_free_metadata = { [probe] _, metadata in
			metadata?.pointee.p_data?.deallocate()
			probe.state.withLock { $0.freeMetadataCount += 1 }
		}
		ndi.NDIlib_send_get_tally = { [probe] _, tally, _ in
			let snapshot = probe.state.withLock { ($0.tally, $0.tallyDidChange) }
			tally?.pointee = NDIlib_tally_t(
				on_program: snapshot.0.isOnProgram,
				on_preview: snapshot.0.isOnPreview
			)
			return snapshot.1
		}
		ndi.NDIlib_send_clear_connection_metadata = { [probe] _ in
			probe.state.withLock { $0.clearConnectionMetadataCount += 1 }
		}
		ndi.NDIlib_send_add_connection_metadata = { [probe] _, frame in
			guard let frame else { return }
			probe.state.withLock { $0.connectionMetadata.append(Self.metadataString(frame.pointee) ?? "") }
		}
		ndi.NDIlib_send_set_failover = { [probe] _, source in
			probe.state.withLock { state in
				guard let source else {
					state.failoverSource = nil
					state.clearedFailover = true
					return
				}
				state.failoverSource = NDISourceSnapshot(
					name: String(cString: source.pointee.p_ndi_name),
					url: String(cString: source.pointee.p_url_address)
				)
			}
		}
		ndi.NDIlib_send_get_source_name = { [probe] _ in UnsafePointer(probe.source) }
		return ndi
	}

	private static func snapshot(_ frame: NDIlib_audio_frame_v3_t) -> AudioSnapshot {
		let count = Int(frame.no_channels * frame.no_samples)
		let samples = frame.p_data.map {
			Array(UnsafeBufferPointer(start: UnsafeRawPointer($0).assumingMemoryBound(to: Float.self), count: count))
		} ?? []
		return AudioSnapshot(
			sampleRate: frame.sample_rate,
			numberOfChannels: frame.no_channels,
			numberOfSamples: frame.no_samples,
			timecode: frame.timecode,
			metadata: frame.p_metadata.map(String.init(cString:)),
			samples: samples
		)
	}

	private static func metadataString(_ frame: NDIlib_metadata_frame_t) -> String? {
		frame.p_data.map { String(cString: $0) }
	}
}

private extension UnsafeMutablePointer<CChar> {
	static func allocate(from string: String) -> Self {
		string.utf8CString.withUnsafeBufferPointer { buffer in
			let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: buffer.count)
			pointer.initialize(from: buffer.baseAddress!, count: buffer.count)
			return pointer
		}
	}
}
