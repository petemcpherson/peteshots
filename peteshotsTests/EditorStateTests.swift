import AppKit
import Testing
@testable import peteshots

@MainActor
struct EditorStateTests {
    private func makeState() -> (EditorState, UndoManager) {
        let context = CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let state = EditorState(baseImage: context.makeImage()!, pointsPerPixel: 0.5)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        state.undoManager = undoManager
        return (state, undoManager)
    }

    private func blur(_ rect: CGRect) -> Annotation {
        .blur(BlurAnnotation(rect: rect))
    }

    /// Commits run outside an event loop, so each one gets an explicit undo group.
    private func step(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    @Test func initialDocumentCoversImage() {
        let (state, _) = makeState()
        #expect(state.document.cropRect == CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(state.document.annotations.isEmpty)
        #expect(state.tool == .select)
    }

    @Test func placeSelectsAndSwitchesToSelect() {
        let (state, undoManager) = makeState()
        state.tool = .blur
        let annotation = blur(CGRect(x: 1, y: 1, width: 10, height: 10))
        step(undoManager) { state.place(annotation) }
        #expect(state.tool == .select)
        #expect(state.selectedID == annotation.id)
    }

    @Test func backgroundIsOneUndoStep() {
        let (state, undoManager) = makeState()
        step(undoManager) { state.setBackground(.sunset) }
        #expect(state.document.background?.gradient == .sunset)
        #expect(state.document.background?.padding == state.backgroundPadding)

        step(undoManager) { state.setBackground(nil) }
        #expect(state.document.background == nil)

        undoManager.undo()
        #expect(state.document.background?.gradient == .sunset)
        undoManager.undo()
        #expect(state.document.background == nil)
    }

    @Test func paddingDragIsOneUndoStep() {
        let (state, undoManager) = makeState()
        let original = state.backgroundPadding
        defer { state.setBackgroundPadding(original) }
        step(undoManager) { state.setBackground(.mint) }
        let before = state.document.background

        step(undoManager) {
            state.beginLiveChange()
            state.setBackgroundPadding(0.1)
            state.setBackgroundPadding(0.15)
            state.endLiveChange()
        }
        #expect(state.document.background?.padding == 0.15)

        undoManager.undo()
        #expect(state.document.background == before)
    }

    @Test func paddingIsClamped() {
        let (state, _) = makeState()
        let original = state.backgroundPadding
        defer { state.setBackgroundPadding(original) }
        state.setBackgroundPadding(5)
        #expect(state.backgroundPadding == Background.paddingRange.upperBound)
    }

    @Test func undoAndRedoRestoreSnapshots() {
        let (state, undoManager) = makeState()
        let annotation = blur(CGRect(x: 1, y: 1, width: 10, height: 10))
        step(undoManager) { state.place(annotation) }
        #expect(state.document.annotations.count == 1)

        undoManager.undo()
        #expect(state.document.annotations.isEmpty)
        #expect(state.selectedID == nil)

        undoManager.redo()
        #expect(state.document.annotations == [annotation])
    }

    @Test func liveDragIsOneUndoStep() {
        let (state, undoManager) = makeState()
        let annotation = blur(CGRect(x: 0, y: 0, width: 10, height: 10))
        step(undoManager) { state.place(annotation) }
        let placed = state.document

        step(undoManager) {
            state.beginLiveChange()
            for _ in 0..<5 {
                state.updateLive { $0.updateAnnotation(withID: annotation.id) { $0 = $0.offsetBy(dx: 1, dy: 0) } }
            }
            state.endLiveChange()
        }
        #expect(state.document.annotations.first == annotation.offsetBy(dx: 5, dy: 0))

        undoManager.undo()
        #expect(state.document == placed)
    }

    @Test func unchangedCommitAddsNoUndoStep() {
        let (state, undoManager) = makeState()
        state.commit { _ in }
        #expect(!undoManager.canUndo)
    }

    @Test func deleteSelectionIsUndoable() {
        let (state, undoManager) = makeState()
        let annotation = blur(CGRect(x: 0, y: 0, width: 10, height: 10))
        step(undoManager) { state.place(annotation) }
        step(undoManager) { state.deleteSelection() }
        #expect(state.document.annotations.isEmpty)
        #expect(state.selectedID == nil)

        undoManager.undo()
        #expect(state.document.annotations == [annotation])
    }

    private func arrow() -> Annotation {
        .arrow(ArrowAnnotation(start: .zero, end: CGPoint(x: 10, y: 10), colorHex: "#FF0000", strokeWidth: 3))
    }

    /// Runs `body`, then restores the saved annotation color and style.
    private func keepingSavedStyle(_ body: () -> Void) {
        let keys = [
            AppSettings.Key.annotationColorHex, AppSettings.Key.arrowWeight,
            AppSettings.Key.outlineColorHex, AppSettings.Key.outlineWidth,
        ]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        body()
    }

    @Test func arrowStrokeWidthIsClamped() {
        let (state, _) = makeState()
        // The long side is 40 px, so 0.8% is below the 4 px minimum.
        #expect(state.baseArrowStrokeWidth == 4)
    }

    @Test func colorChangeRecolorsSelectionAsOneUndoStep() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            let annotation = arrow()
            step(undoManager) { state.place(annotation) }

            // Continuous panel updates coalesce into one step.
            step(undoManager) { state.setColor("#00FF00") }
            // A live update registers nothing, so it gets no undo group.
            state.setColor("#0000FF")
            #expect(state.selectedAnnotation?.colorHex == "#0000FF")
            #expect(state.colorHex == "#0000FF")

            undoManager.undo()
            #expect(state.document.annotations.first?.colorHex == "#FF0000")
            undoManager.redo()
            #expect(state.document.annotations.first?.colorHex == "#0000FF")
            undoManager.undo()
            undoManager.undo()
            #expect(state.document.annotations.isEmpty)
        }
    }

    @Test func colorChangeWithoutSelectionAddsNoUndoStep() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            state.setColor("#123456")
            #expect(state.colorHex == "#123456")
            #expect(!undoManager.canUndo)
        }
    }

    @Test func colorChangeSkipsBlur() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            let annotation = blur(CGRect(x: 0, y: 0, width: 10, height: 10))
            step(undoManager) { state.place(annotation) }
            state.setColor("#123456")
            #expect(state.document.annotations == [annotation])
            undoManager.undo()
            #expect(state.document.annotations.isEmpty)
        }
    }

    @Test func arrowWeightRestylesSelectedArrowAsOneUndoStep() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            state.setArrowWeight(.regular)
            let annotation = arrow()
            step(undoManager) { state.place(annotation) }

            step(undoManager) { state.setArrowWeight(.heavy) }
            #expect(state.arrowStrokeWidth == state.baseArrowStrokeWidth * 2)
            guard case .arrow(let heavy)? = state.selectedAnnotation else { Issue.record("no arrow"); return }
            #expect(heavy.strokeWidth == state.arrowStrokeWidth)

            undoManager.undo()
            #expect(state.document.annotations == [annotation])
        }
    }

    @Test func outlineChangesRestyleSelection() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            state.setOutlineWidth(.off)
            state.setOutlineColor("#FFFFFF")
            let annotation = arrow()
            step(undoManager) { state.place(annotation) }

            step(undoManager) { state.setOutlineWidth(.thick) }
            step(undoManager) { state.setOutlineColor("#000000") }
            // A quick second color change joins the first color step.
            state.setOutlineColor("#111111")
            #expect(state.outline == Outline(colorHex: "#111111", width: .thick))
            guard case .arrow(let outlined)? = state.selectedAnnotation else { Issue.record("no arrow"); return }
            #expect(outlined.outline == state.outline)

            undoManager.undo()
            guard case .arrow(let undone)? = state.selectedAnnotation else { Issue.record("no arrow"); return }
            #expect(undone.outline.width == .thick)
            #expect(undone.outline == Outline(colorHex: "#FFFFFF", width: .thick))
        }
    }

    @Test func outlineChangeSkipsBlur() {
        keepingSavedStyle {
            let (state, undoManager) = makeState()
            let annotation = blur(CGRect(x: 0, y: 0, width: 10, height: 10))
            step(undoManager) { state.place(annotation) }
            state.setOutlineWidth(.thin)
            state.setArrowWeight(.bold)
            #expect(state.document.annotations == [annotation])
            undoManager.undo()
            #expect(state.document.annotations.isEmpty)
        }
    }

    // MARK: - Text

    private func text(_ string: String) -> TextAnnotation {
        TextAnnotation(origin: CGPoint(x: 2, y: 2), string: string, fontSize: 14, colorHex: "#FF0000")
    }

    @Test func defaultFontSizeIsClamped() {
        let (state, _) = makeState()
        #expect(state.defaultFontSize == 18)
    }

    @Test func newTextEditIsOneUndoStep() {
        let (state, undoManager) = makeState()
        state.tool = .text
        let new = text("")
        step(undoManager) {
            state.beginTextEditing(new, isNew: true)
            #expect(state.tool == .select)
            #expect(state.editingTextID == new.id)
            state.updateEditingText("H")
            state.updateEditingText("Hi")
            state.endTextEditing()
        }
        #expect(state.editingTextID == nil)
        #expect(state.selectedID == new.id)
        guard case .text(let placed)? = state.document.annotations.first else {
            Issue.record("No text annotation")
            return
        }
        #expect(placed.string == "Hi")

        undoManager.undo()
        #expect(state.document.annotations.isEmpty)
    }

    @Test func emptyNewTextIsRemovedWithoutUndoStep() {
        let (state, undoManager) = makeState()
        // Nothing registers, so no undo group is needed.
        state.beginTextEditing(text(""), isNew: true)
        state.updateEditingText("  \n ")
        state.endTextEditing()
        #expect(state.document.annotations.isEmpty)
        #expect(!undoManager.canUndo)
    }

    @Test func editingExistingTextRestoresOnUndo() {
        let (state, undoManager) = makeState()
        let original = text("Old")
        step(undoManager) { state.place(.text(original)) }
        step(undoManager) {
            state.beginTextEditing(original, isNew: false)
            state.updateEditingText("New")
            state.endTextEditing()
        }
        #expect(state.document.annotations.first?.id == original.id)
        undoManager.undo()
        #expect(state.document.annotations == [.text(original)])
    }

    @Test func toolChangeEndsTextEditing() {
        let (state, undoManager) = makeState()
        step(undoManager) {
            state.beginTextEditing(text(""), isNew: true)
            state.updateEditingText("Hi")
            state.tool = .arrow
        }
        #expect(state.editingTextID == nil)
        #expect(state.document.annotations.count == 1)
    }

    // MARK: - Crop

    @Test func applyCropIsOneUndoStep() {
        let (state, undoManager) = makeState()
        state.tool = .crop
        #expect(state.cropDraft == state.imageBounds)
        state.updateCropDraft(CGRect(x: 4.4, y: 2.6, width: 20, height: 10))
        #expect(state.cropDraft == CGRect(x: 4, y: 3, width: 20, height: 10))
        step(undoManager) { state.applyCrop() }
        #expect(state.tool == .select)
        #expect(state.cropDraft == nil)
        #expect(state.document.cropRect == CGRect(x: 4, y: 3, width: 20, height: 10))

        undoManager.undo()
        #expect(state.document.cropRect == state.imageBounds)
    }

    @Test func escapeCancelsCropOnly() {
        let (state, undoManager) = makeState()
        var cancelled = false
        state.onCancel = { cancelled = true }
        state.tool = .crop
        state.updateCropDraft(CGRect(x: 0, y: 0, width: 10, height: 10))
        state.escape()
        #expect(!cancelled)
        #expect(state.tool == .select)
        #expect(state.document.cropRect == state.imageBounds)
        #expect(!undoManager.canUndo)
    }

    @Test func cropDraftStaysInImage() {
        let (state, _) = makeState()
        state.tool = .crop
        state.updateCropDraft(CGRect(x: 30, y: 15, width: 20, height: 10))
        #expect(state.cropDraft == CGRect(x: 20, y: 10, width: 20, height: 10))
    }
}
