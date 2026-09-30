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

    /// Runs `body`, then restores the saved annotation color.
    private func keepingSavedColor(_ body: () -> Void) {
        let key = AppSettings.Key.annotationColorHex
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        body()
    }

    @Test func arrowStrokeWidthIsClamped() {
        let (state, _) = makeState()
        // The long side is 40 px, so 0.4% is below the 3 px minimum.
        #expect(state.arrowStrokeWidth == 3)
    }

    @Test func colorChangeRecolorsSelectionAsOneUndoStep() {
        keepingSavedColor {
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
        keepingSavedColor {
            let (state, undoManager) = makeState()
            state.setColor("#123456")
            #expect(state.colorHex == "#123456")
            #expect(!undoManager.canUndo)
        }
    }

    @Test func colorChangeSkipsBlur() {
        keepingSavedColor {
            let (state, undoManager) = makeState()
            let annotation = blur(CGRect(x: 0, y: 0, width: 10, height: 10))
            step(undoManager) { state.place(annotation) }
            state.setColor("#123456")
            #expect(state.document.annotations == [annotation])
            undoManager.undo()
            #expect(state.document.annotations.isEmpty)
        }
    }
}
