//
//  EditorState.swift
//  peteshots
//

import AppKit
import Observation

enum Tool: CaseIterable {
    case select, arrow, blur, text, crop

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .blur: "Blur"
        case .text: "Text"
        case .crop: "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .blur: "drop.halffull"
        case .text: "textformat"
        case .crop: "crop"
        }
    }

    /// Single-key shortcut (spec §5.2).
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .blur: "b"
        case .text: "t"
        case .crop: "c"
        }
    }
}

/// State of one editor window: the image, the document, the tool, the
/// selection, and snapshot undo (spec §5.9).
@Observable
final class EditorState {
    let baseImage: CGImage
    /// View points per image pixel at 1:1 on the capture screen (1 / backing scale).
    let pointsPerPixel: CGFloat

    private(set) var document: EditorDocument {
        didSet {
            if let selectedID, document.annotation(withID: selectedID) == nil {
                self.selectedID = nil
            }
        }
    }

    var tool: Tool = .select {
        didSet { if tool != .select { selectedID = nil } }
    }

    var selectedID: Annotation.ID? {
        didSet { if selectedID != oldValue { colorChange = nil } }
    }
    var editingTextID: Annotation.ID?
    private(set) var colorHex: String

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored var onSave: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}

    /// The document when the current live drag started.
    @ObservationIgnored private var liveChangeStart: EditorDocument?
    /// The annotation whose color is changing and the time of the last change.
    /// Continuous color panel updates coalesce into one undo step.
    @ObservationIgnored private var colorChange: (id: Annotation.ID, time: Date)?

    /// A pause longer than this starts a new color undo step.
    static let colorCoalesceInterval: TimeInterval = 1
    /// The smallest blur region, in image px (spec §5.5).
    static let minBlurSize = CGSize(width: 8, height: 8)

    init(baseImage: CGImage, pointsPerPixel: CGFloat) {
        self.baseImage = baseImage
        self.pointsPerPixel = pointsPerPixel
        self.document = EditorDocument(imageSize: CGSize(width: baseImage.width, height: baseImage.height))
        self.colorHex = UserDefaults.standard.string(forKey: AppSettings.Key.annotationColorHex)
            ?? AppSettings.Default.annotationColorHex
    }

    var imageBounds: CGRect {
        CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
    }

    var selectedAnnotation: Annotation? {
        selectedID.flatMap { document.annotation(withID: $0) }
    }

    /// Arrow stroke width: 0.4% of the image's long side, clamped to 3–10 px (spec §5.4).
    var arrowStrokeWidth: CGFloat {
        Geometry.clamp(0.004 * CGFloat(max(baseImage.width, baseImage.height)), 3, 10)
    }

    // MARK: - Changes

    /// Applies a change as one undo step.
    func commit(_ change: (inout EditorDocument) -> Void) {
        var newDocument = document
        change(&newDocument)
        guard newDocument != document else { return }
        colorChange = nil
        replaceDocument(with: newDocument)
    }

    /// Saves the document before a drag. Call `updateLive` during the drag
    /// and `endLiveChange` at mouse-up.
    func beginLiveChange() {
        liveChangeStart = document
    }

    /// Changes the document without an undo step.
    func updateLive(_ change: (inout EditorDocument) -> Void) {
        change(&document)
    }

    /// Registers the whole drag as one undo step.
    func endLiveChange() {
        guard let start = liveChangeStart else { return }
        liveChangeStart = nil
        guard start != document else { return }
        colorChange = nil
        registerUndo(restoring: start)
    }

    /// Adds a new annotation, then selects it with the Select tool (spec §5.2).
    func place(_ annotation: Annotation) {
        commit { $0.annotations.append(annotation) }
        tool = .select
        selectedID = annotation.id
    }

    func deleteSelection() {
        guard let selectedID else { return }
        commit { $0.removeAnnotation(withID: selectedID) }
        self.selectedID = nil
    }

    /// Sets the annotation color and saves it as the default. A selected arrow
    /// or text annotation takes the new color (spec §5.3).
    func setColor(_ hex: String) {
        guard hex != colorHex else { return }
        colorHex = hex
        UserDefaults.standard.set(hex, forKey: AppSettings.Key.annotationColorHex)

        guard let selectedID, selectedAnnotation?.colorHex != nil else { return }
        let recolor: (inout EditorDocument) -> Void = { document in
            document.updateAnnotation(withID: selectedID) { $0 = $0.withColor(hex) }
        }
        let now = Date()
        if let colorChange, colorChange.id == selectedID,
           now.timeIntervalSince(colorChange.time) < Self.colorCoalesceInterval {
            // Same color session: the undo step registered by the first change
            // restores the original color, and redo returns the latest one.
            updateLive(recolor)
        } else {
            commit(recolor)
        }
        colorChange = (selectedID, now)
    }

    /// Registers an undo step to `oldDocument`, then replaces the document.
    private func replaceDocument(with newDocument: EditorDocument) {
        registerUndo(restoring: document)
        document = newDocument
    }

    /// Undo restores `oldDocument`. Redo goes back to the document as it is when
    /// undo runs, so live updates after the registration (color changes) are kept.
    private func registerUndo(restoring oldDocument: EditorDocument) {
        undoManager?.registerUndo(withTarget: self) { state in
            state.colorChange = nil
            state.replaceDocument(with: oldDocument)
        }
    }

    // MARK: - Actions

    func save() { onSave() }
    func cancel() { onCancel() }

    /// Handles a key that no text view consumed. Returns false if unhandled.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Esc
            cancel()
            return true
        case 51, 117: // Delete, Forward Delete
            deleteSelection()
            return true
        default:
            break
        }
        guard modifiers.isDisjoint(with: [.command, .control, .option]),
              editingTextID == nil,
              let key = event.charactersIgnoringModifiers?.lowercased().first,
              let tool = Tool.allCases.first(where: { $0.key == key })
        else { return false }
        self.tool = tool
        return true
    }
}
