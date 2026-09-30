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
        didSet { toolDidChange(from: oldValue) }
    }

    var selectedID: Annotation.ID? {
        didSet { if selectedID != oldValue { colorChange = nil } }
    }
    /// The text annotation in the inline editor. Its string updates live, and
    /// the whole edit becomes one undo step when editing ends (spec §5.6).
    private(set) var editingTextID: Annotation.ID?
    /// The crop rect being adjusted while the crop tool is active (spec §5.7).
    private(set) var cropDraft: CGRect?
    private(set) var colorHex: String

    /// True while the export runs. Save is disabled until it ends.
    private(set) var isSaving = false

    @ObservationIgnored var undoManager: UndoManager?
    /// The capture time, used for the file name (spec §7.4).
    @ObservationIgnored var captureDate = Date()
    @ObservationIgnored var onSaved: (ExportResult) -> Void = { _ in }
    @ObservationIgnored var onSaveFailed: (Error) -> Void = { _ in }
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
    /// The smallest crop, in image px (spec §5.7).
    static let minCropSize = CGSize(width: 8, height: 8)

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

    /// Default font size: 3% of the image's long side, clamped to 14–48 px (spec §5.6).
    var defaultFontSize: CGFloat {
        Geometry.clamp(0.03 * CGFloat(max(baseImage.width, baseImage.height)), 14, 48)
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
        if editingTextID == selectedID {
            // Part of the text edit's undo step.
            updateLive(recolor)
            return
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

    // MARK: - Text editing

    /// Starts editing a text annotation. A new one (not yet in the document)
    /// is added now and kept only if it has text when editing ends.
    func beginTextEditing(_ text: TextAnnotation, isNew: Bool) {
        tool = .select
        beginLiveChange()
        if isNew {
            updateLive { $0.annotations.append(.text(text)) }
        }
        selectedID = text.id
        editingTextID = text.id
    }

    func updateEditingText(_ string: String) {
        guard let editingTextID else { return }
        updateLive { document in
            document.updateAnnotation(withID: editingTextID) { annotation in
                guard case .text(var text) = annotation else { return }
                text.string = string
                annotation = .text(text)
            }
        }
    }

    /// Ends editing. Empty text is removed; otherwise the edit is one undo step.
    func endTextEditing() {
        guard let id = editingTextID else { return }
        editingTextID = nil
        if case .text(let text)? = document.annotation(withID: id),
           text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateLive { $0.removeAnnotation(withID: id) }
        }
        endLiveChange()
    }

    // MARK: - Crop

    func updateCropDraft(_ rect: CGRect) {
        guard cropDraft != nil else { return }
        cropDraft = Geometry.clampRect(Geometry.roundedRect(rect), to: imageBounds)
    }

    /// Applies the crop as one undo step and returns to Select.
    func applyCrop() {
        guard tool == .crop else { return }
        tool = .select
    }

    /// Restores the crop from before crop mode and returns to Select.
    func cancelCrop() {
        guard tool == .crop else { return }
        cropDraft = nil
        tool = .select
    }

    private func toolDidChange(from oldTool: Tool) {
        guard tool != oldTool else { return }
        endTextEditing()
        if tool != .select { selectedID = nil }
        if oldTool == .crop {
            // Leaving crop mode by any route except Esc applies the crop.
            if let draft = cropDraft {
                cropDraft = nil
                commit { $0.cropRect = draft }
            }
        }
        if tool == .crop {
            cropDraft = document.cropRect
        }
    }

    // MARK: - Actions

    /// Exports off the main thread, then copies to the clipboard (spec §6).
    /// A failed write keeps the editor open with Save enabled again.
    func save() {
        guard !isSaving else { return }
        endTextEditing()
        applyCrop()
        isSaving = true

        let base = baseImage
        let document = document
        let captureDate = captureDate
        let settings = ExportSettings.current()
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ExportPipeline.export(base: base, document: document, captureDate: captureDate, settings: settings) }
            }.value
            isSaving = false
            switch result {
            case .success(let export):
                if settings.copyToClipboard {
                    ClipboardWriter.write(fileURL: export.url, data: export.data, format: export.format)
                }
                onSaved(export)
            case .failure(let error):
                onSaveFailed(error)
            }
        }
    }

    func cancel() { onCancel() }

    /// Esc cancels crop mode first, then the whole editor (spec §5.7).
    func escape() {
        if tool == .crop {
            cancelCrop()
        } else {
            cancel()
        }
    }

    /// Handles a key that no text view consumed. Returns false if unhandled.
    func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Esc
            escape()
            return true
        case 36 where tool == .crop, 76 where tool == .crop: // Return, Enter
            applyCrop()
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
