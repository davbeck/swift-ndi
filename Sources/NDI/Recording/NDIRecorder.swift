#if os(macOS)
	import Foundation
	import IssueReporting
	import OSLog

	private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "NDIRecorder")

	/// A wrapper for the [NDI recording CLI](https://docs.ndi.video/all/developing-with-ndi/sdk/command-line-tools)
	///
	/// You will need to have access to the NDI recording executable at runtime. When the NDI SDK is installed, this is located at `/Library/NDI\ SDK\ for\ Apple/bin/Application.Mac.NDI.Recording`.
	public final class NDIRecorder {
		let process = Process()
		let standardOutput = Pipe()
		let standardError = Pipe()
		let standardInput = Pipe()

		public let inputName: String

		public let executableURL: URL

		/// Create a new recorder instance
		/// - Parameters:
		///   - inputName: The NDI source name to connect to and record. Use ``NDIFind`` or ``NDIFindManager`` to discover sources.
		///   - executableURL: The file URL of the NDI recording executable.
		public init(inputName: String, executableURL: URL) {
			self.inputName = inputName
			self.executableURL = executableURL
		}

		/// Connect to the NDI source and prepare to record.
		/// - Parameters:
		///   - writeThumbnail: Whether a proxy file should be written.
		///   - autostart: This command may be used to achieve frame-accurate recording as needed. When specified, the record application will run and connect to the remote source; however, it will not immediately start recording. It will then start immediately when you call ``start()``.
		///   - autochop: This specifies that if the video properties change (resolution, framerate, aspect ratio), the existing file is chopped, and a new one starts with a number appended. When false, it will simply exit when the video properties change, allowing you to start it again with a new file name should you want. By default, if the video format changes, it will open a new file in that format without dropping any frames.
		@discardableResult public func launch(
			writeThumbnail: Bool = true,
			autostart: Bool = true,
			autochop: Bool = true
		) throws -> MessageStream {
			let inputName = self.inputName

			process.standardOutput = standardOutput
			process.standardError = standardError
			process.standardInput = standardInput

			process.executableURL = executableURL

//			/Library/NDI\ SDK\ for\ Apple/bin/Application.Mac.NDI.Recording -i "MEVO-N648P (MEVO-N648P)" -o Test/Library/NDI\ SDK\ for\ Apple/bin/Application.Mac.NDI.DirectoryService

			let date = Date.now.formatted(
				.verbatim(
					"\(year: .extended())-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twelveHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits) \(dayPeriod: .conversational(.wide))",
					timeZone: .current,
					calendar: .current
				)
			)
			let outputURL = URL.moviesDirectory
				.appending(component: "Recordings")
				.appending(component: "\(inputName) \(date)")

			let outputPath = outputURL.path(percentEncoded: false)

			var arguments: [String] = [
				"-i",
				inputName,
				"-o",
				outputPath,
			]
			if !writeThumbnail {
				arguments.append("-nothumbnail")
			}
			if !autochop {
				arguments.append("-noautochop")
			}
			if !autostart {
				arguments.append("-noautostart")
			}

			process.arguments = arguments
			logger.info("starting recording of '\(inputName)' at '\(outputPath)'")

			try process.run()

			Task { [standardError] in
				for try await line in standardError.fileHandleForReading.bytes.lines {
					logger.info("\(line)")
				}
			}

			let stream = standardOutput.fileHandleForReading.bytes.lines
				.compactMap { line in
					do {
						return try NDIMessageParser.parse(line: line)
					} catch {
						logger.error("failed to decode message '\(line)': \(error)")
						return nil
					}
				}

			return MessageStream(underlyingStream: stream)
		}

		/// Start recording at this moment; this is used in conjunction with the “-noautostart” command line.
		public func start() throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data("<start/>\n".utf8))
		}

		/// This will cancel recording and exit the moment that the file is completely on disk.
		public func stop() throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data("<exit/>\n".utf8))
		}

		/// Immediately stop recording, then restart another file without dropping frames.
		public func chop(filename: String? = nil) throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data("<record_chop/>\n".utf8))
		}

		/// Immediately stop recording, and start recording another file in potentially a different location without dropping frames. This allows a recording location to be changed on the fly, allowing you to span recordings across multiple drives or locations.
		public func chop(filename: String) throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data(#"<record_chop filename="\#(filename)"/>\n"#.utf8))
		}

		/// This allows you to control the current recorded audio levels in decibels. 1.2 would apply 1.2 dB of gain to the audio signal while recording to disk.
		public func setRecordLevelGain(_ gain: Float) throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data(#"<record_level gain="\#(gain)"/>\n"#.utf8))
		}

		/// Enable (or disable) automatic gain control for audio, which will use an expander/compressor to normalize the audio while it is being recorded.
		public func setAutomaticGainControl(_ isOn: Bool) throws {
			try standardInput.fileHandleForWriting
				.write(contentsOf: Data(#"<record_agc enabled="\#(isOn)"/>\n"#.utf8))
		}

		public struct MessageStream: AsyncSequence {
			typealias UnderlyingStream = AsyncCompactMapSequence<AsyncLineSequence<FileHandle.AsyncBytes>, NDIMessage>

			fileprivate let underlyingStream: UnderlyingStream

			fileprivate init(underlyingStream: UnderlyingStream) {
				self.underlyingStream = underlyingStream
			}

			public typealias Element = NDIMessage

			public func makeAsyncIterator() -> AsyncIterator {
				AsyncIterator(underlyingIterator: underlyingStream.makeAsyncIterator())
			}

			public struct AsyncIterator: AsyncIteratorProtocol {
				public typealias Element = NDIMessage

				fileprivate var underlyingIterator: UnderlyingStream.AsyncIterator

				fileprivate init(underlyingIterator: UnderlyingStream.AsyncIterator) {
					self.underlyingIterator = underlyingIterator
				}

				public mutating func next() async throws -> NDIMessage? {
					try await underlyingIterator.next()
				}

				public mutating func next(isolation actor: isolated (any Actor)?) async throws -> Element? {
					try await underlyingIterator.next(isolation: actor)
				}
			}
		}
	}
#endif
