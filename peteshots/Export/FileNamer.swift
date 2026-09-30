//
//  FileNamer.swift
//  peteshots
//

import Foundation

/// File names and the destination folder for saved screenshots (spec §7.4).
nonisolated enum FileNamer {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd-yy HH.mm"
        return formatter
    }()

    /// The prefix with `/` and `:` removed and whitespace trimmed. Empty
    /// becomes `Screenshot`.
    static func cleanPrefix(_ prefix: String) -> String {
        let cleaned = prefix
            .filter { $0 != "/" && $0 != ":" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? AppSettings.Default.filenamePrefix : cleaned
    }

    /// `{prefix} - {MM-dd-yy HH.mm}`, with no extension.
    static func baseName(prefix: String, date: Date) -> String {
        "\(cleanPrefix(prefix)) - \(dateFormatter.string(from: date))"
    }

    /// The first free URL in `folder`: `{name}.{ext}`, then `{name} (2).{ext}`, and so on.
    static func availableURL(in folder: URL, baseName: String, fileExtension: String, fileManager: FileManager = .default) -> URL {
        var candidate = folder.appendingPathComponent("\(baseName).\(fileExtension)", isDirectory: false)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) (\(index)).\(fileExtension)", isDirectory: false)
            index += 1
        }
        return candidate
    }

    /// `folder` if it is an existing directory. Else `~/Downloads`, with
    /// `usedFallback` set.
    static func resolveDestination(_ folder: URL, fileManager: FileManager = .default) -> (url: URL, usedFallback: Bool) {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return (folder, false)
        }
        return (downloadsURL(fileManager: fileManager), true)
    }

    static func downloadsURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Downloads" as NSString).expandingTildeInPath, isDirectory: true)
    }
}
