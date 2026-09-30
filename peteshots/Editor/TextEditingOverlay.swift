//
//  TextEditingOverlay.swift
//  peteshots
//

import AppKit

/// The inline editor for a text annotation (spec §5.6). A transparent text
/// view over the canvas, in view points, using the shared text attributes.
final class TextEditingOverlay: NSTextView {
    /// Called with the new string after each edit.
    var onChange: (String) -> Void = { _ in }
    /// Called on Esc or Cmd-Return.
    var onFinish: () -> Void = {}

    /// Typing undo stays inside the edit. The whole edit is one editor undo step.
    private let textUndoManager = UndoManager()
    private var appliedAttributes: (fontSize: CGFloat, colorHex: String, shadowBlur: CGFloat)?

    init(string: String) {
        // TextKit 1 with no padding, so layout matches `NSAttributedString.draw`.
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage(string: string)
        storage.addLayoutManager(layoutManager)

        super.init(frame: .zero, textContainer: container)
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        textContainerInset = .zero
        isHorizontallyResizable = true
        isVerticallyResizable = true
        maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        focusRingType = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var undoManager: UndoManager? { textUndoManager }

    /// Applies the text attributes to all text and to new typing. `fontSize`
    /// is in view points; `shadowBlur` is in device pixels.
    func apply(fontSize: CGFloat, colorHex: String, shadowBlur: CGFloat) {
        if let applied = appliedAttributes,
           applied.fontSize == fontSize, applied.colorHex == colorHex, applied.shadowBlur == shadowBlur {
            return
        }
        appliedAttributes = (fontSize, colorHex, shadowBlur)
        let attributes = TextLayout.attributes(fontSize: fontSize, colorHex: colorHex, shadowBlur: shadowBlur)
        typingAttributes = attributes
        if let textStorage {
            textStorage.setAttributes(attributes, range: NSRange(location: 0, length: textStorage.length))
        }
        insertionPointColor = attributes[.foregroundColor] as? NSColor ?? .textColor
        // An empty box keeps one line of height and room for the cursor.
        minSize = CGSize(width: 2, height: fontSize * TextLayout.lineHeightMultiple)
        sizeToFit()
    }

    override func didChangeText() {
        super.didChangeText()
        sizeToFit()
        onChange(string)
    }

    override func cancelOperation(_ sender: Any?) {
        onFinish()
    }

    override func complete(_ sender: Any?) {
        // Esc is bound to completion in text views. Here it ends editing.
        onFinish()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76), modifiers.contains(.command) {
            onFinish()
            return
        }
        super.keyDown(with: event)
    }
}
