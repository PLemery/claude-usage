import SwiftUI
import AppKit

/// Menu-bar item: a colored status dot + the percentage.
/// The dot is a non-template NSImage so its green/yellow/red color survives,
/// while the number stays plain `Text` so macOS gives it the adaptive menu-bar
/// color (auto-contrasting against light or dark wallpapers).
struct MenuBarLabel: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var auth: AuthManager

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.dot(dotColor)).renderingMode(.original)
            Text(vm.menuBarText).monospacedDigit()
        }
    }

    /// Grey when signed out (or no data yet); otherwise the status color.
    private var dotColor: NSColor {
        guard auth.isSignedIn, let f = vm.snapshot?.fiveHour?.fraction else { return .systemGray }
        return AppViewModel.nsColor(for: f)
    }

    private static func dot(_ color: NSColor, diameter: CGFloat = 8) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false   // keep the status color; don't monochrome it
        return image
    }
}
