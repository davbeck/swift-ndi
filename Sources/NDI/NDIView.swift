import AVFoundation
import Metal
import MetalKit
import SwiftUI

@MainActor
public struct NDIView {
	public typealias NSViewType = MTKView

	public var player: NDIPlayer

	public init(player: NDIPlayer) {
		self.player = player
	}

	public func makeCoordinator() -> NDIViewCoordinator {
		NDIViewCoordinator(player: player)
	}

	private func makePlatformView(coordinator: NDIViewCoordinator) -> MTKView {
		let view = MTKView()
		view.delegate = coordinator
		//		view.backgroundColor = context.environment.colorScheme == .dark ? UIColor.white : UIColor.white
		//		view.isOpaque = true
		view.enableSetNeedsDisplay = true

		view.framebufferOnly = false
		view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
		view.drawableSize = view.frame.size
		view.enableSetNeedsDisplay = true

		return view
	}

	private func updatePlatformView(_ view: MTKView, coordinator: NDIViewCoordinator) {
		coordinator.player = player
		coordinator.mtkView = view
	}
}

#if canImport(Cocoa)
	import Cocoa

	extension NDIView: NSViewRepresentable {
		public func makeNSView(context: NSViewRepresentableContext<NDIView>) -> MTKView {
			self.makePlatformView(coordinator: context.coordinator)
		}

		public func updateNSView(_ view: MTKView, context: NSViewRepresentableContext<NDIView>) {
			updatePlatformView(view, coordinator: context.coordinator)
		}
	}

#elseif canImport(UIKit)
	import UIKit

	extension NDIView: UIViewRepresentable {
		public func makeUIView(context: UIViewRepresentableContext<NDIView>) -> MTKView {
			self.makePlatformView(coordinator: context.coordinator)
		}

		public func updateUIView(_ view: MTKView, context: UIViewRepresentableContext<NDIView>) {
			updatePlatformView(view, coordinator: context.coordinator)
		}
	}
#endif

@MainActor
public class NDIViewCoordinator: NSObject, MTKViewDelegate {
	let device = MTLCreateSystemDefaultDevice()

	var ciContext: CIContext?

	var metalCommandQueue: MTLCommandQueue?

	var mtkView: MTKView? {
		didSet {
			oldValue?.delegate = nil
			mtkView?.delegate = self

			mtkView?.device = device

			mtkView?.isPaused = frame == nil
		}
	}

	var frame: NDIVideoFrame? {
		didSet {
			mtkView?.isPaused = frame == nil
		}
	}

	private var playerTask: Task<Void, Never>? {
		didSet {
			oldValue?.cancel()
		}
	}

	var player: NDIPlayer {
		didSet {
			guard player !== oldValue else { return }

			self.play()
		}
	}

	init(player: NDIPlayer) {
		self.player = player

		metalCommandQueue = device?.makeCommandQueue()
		ciContext = device.flatMap { CIContext(mtlDevice: $0) }

		super.init()

		mtkView?.isPaused = true
		self.play()
	}

	deinit {
		playerTask?.cancel()
	}

	func play() {
		playerTask = Task { [weak self, player] in
			for await frame in player.videoFrames {
				self?.frame = frame
			}
		}
	}

	public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

	public func draw(in view: MTKView) {
		guard
			let frame,
			let pixelBuffer = frame.pixelBuffer,
			let metalCommandQueue,
			let ciContext,
			let drawable = view.currentDrawable,
			let commandBuffer = metalCommandQueue.makeCommandBuffer()
		else {
			return
		}

		let inputImage = CIImage(cvPixelBuffer: pixelBuffer)

		var size = view.bounds
		size.size = view.drawableSize
		size = AVMakeRect(aspectRatio: inputImage.extent.size, insideRect: size)
		let filteredImage = inputImage.transformed(by: CGAffineTransform(
			scaleX: size.size.width / inputImage.extent.size.width,
			y: size.size.height / inputImage.extent.size.height
		))
		let x = -size.origin.x
		let y = -size.origin.y

		ciContext.render(
			filteredImage,
			to: drawable.texture,
			commandBuffer: commandBuffer,
			bounds: CGRect(origin: CGPoint(x: x, y: y), size: view.drawableSize),
			colorSpace: CGColorSpaceCreateDeviceRGB()
		)

		commandBuffer.present(drawable)
		commandBuffer.commit()
	}
}

#Preview {
	NDIView(player: .player(for: "IPHONE BC97 (HX Camera)"))
}
