import CoreMedia
import Dependencies
import Foundation
import libNDI

/// An absolute point in time used to sync frames.
public struct NDITimecode: Hashable, Sendable {
	public var rawValue: Int64

	public init(rawValue: Int64) {
		self.rawValue = rawValue
	}

	/// Get the current timecode based on the system clock.
	public static var now: NDITimecode {
		@Dependency(\.ndiTimecode) var generator

		return generator.now()
	}
}

public extension Date {
	init(_ timecode: NDITimecode) {
		self.init(timeIntervalSince1970: TimeInterval(timecode.rawValue) / TimeInterval(NDI.timescale))
	}
}

public extension CMTime {
	init(_ timecode: NDITimecode) {
		self.init(value: timecode.rawValue, timescale: CMTimeScale(NDI.timescale))
	}
}

public struct NDITimecodeGenerator: DependencyKey, Sendable {
	var now: @Sendable () -> NDITimecode

	init(now: @escaping @Sendable () -> NDITimecode) {
		self.now = now
	}

	public static let liveValue: NDITimecodeGenerator = .init {
		// adapted from https://github.com/swiftlang/swift-corelibs-foundation/blob/4a9694d396b34fb198f4c6dd865702f7dc0b0dcf/Sources/CoreFoundation/CFDate.c#L80
		// TODO: handle Windows

		var tv = timeval()
		gettimeofday(&tv, nil)
		var rawValue = Int64(tv.tv_sec) * NDI.timescale
		rawValue += Int64(tv.tv_usec) * (NDI.timescale / 1_000_000)

		return .init(rawValue: rawValue)
	}

	public static var testValue: NDITimecodeGenerator {
		.init(
			now: unimplemented(
				"NDITimecode.now",
				placeholder: NDITimecode(rawValue: NDIlib_recv_timestamp_undefined)
			)
		)
	}
}

public extension DependencyValues {
	var ndiTimecode: NDITimecodeGenerator {
		get { self[NDITimecodeGenerator.self] }
		set { self[NDITimecodeGenerator.self] = newValue }
	}
}
