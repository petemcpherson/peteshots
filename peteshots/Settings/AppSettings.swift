//
//  AppSettings.swift
//  peteshots
//

import Foundation

nonisolated enum ImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

/// All UserDefaults keys and default values (spec §9).
nonisolated enum AppSettings {
    enum Key {
        static let destinationPath = "destinationPath"
        static let filenamePrefix = "filenamePrefix"
        static let format = "format"
        static let resizeEnabled = "resizeEnabled"
        static let maxLongSide = "maxLongSide"
        static let compressionEnabled = "compressionEnabled"
        static let jpegQuality = "jpegQuality"
        static let copyToClipboard = "copyToClipboard"
        static let launchAtLogin = "launchAtLogin"
        static let annotationColorHex = "annotationColorHex"
    }

    enum Default {
        static let destinationPath = "~/Downloads"
        static let filenamePrefix = "Screenshot"
        static let format = ImageFormat.png
        static let resizeEnabled = true
        static let maxLongSide = 2000
        static let compressionEnabled = true
        static let jpegQuality = 0.80
        static let copyToClipboard = true
        static let launchAtLogin = true
        static let annotationColorHex = "#FF3B30"
    }

    /// Registers defaults for every key except `launchAtLogin`, which must stay
    /// unset until `LaunchAtLogin.registerOnFirstLaunch()` runs.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.destinationPath: Default.destinationPath,
            Key.filenamePrefix: Default.filenamePrefix,
            Key.format: Default.format.rawValue,
            Key.resizeEnabled: Default.resizeEnabled,
            Key.maxLongSide: Default.maxLongSide,
            Key.compressionEnabled: Default.compressionEnabled,
            Key.jpegQuality: Default.jpegQuality,
            Key.copyToClipboard: Default.copyToClipboard,
            Key.annotationColorHex: Default.annotationColorHex,
        ])
    }

    /// The destination folder with `~` expanded.
    static var destinationURL: URL {
        let path = UserDefaults.standard.string(forKey: Key.destinationPath) ?? Default.destinationPath
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// A snapshot of the export settings, safe to read off the main thread.
nonisolated struct ExportSettings: Equatable, Sendable {
    var destinationURL: URL
    var filenamePrefix: String
    var format: ImageFormat
    var resizeEnabled: Bool
    var maxLongSide: Int
    var compressionEnabled: Bool
    var jpegQuality: Double
    var copyToClipboard: Bool

    static func current(_ defaults: UserDefaults = .standard) -> ExportSettings {
        typealias Key = AppSettings.Key
        typealias Default = AppSettings.Default
        return ExportSettings(
            destinationURL: AppSettings.destinationURL,
            filenamePrefix: defaults.string(forKey: Key.filenamePrefix) ?? Default.filenamePrefix,
            format: defaults.string(forKey: Key.format).flatMap(ImageFormat.init(rawValue:)) ?? Default.format,
            resizeEnabled: defaults.object(forKey: Key.resizeEnabled) as? Bool ?? Default.resizeEnabled,
            maxLongSide: defaults.object(forKey: Key.maxLongSide) as? Int ?? Default.maxLongSide,
            compressionEnabled: defaults.object(forKey: Key.compressionEnabled) as? Bool ?? Default.compressionEnabled,
            jpegQuality: defaults.object(forKey: Key.jpegQuality) as? Double ?? Default.jpegQuality,
            copyToClipboard: defaults.object(forKey: Key.copyToClipboard) as? Bool ?? Default.copyToClipboard
        )
    }
}
