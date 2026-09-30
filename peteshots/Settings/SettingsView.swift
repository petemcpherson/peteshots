//
//  SettingsView.swift
//  peteshots
//

import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// The preferences form (spec §9). Every change applies to the next export.
struct SettingsView: View {
    typealias Key = AppSettings.Key
    typealias Default = AppSettings.Default

    static let maxLongSideRange = 200...10000

    @AppStorage(Key.destinationPath) private var destinationPath = Default.destinationPath
    @AppStorage(Key.filenamePrefix) private var filenamePrefix = Default.filenamePrefix
    @AppStorage(Key.format) private var format = Default.format.rawValue
    @AppStorage(Key.resizeEnabled) private var resizeEnabled = Default.resizeEnabled
    @AppStorage(Key.maxLongSide) private var maxLongSide = Default.maxLongSide
    @AppStorage(Key.compressionEnabled) private var compressionEnabled = Default.compressionEnabled
    @AppStorage(Key.jpegQuality) private var jpegQuality = Default.jpegQuality
    @AppStorage(Key.copyToClipboard) private var copyToClipboard = Default.copyToClipboard
    @AppStorage(Key.launchAtLogin) private var launchAtLogin = Default.launchAtLogin

    @State private var maxLongSideDraft = Default.maxLongSide
    @State private var loginStatus: SMAppService.Status = .notRegistered

    private var imageFormat: ImageFormat { ImageFormat(rawValue: format) ?? Default.format }

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture hotkey:", name: .takeScreenshot)
            }

            Section {
                LabeledContent("Save to:") {
                    HStack {
                        Text((AppSettings.destinationURL.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseDestination)
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppSettings.destinationURL])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Filename prefix:", text: $filenamePrefix)
                        .onChange(of: filenamePrefix) { _, newValue in
                            let stripped = newValue.filter { $0 != "/" && $0 != ":" }
                            if stripped != newValue { filenamePrefix = stripped }
                        }
                    Text("\"\(FileNamer.baseName(prefix: filenamePrefix, date: .now)).\(imageFormat.fileExtension)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Section {
                Picker("Format:", selection: $format) {
                    Text("PNG").tag(ImageFormat.png.rawValue)
                    Text("JPEG").tag(ImageFormat.jpeg.rawValue)
                }
                .pickerStyle(.segmented)

                Toggle("Resize large images", isOn: $resizeEnabled)
                TextField("Max long side (px):", value: $maxLongSideDraft, format: .number.grouping(.never))
                    .disabled(!resizeEnabled)
                    .onSubmit(commitMaxLongSide)
                    .onChange(of: maxLongSideDraft) { _, _ in commitMaxLongSide() }

                Toggle("Compression", isOn: $compressionEnabled)
                if imageFormat == .jpeg && compressionEnabled {
                    LabeledContent("JPEG quality:") {
                        HStack {
                            Slider(value: $jpegQuality, in: 0.60...0.95, step: 0.05)
                            Text("\(Int((jpegQuality * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            Section {
                Toggle("Copy to clipboard on save", isOn: $copyToClipboard)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            LaunchAtLogin.setEnabled(enabled)
                            loginStatus = LaunchAtLogin.status
                        }
                    HStack {
                        Text(LaunchAtLogin.describe(loginStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if loginStatus == .requiresApproval {
                            Button("Open Login Items…", action: LaunchAtLogin.openSystemSettings)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    /// Reads the real login item status, and the stored max long side.
    private func refresh() {
        loginStatus = LaunchAtLogin.status
        let enabled = LaunchAtLogin.isEnabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
        maxLongSideDraft = maxLongSide
    }

    private func commitMaxLongSide() {
        let clamped = min(max(maxLongSideDraft, Self.maxLongSideRange.lowerBound), Self.maxLongSideRange.upperBound)
        maxLongSide = clamped
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.destinationURL
        panel.prompt = "Choose"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = (url.path as NSString).abbreviatingWithTildeInPath
    }
}
