//
//  EditorView.swift
//  peteshots
//

import SwiftUI

/// The editor chrome: the toolbar above the canvas (spec §5.2).
struct EditorView: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            CanvasRepresentable(state: state)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases, id: \.self) { tool in
                ToolButton(tool: tool, isActive: state.tool == tool) {
                    state.tool = tool
                }
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 6)

            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Annotation color")

            Spacer()

            Button("Cancel") { state.cancel() }
                .help("Discard (Esc)")
            Button("Save") { state.save() }
                .buttonStyle(.borderedProminent)
                .help("Save (⌘S)")
        }
        .padding(.horizontal, 10)
        .frame(height: EditorWindowController.toolbarHeight - 1)
        .focusEffectDisabled()
    }

    /// The color as a SwiftUI `Color`, stored as sRGB hex (spec §5.3).
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: state.colorHex) },
            set: { color in
                if let hex = color.hexString { state.setColor(hex) }
            }
        )
    }
}

private struct ToolButton: View {
    let tool: Tool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.accentColor.opacity(0.25) : .clear)
                )
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(tool.title) (\(tool.key.uppercased()))")
        .accessibilityLabel(tool.title)
    }
}
