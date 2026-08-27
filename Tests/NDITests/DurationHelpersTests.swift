import Testing
@testable import NDI

struct DurationHelpersTests {
	@Test func seconds() {
		let duration = Duration.seconds(1.2)

		#expect(duration.seconds == 1.2)
	}

	@Test func milliseconds() {
		let duration = Duration.seconds(1.2)

		#expect(duration.milliseconds == 1200)
	}
}
