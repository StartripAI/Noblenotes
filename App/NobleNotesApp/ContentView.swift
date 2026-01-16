import SwiftUI

struct ContentView: View {
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Entry Flow") {
                    if isPad {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Handwrite")
                                .font(.headline)
                            Text("PDF Deep Work")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Capture")
                                .font(.headline)
                            Text("Review")
                                .font(.headline)
                            Text("Share")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Debug") {
                    NavigationLink("Diagnostics Harness") {
                        DebugView()
                    }
                }
            }
            .navigationTitle("NobleNotes")
        }
    }
}

#Preview {
    ContentView()
}
