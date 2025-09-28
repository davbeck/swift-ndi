//
//  ContentView.swift
//  Monitor
//
//  Created by David Beck on 9/27/25.
//

import SwiftUI
import NDI

struct ContentView: View {
	@SceneStorage("SelectedSourceName") private var sourceName: String?
	
	@State private var player: NDIPlayer?
	
    var body: some View {
		ZStack {
			Rectangle()
			
			if let sourceName {
				NDIView(player: .player(for: sourceName))
			}
		}
		.toolbar {
			SourcePicker(selectedSourceName: $sourceName)
		}
    }
}

#Preview {
    ContentView()
}
