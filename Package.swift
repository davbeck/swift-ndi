// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "swift-ndi",
	platforms: [
		.macOS(.v15),
	],
	products: [
		.library(
			name: "NDI",
			targets: ["NDI"]
		),
	],
	targets: [
		.target(
			name: "NDI",
			dependencies: ["libNDI"],
			linkerSettings: [
				.unsafeFlags([
					"-L/Library/NDI SDK for Apple/lib/macOS",
				]),
				.linkedLibrary("ndi", .when(platforms: [.macOS])),
			]
		),
		.systemLibrary(name: "libNDI"),
		.testTarget(
			name: "NDITests",
			dependencies: ["NDI"]
		),
	]
)
