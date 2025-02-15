import Foundation

public class NDIMessageParser: NSObject {
	private let xmlParser: XMLParser

	private var elementName: String?
	private var attributes: [String: String] = [:]

	private var error: Error?

	public static func parse(line: String) throws -> NDIMessage {
		try self.parse(data: Data(line.utf8))
	}

	public static func parse(data: Data) throws -> NDIMessage {
		let parser = NDIMessageParser(data: data)
		return try parser.parse()
	}

	public init(data: Data) {
		xmlParser = XMLParser(data: data)

		super.init()

		xmlParser.delegate = self
	}

	private func parseAttribute(name: String) throws (Error) -> String {
		guard let value = attributes[name] else {
			throw Error.missingAttribute(message: elementName ?? "", attribute: name)
		}

		return value
	}

	private func parseAttribute<Value: LosslessStringConvertible>(as: Value.Type, name: String) throws (Error) -> Value {
		let valueString = try parseAttribute(name: name)

		guard let value = Value(valueString) else {
			throw Error.invalidAttributeValue(message: elementName ?? "", attribute: name, value: valueString)
		}

		return value
	}

	public func parse() throws (Error) -> NDIMessage {
		xmlParser.parse()

		if let error = xmlParser.parserError {
			throw Error.xmlParsingFailed(error)
		}

		guard let elementName else {
			throw Error.elementNotFound
		}

		switch elementName {
		case "record_started":
			let filename = try parseAttribute(name: "filename")
			let previewFilename = try parseAttribute(name: "filename_pvw")
			let frameRateNumerator = try parseAttribute(as: Int.self, name: "frame_rate_n")
			let frameRateDenominator = try parseAttribute(as: Int.self, name: "frame_rate_d")
			let xResolution = try? parseAttribute(as: Int.self, name: "xres")
			let yResolution = try? parseAttribute(as: Int.self, name: "yres")

			return .recordStarted(
				.init(
					filename: filename,
					previewFilename: previewFilename,
					frameRateNumerator: frameRateNumerator,
					frameRateDenominator: frameRateDenominator,
					xResolution: xResolution,
					yResolution: yResolution
				)
			)
		case "recording":
			let numberOfFramesWritten = try parseAttribute(as: Int.self, name: "no_frames")
			let timecode = try parseAttribute(as: Int64.self, name: "timecode")
			let realTimecodeInFlight = try parseAttribute(as: Int64.self, name: "real_timecode_inflight")
			let vuDB = try parseAttribute(as: Double.self, name: "vu_dB")
			let startTimecode = try? parseAttribute(as: Int64.self, name: "start_timecode")

			return .recording(
				.init(
					numberOfFramesWritten: numberOfFramesWritten,
					timecode: timecode,
					realTimecodeInFlight: realTimecodeInFlight,
					vuDB: vuDB,
					startTimecode: startTimecode
				)
			)
		case "record_stopped":
			let numberOfFramesWritten = try parseAttribute(as: Int.self, name: "no_frames")
			let lastTimecode = try parseAttribute(as: Int64.self, name: "last_timecode")

			return .recordStopped(
				.init(
					numberOfFramesWritten: numberOfFramesWritten,
					lastTimecode: lastTimecode
				)
			)
		default:
			throw Error.unrecognizedMessage(name: elementName)
		}
	}
}

extension NDIMessageParser: XMLParserDelegate {
	public func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?,
		attributes: [String: String] = [:]
	) {
		guard self.elementName == nil else {
			// all messages are a single xml element without any children
			self.error = .additionalElementsFound
			xmlParser.abortParsing()
			return
		}

		self.elementName = elementName
		self.attributes = attributes
	}
}

public extension NDIMessageParser {
	enum Error: Swift.Error {
		case additionalElementsFound
		case elementNotFound
		case unrecognizedMessage(name: String)
		case xmlParsingFailed(any Swift.Error)

		case missingAttribute(message: String, attribute: String)
		case invalidAttributeValue(message: String, attribute: String, value: String)
	}
}
