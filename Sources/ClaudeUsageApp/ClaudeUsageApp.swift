import SwiftUI
import AppKit
import Sparkle

/// Owns the view model and starts data loading at real app launch (not on first
/// click). Menu-bar-only: hides the Dock icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = AppViewModel()
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
            UsagePopover(vm: delegate.vm, auth: delegate.vm.auth, updater: delegate.updaterController.updater)
        } label: {
            MenuBarLabel(vm: delegate.vm, auth: delegate.vm.auth)
        }
        .menuBarExtraStyle(.window)
    }
}
