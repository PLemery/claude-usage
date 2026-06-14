import ServiceManagement
import AppKit

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { /* best-effort; ignore */ }
    }

    /// Ask once, on first launch, whether to start at login. Remembers the answer
    /// so the prompt never appears again. (There is no in-app toggle by design —
    /// it can later be changed in System Settings → General → Login Items.)
    @MainActor
    static func promptForLaunchAtLoginIfNeeded() {
        let key = "didAskLaunchAtLogin"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Launch ClaudeUsage at login?"
        alert.informativeText = "Keep your Claude usage in the menu bar automatically every time you log in. You can change this later in System Settings → General → Login Items."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { set(true) }
    }
}
