import SwiftUI

@main
struct ClaudeUsageApp: App {
    var body: some Scene {
        MenuBarExtra("…", systemImage: "gauge.medium") {
            Text("Hello from the menu bar")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
