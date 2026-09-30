//
//  CanvasRepresentable.swift
//  peteshots
//

import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    let state: EditorState

    func makeNSView(context: Context) -> CanvasView {
        CanvasView(state: state)
    }

    func updateNSView(_ nsView: CanvasView, context: Context) {}
}
