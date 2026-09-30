//
//  ToastView.swift
//  peteshots
//

import SwiftUI

/// What one toast shows (spec §8).
nonisolated struct ToastContent: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case success
        case error
    }

    var lines: [String]
    var style: Style
    /// Clicking the toast reveals this file in Finder.
    var fileURL: URL?

    /// The lines for a finished save. Only the lines that apply are included.
    static func saved(_ result: ExportResult) -> ToastContent {
        var lines = ["✓ Saved \"\(result.fileName)\""]
        if result.didResize {
            lines.append("↘ Resized \(dimensions(result.originalSize)) → \(dimensions(result.finalSize))")
        }
        if result.showCompression {
            lines.append("🗜 \(result.formattedOriginalBytes) 👉 \(result.formattedFinalBytes)")
        }
        if result.usedFallback {
            lines.append("⚠️ Folder not found. Saved to Downloads.")
        }
        return ToastContent(lines: lines, style: .success, fileURL: result.url)
    }

    static func error(_ title: String, _ error: Error) -> ToastContent {
        ToastContent(lines: ["✕ \(title)", error.localizedDescription], style: .error, fileURL: nil)
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }
}

struct ToastView: View {
    let content: ToastContent

    var body: some View {
        HStack(spacing: 0) {
            if content.style == .error {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: 3)
                    .padding(.trailing, 10)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(content.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
    }
}
