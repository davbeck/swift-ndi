#if os(macOS)
	import Foundation
	import Testing

	@testable import NDI

	struct NDIRecorderTests {
		@Test
		func streamsMessagesAndSendsCommands() async throws {
			let executableURL = FileManager.default.temporaryDirectory
				.appending(path: UUID().uuidString)
			defer { try? FileManager.default.removeItem(at: executableURL) }

			let executable = #"""
			#!/bin/sh
			printf '<record_started filename="test.mov" filename_pvw="test.mov.preview" frame_rate_n="30000" frame_rate_d="1000"/>\n'
			while IFS= read -r command; do
				case "$command" in
					'<start/>')
						printf '<recording no_frames="1" timecode="100" real_timecode_inflight="101" vu_dB="-12.5"/>\n'
						;;
					'<exit/>')
						printf '<record_stopped no_frames="1" last_timecode="100"/>\n'
						exit 0
						;;
				esac
			done
			"""#
			try Data(executable.utf8).write(to: executableURL)
			try FileManager.default.setAttributes(
				[.posixPermissions: 0o700],
				ofItemAtPath: executableURL.path()
			)

			let recorder = NDIRecorder(inputName: "Test Input", executableURL: executableURL)
			var messages = try await recorder.launch(autostart: false).makeAsyncIterator()

			#expect(
				try await messages.next() == .recordStarted(
					.init(
						filename: "test.mov",
						previewFilename: "test.mov.preview",
						frameRateNumerator: 30_000,
						frameRateDenominator: 1_000,
						xResolution: nil,
						yResolution: nil
					)
				)
			)

			try await recorder.start()
			#expect(
				try await messages.next() == .recording(
					.init(
						numberOfFramesWritten: 1,
						timecode: 100,
						realTimecodeInFlight: 101,
						vuDB: -12.5,
						startTimecode: nil
					)
				)
			)

			try await recorder.stop()
			#expect(
				try await messages.next() == .recordStopped(
					.init(numberOfFramesWritten: 1, lastTimecode: 100)
				)
			)
			#expect(try await messages.next() == nil)
			await #expect(throws: (any Error).self) {
				try await recorder.start()
			}
		}

		@Test
		func reportsLaunchFailure() async {
			let recorder = NDIRecorder(
				inputName: "Test Input",
				executableURL: URL(filePath: "/does/not/exist")
			)

			await #expect(throws: (any Error).self) {
				_ = try await recorder.launch()
			}
		}
	}
#endif
