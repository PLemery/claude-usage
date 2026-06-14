import SwiftUI
import AppKit

/// Menu-bar item: a colored status dot + the percentage.
/// The dot is a non-template NSImage so its green/yellow/red color survives,
/// while the number stays plain `Text` so macOS gives it the adaptive menu-bar
/// color (auto-contrasting against light or dark wallpapers).
struct MenuBarLabel: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.dot(AppViewModel.nsColor(for: vm.snapshot?.fiveHour?.fraction ?? 0)))
                .renderingMode(.original)
            Text(vm.menuBarText).monospacedDigit()
        }
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
