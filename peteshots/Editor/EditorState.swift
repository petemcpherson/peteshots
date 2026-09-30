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

    var selectedID: Annotation.ID?
    var editingTextID: Annotation.ID?
    var colorHex: String

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored var onSave: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}

    /// The document when the current live drag started.
    @ObservationIgnored private var liveChangeStart: EditorDocument?

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

    // MARK: - Changes

    /// Applies a change as one undo step.
    func commit(_ change: (inout EditorDocument) -> Void) {
        var newDocument = document
        change(&newDocument)
        guard newDocument != document else { return }
        replaceDocument(with: newDocument, undoTo: document)
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
        registerUndo(restoring: start, redoTo: document)
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

    private func replaceDocument(with newDocument: EditorDocument, undoTo oldDocument: EditorDocument) {
        registerUndo(restoring: oldDocument, redoTo: newDocument)
        document = newDocument
    }

    private func registerUndo(restoring oldDocument: EditorDocument, redoTo newDocument: EditorDocument) {
        undoManager?.registerUndo(withTarget: self) { state in
            state.replaceDocument(with: oldDocument, undoTo: newDocument)
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
