import CoreMedia
import CoreVideo
import Dependencies
import libNDI

/// The program and preview tally state reported by connected receivers.
public struct NDISenderTally: Equatable, Sendable {
	/// Whether the source is currently on a receiver's program output.
	public var isOnProgram: Bool
	/// Whether the source is currently on a receiver's preview output.
	public var isOnPreview: Bool

	/// Creates a tally state.
	///
	/// - Parameters:
	///   - isOnProgram: Whether the source is on program output.
	///   - isOnPreview: Whether the source is on preview output.
	public init(isOnProgram: Bool, isOnPreview: Bool) {
		self.isOnProgram = isOnProgram
		self.isOnPreview = isOnPreview
	}
}
