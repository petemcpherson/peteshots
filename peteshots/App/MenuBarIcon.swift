import AppKit

/// Menu bar icon: viewfinder corner brackets with a bold "P" in the middle.
/// Template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let brackets = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let b = brackets.size
                brackets.draw(in: NSRect(x: (rect.width - b.width) / 2,
                                         y: (rect.height - b.height) / 2,
                                         width: b.width, height: b.height))
            }

            let font = NSFont.systemFont(ofSize: 11, weight: .heavy)
            let text = NSAttributedString(string: "P", attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ])
            let t = text.size()
            // Center on the glyph's cap height, not the line box, so the P sits visually centered.
            let baselineY = (rect.height - font.capHeight) / 2
            text.draw(at: NSPoint(x: (rect.width - t.width) / 2,
                                  y: baselineY + font.descender))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Peteshots"
        return image
    }()
}
