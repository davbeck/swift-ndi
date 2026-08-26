import SwiftUI

struct ContentView: View {
	@Bindable var model: SignalGeneratorModel
	@State private var inspectorPresented = true

	var body: some View {
		VStack(spacing: 0) {
			preview
			statusBar
		}
		.background(.black)
		.inspector(isPresented: $inspectorPresented) {
			SignalInspector(model: model)
				.inspectorColumnWidth(min: 240, ideal: 280, max: 360)
		}
		.toolbar {
			ToolbarItem {
				Button(model.isSending ? "Stop" : "Start", systemImage: model.isSending ? "stop.fill" : "play.fill") {
					model.toggleSending()
				}
				.help(model.isSending ? "Stop Sending" : "Start Sending")
			}

			ToolbarItem(placement: .primaryAction) {
				Button("Inspector", systemImage: "sidebar.trailing") {
					inspectorPresented.toggle()
				}
				.help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
				.accessibilityLabel(inspectorPresented ? "Hide Inspector" : "Show Inspector")
			}
		}
		.onChange(of: model.configuration) {
			model.restartIfSending()
		}
	}

	private var preview: some View {
		ZStack {
			Color.black

			if let image = model.preview {
				Image(decorative: image, scale: 1)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.shadow(color: .black.opacity(0.5), radius: 20)
					.padding(24)
			} else {
				ContentUnavailableView(
					"Signal Preview",
					systemImage: "waveform.path.ecg.rectangle",
					description: Text("Start sending to generate an NDI test signal.")
				)
				.environment(\.colorScheme, .dark)
			}
		}
		.frame(minWidth: 520, minHeight: 360)
		.clipped()
	}

	private var statusBar: some View {
		HStack(spacing: 8) {
			Circle()
				.fill(model.isSending ? Color.green : Color.secondary)
				.frame(width: 7, height: 7)
				.accessibilityHidden(true)
			Text(model.status)
				.lineLimit(1)
			Spacer()
			Text(model.frameLabel)
				.monospacedDigit()
			Divider().frame(height: 12)
			Label("\(model.connectionCount)", systemImage: "display.2")
				.help("Connected NDI receivers")
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 12)
		.frame(height: 28)
		.background(.bar)
	}
}

private struct SignalInspector: View {
	@Bindable var model: SignalGeneratorModel

	var body: some View {
		Form {
			Section("NDI Source") {
				TextField("Name", text: $model.configuration.sourceName)
					.textFieldStyle(.roundedBorder)
			}

			Section("Video Format") {
				Picker("Resolution", selection: $model.configuration.resolution) {
					ForEach(SignalResolution.allCases) { resolution in
						Text(resolution.rawValue).tag(resolution)
					}
				}
				LabeledContent("Dimensions", value: model.configuration.resolution.dimensions)
				Picker("Frame Rate", selection: $model.configuration.frameRate) {
					ForEach(SignalFrameRate.allCases) { frameRate in
						Text(frameRate.rawValue).tag(frameRate)
					}
				}
			}

			Section("Test Pattern") {
				Picker("Pattern", selection: $model.configuration.pattern) {
					ForEach(SignalPattern.allCases) { pattern in
						Text(pattern.rawValue).tag(pattern)
					}
				}
				Toggle("Show Source Name", isOn: $model.configuration.showSourceName)
				Toggle("Show Signal Details", isOn: $model.configuration.showSignalDetails)
			}
		}
		.formStyle(.grouped)
		.toggleStyle(.checkbox)
		.padding(.top, 4)
	}
}

#Preview {
	ContentView(model: SignalGeneratorModel())
		.frame(width: 1_120, height: 720)
}
