import CoreGraphics
import CoreText
import CoreVideo
import Foundation

nonisolated enum SignalFrameRendererError: Error {
	case couldNotCreatePixelBuffer(CVReturn)
	case couldNotLockPixelBuffer(CVReturn)
	case missingPixelBufferBaseAddress
	case couldNotCreateContext
	case couldNotCreateImage
}

nonisolated struct RenderedSignalFrame: @unchecked Sendable {
	let pixelBuffer: CVPixelBuffer
	let image: CGImage
}

nonisolated enum SignalFrameRenderer {
	static func render(
		configuration: SignalConfiguration,
		date: Date,
		frameInSecond: Int
	) throws -> RenderedSignalFrame {
		let width = configuration.resolution.width
		let height = configuration.resolution.height
		var pixelBuffer: CVPixelBuffer?
		let createResult = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			kCVPixelFormatType_32BGRA,
			[
				kCVPixelBufferCGImageCompatibilityKey: true,
				kCVPixelBufferCGBitmapContextCompatibilityKey: true,
			] as CFDictionary,
			&pixelBuffer
		)
		guard createResult == kCVReturnSuccess, let pixelBuffer else {
			throw SignalFrameRendererError.couldNotCreatePixelBuffer(createResult)
		}

		let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, [])
		guard lockResult == kCVReturnSuccess else {
			throw SignalFrameRendererError.couldNotLockPixelBuffer(lockResult)
		}
		defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw SignalFrameRendererError.missingPixelBufferBaseAddress
		}
		guard let context = CGContext(
			data: baseAddress,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
		) else {
			throw SignalFrameRendererError.couldNotCreateContext
		}

		let bounds = CGRect(x: 0, y: 0, width: width, height: height)
		drawPattern(configuration.pattern, in: bounds, context: context)
		drawSafeArea(in: bounds, context: context)

		let clock = systemTimeString(for: date)
		let counter = String(format: "%02d", frameInSecond) + " / " + configuration.frameRate.counterLabel
		let scale = CGFloat(height) / 1080
		drawCentered(clock, y: CGFloat(height) * 0.55, size: 122 * scale, context: context)
		drawCentered(counter, y: CGFloat(height) * 0.40, size: 68 * scale, context: context)

		if configuration.showSourceName {
			drawLabel(configuration.sourceName, at: CGPoint(x: 48 * scale, y: CGFloat(height) - 78 * scale), size: 30 * scale, context: context)
		}
		if configuration.showSignalDetails {
			let details = "\(configuration.resolution.dimensions)   •   \(configuration.frameRate.rawValue)"
			drawLabel(details, at: CGPoint(x: 48 * scale, y: 48 * scale), size: 25 * scale, context: context)
		}

		guard let image = context.makeImage() else {
			throw SignalFrameRendererError.couldNotCreateImage
		}
		return RenderedSignalFrame(pixelBuffer: pixelBuffer, image: image)
	}

	private static func drawPattern(_ pattern: SignalPattern, in bounds: CGRect, context: CGContext) {
		switch pattern {
		case .colorBars:
			let colors: [CGColor] = [
				CGColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
				CGColor(red: 0.75, green: 0.75, blue: 0, alpha: 1),
				CGColor(red: 0, green: 0.75, blue: 0.75, alpha: 1),
				CGColor(red: 0, green: 0.75, blue: 0, alpha: 1),
				CGColor(red: 0.75, green: 0, blue: 0.75, alpha: 1),
				CGColor(red: 0.75, green: 0, blue: 0, alpha: 1),
				CGColor(red: 0, green: 0, blue: 0.75, alpha: 1),
			]
			let barWidth = bounds.width / CGFloat(colors.count)
			for (index, color) in colors.enumerated() {
				context.setFillColor(color)
				context.fill(CGRect(x: CGFloat(index) * barWidth, y: 0, width: barWidth + 1, height: bounds.height))
			}
		case .grayscale:
			let colors = (0 ..< 10).map { CGFloat($0) / 9 }
			let barWidth = bounds.width / CGFloat(colors.count)
			for (index, white) in colors.enumerated() {
				context.setFillColor(CGColor(gray: white, alpha: 1))
				context.fill(CGRect(x: CGFloat(index) * barWidth, y: 0, width: barWidth + 1, height: bounds.height))
			}
		case .checkerboard:
			let cell = bounds.height / 8
			for row in 0 ..< 8 {
				for column in 0 ..< Int(ceil(bounds.width / cell)) {
					let white: CGFloat = (row + column).isMultiple(of: 2) ? 0.72 : 0.12
					context.setFillColor(CGColor(gray: white, alpha: 1))
					context.fill(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
				}
			}
		}
	}

	private static func drawSafeArea(in bounds: CGRect, context: CGContext) {
		context.saveGState()
		context.setStrokeColor(CGColor(gray: 1, alpha: 0.3))
		context.setLineWidth(max(2, bounds.height / 540))
		context.stroke(bounds.insetBy(dx: bounds.width * 0.05, dy: bounds.height * 0.05))
		context.restoreGState()
	}

	private static func drawCentered(_ text: String, y: CGFloat, size: CGFloat, context: CGContext) {
		let line = makeLine(text, size: size)
		let lineBounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
		context.saveGState()
		context.setShadow(offset: .zero, blur: size * 0.12, color: CGColor(gray: 0, alpha: 0.9))
		context.textPosition = CGPoint(x: (CGFloat(context.width) - lineBounds.width) / 2 - lineBounds.minX, y: y)
		CTLineDraw(line, context)
		context.restoreGState()
	}

	private static func drawLabel(_ text: String, at point: CGPoint, size: CGFloat, context: CGContext) {
		let line = makeLine(text, size: size)
		context.saveGState()
		context.setShadow(offset: .zero, blur: size * 0.1, color: CGColor(gray: 0, alpha: 0.9))
		context.textPosition = point
		CTLineDraw(line, context)
		context.restoreGState()
	}

	private static func makeLine(_ text: String, size: CGFloat) -> CTLine {
		let font = CTFontCreateWithName("SFMono-Bold" as CFString, size, nil)
		let attributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key(kCTFontAttributeName as String): font,
			NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
		]
		return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
	}

	private static func systemTimeString(for date: Date) -> String {
		let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: date)
		return String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
	}
}
