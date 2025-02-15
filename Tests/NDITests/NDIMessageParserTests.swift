import Foundation
import Testing

@testable import NDI

struct NDIMessageParserTests {
	@Test func parse_record_started() async throws {
		// given
		let xml = #"""
		<record_started filename="/Users/davbeck/Movies/Recordings/Test.mov" filename_pvw="/Users/davbeck/Movies/Recordings/Test.mov.preview" frame_rate_n="30000" frame_rate_d="1000" xres="1080" yres="1920"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recordStarted(
				.init(
					filename: "/Users/davbeck/Movies/Recordings/Test.mov",
					previewFilename: "/Users/davbeck/Movies/Recordings/Test.mov.preview",
					frameRateNumerator: 30000,
					frameRateDenominator: 1000,
					xResolution: 1080,
					yResolution: 1920
				)
			)
		)
	}
	
	@Test func parse_record_started_omitted_res() async throws {
		// given
		let xml = #"""
		<record_started filename="e:\Temp 2.mov" filename_pvw="e:\Temp 2.mov.preview" frame_rate_n="60000" frame_rate_d="1001"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recordStarted(
				.init(
					filename: #"e:\Temp 2.mov"#,
					previewFilename: #"e:\Temp 2.mov.preview"#,
					frameRateNumerator: 60000,
					frameRateDenominator: 1001,
					xResolution: nil,
					yResolution: nil
				)
			)
		)
	}
	
	@Test func parse_recording() async throws {
		// given
		let xml = #"""
		<recording no_frames="21" timecode="154139000000" real_timecode_inflight="154139333333" vu_dB="-54.688214" start_timecode="154132333333"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recording(
				.init(
					numberOfFramesWritten: 21,
					timecode: 154139000000,
					realTimecodeInFlight: 154139333333,
					vuDB: -54.688214,
					startTimecode: 154132333333
				)
			)
		)
	}
	
	@Test func parse_recording_withoutStartTimecode() async throws {
		// given
		let xml = #"""
		<recording no_frames="43" timecode="154146333333" real_timecode_inflight="154146666667" vu_dB="-57.499760"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recording(
				.init(
					numberOfFramesWritten: 43,
					timecode: 154146333333,
					realTimecodeInFlight: 154146666667,
					vuDB: -57.499760,
					startTimecode: nil
				)
			)
		)
	}
	
	@Test func parse_recording_negativeInf() async throws {
		// given
		let xml = #"""
		<recording no_frames="313" timecode="154236333333" real_timecode_inflight="154236666667" vu_dB="-inf"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recording(
				.init(
					numberOfFramesWritten: 313,
					timecode: 154236333333,
					realTimecodeInFlight: 154236666667,
					vuDB: -(.infinity),
					startTimecode: nil
				)
			)
		)
	}
	
	@Test func parse_recordStopped() async throws {
		// given
		let xml = #"""
		<record_stopped no_frames="1019" last_timecode="154471666667"/>
		"""#
		let parser = NDIMessageParser(data: Data(xml.utf8))

		// when
		let message = try parser.parse()

		// then
		#expect(
			message == .recordStopped(
				.init(
					numberOfFramesWritten: 1019,
					lastTimecode: 154471666667
				)
			)
		)
	}
}
