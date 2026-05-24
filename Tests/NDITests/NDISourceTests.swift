import Testing
@testable import NDI

struct NDISourceTests {
	@Test
	func exposesNameUrlAndDescription() {
		let source = NDISource(name: "Camera A", url: "ndi://camera-a.local")

		#expect(source.name == "Camera A")
		#expect(source.url == "ndi://camera-a.local")
		#expect(source.id == "ndi://camera-a.local")
		#expect(source.description == #"NDISource(name: "Camera A", url: "ndi://camera-a.local")"#)
	}

	@Test
	func equalityAndHashingUseNameAndUrl() {
		let source = NDISource(name: "Camera A", url: "ndi://camera-a.local")
		let matchingSource = NDISource(name: "Camera A", url: "ndi://camera-a.local")
		let sameNameDifferentUrl = NDISource(name: "Camera A", url: "ndi://camera-b.local")
		let sameUrlDifferentName = NDISource(name: "Camera B", url: "ndi://camera-a.local")

		#expect(source == matchingSource)
		#expect(source != sameNameDifferentUrl)
		#expect(source != sameUrlDifferentName)
		#expect(Set([source, matchingSource, sameNameDifferentUrl, sameUrlDifferentName]).count == 3)
	}
}
