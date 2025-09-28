import NDI
import SwiftUI

struct SourcePicker: View {
	@Binding var selectedSourceName: String?

	@State private var finder = NDIFindManager.shared

	var ndiSources: [NDISource] {
		finder?.sources ?? []
	}

	var body: some View {
		Picker("Source", selection: $selectedSourceName) {
			Text("None")
				.tag(String?.none)

			if let selectedSourceName, !ndiSources.contains(where: { $0.name == selectedSourceName }) {
				Text("\(selectedSourceName) (Disconnected)")
					.tag(Optional.some(selectedSourceName))
			}

			ForEach(ndiSources, id: \.self) { source in
				Text(source.name)
					.tag(Optional.some(source.name))
			}
		}
	}
}

#Preview {
	@Previewable @State var source: String?

	VStack {
		SourcePicker(selectedSourceName: $source)

		Text("Selected: \(source ?? "(none)")")
	}
	.padding()
}
