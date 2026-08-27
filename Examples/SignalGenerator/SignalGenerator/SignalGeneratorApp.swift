import SwiftUI

@main
struct SignalGeneratorApp: App {
	@State private var model = SignalGeneratorModel()

	var body: some Scene {
		Window("Signal Generator", id: "signal-generator") {
			ContentView(model: model)
		}
		.defaultSize(width: 1120, height: 720)
		.commands {
			CommandMenu("Signal") {
				Button(model.isSending ? "Stop Sending" : "Start Sending") {
					model.toggleSending()
				}
				.keyboardShortcut(.space, modifiers: [])
			}
		}
	}
}
