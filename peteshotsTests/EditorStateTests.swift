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
}
