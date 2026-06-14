import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var vm = AppViewModel()
    @State private var didStart = false

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(vm: vm)
                .task {
                    // Start the view model exactly once on first appearance.
                    guard !didStart else { return }
                    didStart = true
                    vm.start()
                }
        } label: {
            MenuBarLabel(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }

    // Hide the Dock icon — menu-bar-only app.
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
