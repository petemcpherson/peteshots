//
//  EditorView.swift
//  peteshots
//

import SwiftUI

/// The editor chrome: the toolbar above the canvas (spec §5.2).
struct EditorView: View {
    @Bindable var state: EditorState
    @State private var showsBackgroundPicker = false

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

            Picker(selection: arrowWeightBinding) {
                ForEach(ArrowWeight.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Image(systemName: "lineweight")
            }
            .fixedSize()
            .help("Arrow weight")
            .padding(.leading, 6)

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 6)

            Text("Outline")
                .foregroundStyle(.secondary)
            ColorPicker("", selection: outlineColorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Outline color")
            Picker("Outline width", selection: outlineWidthBinding) {
                ForEach(OutlineWidth.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help("Outline width for arrows and text")

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 6)

            Button {
                showsBackgroundPicker.toggle()
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(state.document.background != nil ? Color.accentColor.opacity(0.25) : .clear)
                    )
                    .foregroundStyle(state.document.background != nil ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.tool == .crop)
            .help("Background")
            .accessibilityLabel("Background")
            .popover(isPresented: $showsBackgroundPicker, arrowEdge: .bottom) {
                BackgroundPicker(state: state)
            }

            if state.tool == .crop {
                Button("Apply Crop", systemImage: "checkmark") { state.applyCrop() }
                    .help("Apply crop (Return). Esc cancels.")
                    .padding(.leading, 6)
            }

            Spacer()

            Button("Cancel") { state.cancel() }
                .disabled(state.isSaving)
                .help("Discard (Esc)")
            Button { state.save() } label: {
                if state.isSaving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text("Save")
                }
            }
                .buttonStyle(.borderedProminent)
                .disabled(state.isSaving)
                .help("Save (⌘S)")
        }
        .padding(.horizontal, 10)
        .frame(height: EditorWindowController.toolbarHeight - 1)
        .focusEffectDisabled()
    }

    private var arrowWeightBinding: Binding<ArrowWeight> {
        Binding(get: { state.arrowWeight }, set: { state.setArrowWeight($0) })
    }

    private var outlineWidthBinding: Binding<OutlineWidth> {
        Binding(get: { state.outline.width }, set: { state.setOutlineWidth($0) })
    }

    private var outlineColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: state.outline.colorHex) },
            set: { color in
                if let hex = color.hexString { state.setOutlineColor(hex) }
            }
        )
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

/// Gradient swatches and the padding slider (spec §5.6b).
private struct BackgroundPicker: View {
    let state: EditorState

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                state.setBackground(nil)
            } label: {
                Text("None")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Text("Gradients")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BackgroundGradient.allCases, id: \.self) { gradient in
                    GradientSwatch(
                        gradient: gradient,
                        isSelected: state.document.background?.gradient == gradient
                    ) {
                        state.setBackground(gradient)
                    }
                }
            }

            Text("Padding")
                .foregroundStyle(.secondary)
            Slider(
                value: paddingBinding,
                in: Background.paddingRange
            ) { isEditing in
                // One undo step per slider drag.
                if isEditing { state.beginLiveChange() } else { state.endLiveChange() }
            }
            .disabled(state.document.background == nil)
        }
        .padding(16)
        .frame(width: 236)
    }

    private var paddingBinding: Binding<CGFloat> {
        Binding(get: { state.backgroundPadding }, set: { state.setBackgroundPadding($0) })
    }
}

private struct GradientSwatch: View {
    let gradient: BackgroundGradient
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: gradient.colorHexes.map(Color.init(hex:)),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(gradient.title)
        .accessibilityLabel(gradient.title)
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
