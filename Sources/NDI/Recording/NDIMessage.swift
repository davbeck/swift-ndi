import Foundation

public enum NDIMessage: Equatable {
	case recordStarted(NDIRecordStartedMessage)

	case recording(NDIRecordingMessage)

	case recordStopped(NDIRecordStoppedMessage)
}

public struct NDIRecordStartedMessage: Equatable {
	// <record_started filename="/Users/davbeck/Movies/Recordings/Test.mov" filename_pvw="/Users/davbeck/Movies/Recordings/Test.mov.preview" frame_rate_n="30000" frame_rate_d="1000" xres="1080" yres="1920"/>

	var filename: String

	var previewFilename: String

	var frameRateNumerator: Int

	var frameRateDenominator: Int

	var frameRate: Float {
		Float(frameRateNumerator) / Float(frameRateDenominator)
	}

	var xResolution: Int?
	var yResolution: Int?

	var resolution: CGSize? {
		guard let xResolution, let yResolution else { return nil }
		return CGSize(width: xResolution, height: yResolution)
	}
}

public struct NDIRecordingMessage: Equatable {
	// <recording no_frames="21" timecode="154139000000" real_timecode_inflight="154139333333" vu_dB="-54.688214" start_timecode="154132333333"/>
	// <recording no_frames="567" timecode="154321000000" real_timecode_inflight="154321333333" vu_dB="-54.694326"/>
	// <recording no_frames="313" timecode="154236333333" real_timecode_inflight="154236666667" vu_dB="-inf"/>

	var numberOfFramesWritten: Int

	var timecode: Int64

	var realTimecodeInFlight: Int64

	var vuDB: Double

	var startTimecode: Int64?
}

public struct NDIRecordStoppedMessage: Equatable {
	// <record_stopped no_frames="1019" last_timecode="154471666667"/>

	var numberOfFramesWritten: Int

	var lastTimecode: Int64
}
