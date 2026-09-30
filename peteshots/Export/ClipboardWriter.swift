//
//  ClipboardWriter.swift
//  peteshots
//

import AppKit

/// Puts a saved screenshot on the pasteboard (spec §7.5). Main thread only.
enum ClipboardWriter {
    /// One pasteboard item with the file URL and the image data: apps paste
    /// the image, and Finder pastes the file.
    static func write(fileURL: URL, data: Data, format: ImageFormat) {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setData(data, forType: format == .png ? .png : NSPasteboard.PasteboardType("public.jpeg"))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
