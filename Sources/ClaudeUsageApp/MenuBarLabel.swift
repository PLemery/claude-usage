import SwiftUI
import AppKit

/// The menu-bar number. Rendered as a **non-template NSImage** so the color
/// survives — macOS templates plain `Text` in the menu bar to monochrome,
/// which would strip our green/yellow/red.
struct MenuBarLabel: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        Image(nsImage: Self.render(vm.menuBarText,
                                   color: AppViewModel.nsColor(for: vm.snapshot?.fiveHour?.fraction ?? 0)))
            .renderingMode(.original)
    }

    private static func render(_ text: String, color: NSColor) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = text as NSString
        let textSize = string.size(withAttributes: attrs)
        let size = NSSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let image = NSImage(size: size)
        image.lockFocus()
        string.draw(at: .zero, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false   // keep our color; don't let the menu bar monochrome it
        return image
    }
}
