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
	dependencies: [
		.package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.6.4"),
	],
	targets: [
		.target(
			name: "NDI",
			dependencies: [
				"libNDI",
				.product(name: "Dependencies", package: "swift-dependencies"),
				.product(name: "DependenciesMacros", package: "swift-dependencies"),
			],
			linkerSettings: [
//				.unsafeFlags([
//					"-L/Library/NDI SDK for Apple/lib/macOS",
//				]),
//				.linkedLibrary("ndi", .when(platforms: [.macOS])),
			]
		),
		.systemLibrary(name: "libNDI"),
		.testTarget(
			name: "NDITests",
			dependencies: ["NDI"]
		),
	]
)
