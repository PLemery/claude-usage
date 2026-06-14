import SwiftUI
import AppKit

/// Owns the view model and starts data loading at real app launch (not on first
/// click). Menu-bar-only: hides the Dock icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = AppViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)  // no Dock icon
        vm.start()                                            // first fetch + login prompt + 30s timer
    }
}

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(vm: delegate.vm, auth: delegate.vm.auth)
        } label: {
            MenuBarLabel(vm: delegate.vm, auth: delegate.vm.auth)
        }
        .menuBarExtraStyle(.window)
    }
}
