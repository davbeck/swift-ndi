import CoreMedia
import Foundation
import Testing
@testable import NDI

struct NDITimecodeTests {
	@Test
	func convertToDate() {
		let timecode = NDITimecode(rawValue: 17_416_279_550_202_790)

		let date = Date(timecode)

		#expect(date == Date(timeIntervalSinceReferenceDate: 763_320_755.0202789))
	}

	@Test
	func convertToCMTime() {
		let timecode = NDITimecode(rawValue: 17_416_279_550_202_790)

		let time = CMTime(timecode)

		#expect(time.value == 17_416_279_550_202_790)
		#expect(time.timescale == 10_000_000)
	}
}
