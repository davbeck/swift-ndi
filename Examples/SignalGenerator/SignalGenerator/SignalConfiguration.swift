import CoreGraphics
import CoreMedia

nonisolated struct SignalConfiguration: Equatable, Sendable {
	var sourceName = "Signal Generator"
	var resolution = SignalResolution.fullHD
	var frameRate = SignalFrameRate.fps30
	var pattern = SignalPattern.colorBars
	var showSourceName = true
	var showSignalDetails = true
	var sendsAudio = true
	var audioChannels = SignalAudioChannels.stereo
	var audioSampleRate = SignalAudioSampleRate.hz48000
	var toneFrequency = 440.0
	var toneLevel = -20.0
	var sendsMetadata = true
	var metadata = #"<signal_generator event="heartbeat"/>"#
	var sendsConnectionMetadata = true
	var connectionMetadata = #"<ndi_product long_name="swift-ndi Signal Generator" short_name="Signal Generator" manufacturer="swift-ndi" version="1.0" session="default" model_name="SignalGenerator" serial=""/>"#
	var usesFailover = false
	var failoverName = ""
	var failoverURL = ""
}

nonisolated enum SignalResolution: String, CaseIterable, Identifiable, Sendable {
	case hd = "HD 720p"
	case fullHD = "Full HD 1080p"
	case fullHDVertical = "1080 × 1920 (Vertical)"
	case fullHDSquare = "1080 × 1080 (Square)"
	case ultraHD = "Ultra HD 2160p"

	var id: Self {
		self
	}

	var width: Int {
		switch self {
		case .hd: 1280
		case .fullHD: 1920
		case .fullHDVertical, .fullHDSquare: 1080
		case .ultraHD: 3840
		}
	}

	var height: Int {
		switch self {
		case .hd: 720
		case .fullHD, .fullHDSquare: 1080
		case .fullHDVertical: 1920
		case .ultraHD: 2160
		}
	}

	var dimensions: String {
		"\(width) × \(height)"
	}

	var size: CGSize {
		CGSize(width: width, height: height)
	}
}

nonisolated enum SignalFrameRate: String, CaseIterable, Identifiable, Sendable {
	case fps2398 = "23.98 fps"
	case fps24 = "24 fps"
	case fps25 = "25 fps"
	case fps2997 = "29.97 fps"
	case fps30 = "30 fps"
	case fps50 = "50 fps"
	case fps5994 = "59.94 fps"
	case fps60 = "60 fps"

	var id: Self {
		self
	}

	var numerator: Int32 {
		switch self {
		case .fps2398: 24000
		case .fps24: 24
		case .fps25: 25
		case .fps2997: 30000
		case .fps30: 30
		case .fps50: 50
		case .fps5994: 60000
		case .fps60: 60
		}
	}

	var denominator: Int32 {
		switch self {
		case .fps2398, .fps2997, .fps5994: 1001
		default: 1
		}
	}

	var framesPerSecond: Double {
		Double(numerator) / Double(denominator)
	}

	var nominalFramesPerSecond: Int {
		Int(framesPerSecond.rounded())
	}

	var counterLabel: String {
		switch self {
		case .fps2398: "23.98"
		case .fps2997: "29.97"
		case .fps5994: "59.94"
		default: "\(nominalFramesPerSecond)"
		}
	}

	var mediaTime: CMTime {
		CMTime(value: Int64(numerator), timescale: denominator)
	}
}

nonisolated enum SignalPattern: String, CaseIterable, Identifiable, Sendable {
	case colorBars = "Color Bars"
	case grayscale = "Grayscale"
	case checkerboard = "Checkerboard"

	var id: Self {
		self
	}
}

nonisolated enum SignalAudioChannels: String, CaseIterable, Identifiable, Sendable {
	case mono = "Mono"
	case stereo = "Stereo"

	var id: Self {
		self
	}

	var count: Int {
		switch self {
		case .mono: 1
		case .stereo: 2
		}
	}
}

nonisolated enum SignalAudioSampleRate: String, CaseIterable, Identifiable, Sendable {
	case hz44100 = "44.1 kHz"
	case hz48000 = "48 kHz"
	case hz96000 = "96 kHz"

	var id: Self {
		self
	}

	var value: Int {
		switch self {
		case .hz44100: 44100
		case .hz48000: 48000
		case .hz96000: 96000
		}
	}
}
