# Peteshots — Implementation Plan

Source: `context/spec.md` (final). This plan breaks the spec into 8 phases. Each phase ends in a buildable, runnable app. Section references (§) point to the spec.

## Progress

- [x] Phase 1 — Project setup and app shell
- [ ] Phase 2 — Hotkey, permission, selection overlay, and capture
- [ ] Phase 3 — Editor foundation (window, document model, canvas, toolbar, undo)
- [ ] Phase 4 — Arrow tool, blur tool, and color picker
- [ ] Phase 5 — Text tool and crop tool
- [ ] Phase 6 — Export pipeline (flatten, resize, encode, write, clipboard)
- [ ] Phase 7 — Toast notification and full Settings window
- [ ] Phase 8 — Edge cases, polish, and acceptance testing

---

## Ground Rules

- **Language mode:** Swift 6, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Mark pure value types and export code `nonisolated` (or `Sendable`) where they run off the main thread.
- **File membership:** the project uses Xcode file-system synchronized groups. New `.swift` files in `peteshots/` join the target automatically. No `project.pbxproj` edits are needed for source files.
- **Coordinates:** all annotation geometry is stored in **image pixel space, top-left origin**. Only the canvas view converts to and from view points.
- **One drawing path:** the editor canvas and the export use the same drawing functions (`AnnotationDrawing`). This is how WYSIWYG (§7.1) is guaranteed.
- **No network code.** Do not import `Network`, `URLSession`, or any analytics library.
- **Manual items for Pete** go in `context/user-todo.md` as short, step-by-step instructions.

### Proposed file layout

```
peteshots/
  App/
    PeteshotsApp.swift          // @main, MenuBarExtra + Settings scenes
    AppDelegate.swift           // NSApplicationDelegate adaptor, startup
    MenuContent.swift           // menu bar items
  Settings/
    AppSettings.swift           // keys, defaults, @AppStorage helpers
    SettingsView.swift          // Settings form (§9)
    LaunchAtLogin.swift         // SMAppService wrapper
  Capture/
    HotkeyService.swift
    CaptureCoordinator.swift
    PermissionService.swift
    PermissionWindow.swift
    SelectionOverlay.swift      // overlay controller + NSPanel per screen
    SelectionView.swift         // NSView: dim, drag, size label
    ScreenCapturer.swift        // SCScreenshotManager wrapper
    CoordinateSpace.swift       // Cocoa <-> CG display space
  Editor/
    EditorWindowController.swift
    EditorView.swift            // SwiftUI chrome (toolbar)
    EditorState.swift           // @Observable: document, tool, selection, undo
    CanvasView.swift            // NSView: draws image + annotations, handles mouse
    CanvasRepresentable.swift   // NSViewRepresentable bridge
    Tools/                      // per-tool mouse handling
    TextEditingOverlay.swift    // inline NSTextView for the text tool
  Model/
    EditorDocument.swift        // EditorDocument, Annotation, ArrowAnnotation, ...
    Geometry.swift              // hit-testing, handles, clamping helpers
  Rendering/
    AnnotationDrawing.swift     // shared CGContext drawing (arrow, text, blur)
    BlurRenderer.swift          // CIGaussianBlur + CIContext cache
    Renderer.swift              // flatten to CGImage
  Export/
    ExportPipeline.swift
    ImageEncoder.swift          // ImageIO PNG/JPEG
    ImageResizer.swift          // CILanczosScaleTransform
    FileNamer.swift             // filename + collision suffix
    ClipboardWriter.swift
  Toast/
    ToastPanel.swift
    ToastView.swift
  Util/
    Color+Hex.swift
```

---

## Phase 1 — Project setup and app shell [COMPLETED]

**Goal:** a menu bar–only app with the correct build settings, the KeyboardShortcuts dependency, and a stub Settings window.

### 1.1 Build settings (`peteshots.xcodeproj/project.pbxproj`, app target, Debug + Release)
- Set `ENABLE_APP_SANDBOX = NO`.
- Remove `ENABLE_USER_SELECTED_FILES = readonly`.
- Keep `ENABLE_HARDENED_RUNTIME = YES`.
- Set `SWIFT_VERSION = 6.0`. Keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- Add `INFOPLIST_KEY_LSUIElement = YES`.
- Confirm `PRODUCT_BUNDLE_IDENTIFIER = com.peteshots.peteshots` and `MACOSX_DEPLOYMENT_TARGET = 26.2`.
- Apply the same `SWIFT_VERSION` to the test targets so they compile against the app module.

### 1.2 Template cleanup
- Delete `Item.swift` and `ContentView.swift`.
- Remove `ModelContainer`, SwiftData imports, and the `WindowGroup` from `peteshotsApp.swift`.
- Remove SwiftData references from `peteshotsTests` and `peteshotsUITests`. Leave the test files as empty shells.

### 1.3 Add KeyboardShortcuts (SPM)
- Add `https://github.com/sindresorhus/KeyboardShortcuts` (up to next major from the latest 2.x) to the app target.
- Preferred: edit `project.pbxproj` (add `XCRemoteSwiftPackageReference`, `XCSwiftPackageProductDependency`, and the framework build phase entry), then run `xcodebuild -resolvePackageDependencies`.
- Fallback: if the pbxproj edit fails to resolve, add a `user-todo.md` item: *File → Add Package Dependencies… → paste URL → Add to target peteshots*.
- Use context7 to confirm the current KeyboardShortcuts API (`Name`, `onKeyDown(for:)`, `Recorder`) before writing Phase 2 code.

### 1.4 App shell
- `PeteshotsApp.swift`: `@main` with `@NSApplicationDelegateAdaptor(AppDelegate.self)`.
  - `MenuBarExtra("Peteshots", systemImage: "camera.viewfinder")` with `MenuContent`.
  - `Settings { SettingsView() }`.
- `MenuContent.swift`: items **Take Screenshot** (stub action for now), **Open Destination Folder**, **Settings…** (`SettingsLink`, Cmd-,), divider, **Quit Peteshots** (`NSApp.terminate`).
- `AppSettings.swift`: one place for all `UserDefaults` keys and defaults (§9):
  - `destinationPath` (`~/Downloads`), `filenamePrefix` (`Screenshot`), `format` (`png`), `resizeEnabled` (`true`), `maxLongSide` (`2000`), `compressionEnabled` (`true`), `jpegQuality` (`0.80`), `copyToClipboard` (`true`), `launchAtLogin` (`true`), `annotationColorHex` (`#FF3B30`).
  - A `nonisolated` snapshot struct (`ExportSettings`) that the export pipeline can read off the main thread.
- `SettingsView.swift`: placeholder form. The full form comes in Phase 7.
- "Open Destination Folder": `NSWorkspace.shared.open(URL(fileURLWithPath: destinationPath))`.

### 1.5 Manual items (`context/user-todo.md`)
- Select the signing team (spec "Manual Setup" step 1).

**Done when:** the app builds under Swift 6 with no warnings from our code. Launch shows only a menu bar icon with no Dock icon (acceptance #1). The menu items work (Take Screenshot is a no-op).

---

## Phase 2 — Hotkey, permission, selection overlay, and capture

**Goal:** Cmd-Shift-A shows the overlay on all displays. Drag and release captures the region into an in-memory `CGImage` (§4).

### 2.1 HotkeyService
- `extension KeyboardShortcuts.Name { static let takeScreenshot = Self("takeScreenshot", initial: .init(.a, modifiers: [.command, .shift])) }`.
- Register `KeyboardShortcuts.onKeyDown(for: .takeScreenshot)` at app launch (from `AppDelegate.applicationDidFinishLaunching`). It calls `CaptureCoordinator.shared.start()`.
- The menu item "Take Screenshot" calls the same method and shows the current shortcut (`.keyboardShortcut(for: .takeScreenshot)` or a formatted label).

### 2.2 CaptureCoordinator (state machine)
- States: `idle`, `selecting`, `capturing`, `editing(EditorWindowController)`.
- `start()`:
  - `selecting` or `capturing`: ignore.
  - `editing`: bring the editor to the front (`NSApp.activate()`, `makeKeyAndOrderFront`).
  - `idle`: check permission, then show the overlay.
- Owns the capture timestamp (`Date()` at mouse-up), the capture screen, and the capture rect. Phase 3 uses them for the editor; Phase 6 uses the timestamp for the filename.

### 2.3 PermissionService + PermissionWindow (§4.2)
- `CGPreflightScreenCaptureAccess()`. If false: call `CGRequestScreenCaptureAccess()`, then show a small window with an explanation and **Open System Settings**.
- Deep link: `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- Do not show the overlay without permission (§11).

### 2.4 SelectionOverlay (§4.3)
- One `NSPanel` per `NSScreen.screens`: `styleMask: [.borderless, .nonactivatingPanel]`, `level = .screenSaver`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `ignoresMouseEvents = false`.
- Panels must be able to become key to receive Esc. Subclass `NSPanel` and override `canBecomeKey = true`. Activate the app when the overlay opens.
- `SelectionView` (NSView, one per panel), with the drag held in **global Cocoa coordinates** so one selection can cross displays. Each view draws the part of the global rect that falls on its screen.
  - Idle: fill 20% black.
  - Dragging: fill 20% black, clear the selection rect, stroke it with 1 pt white.
  - Size label near the cursor: `W × H` in real pixels (`rect.size × screen.backingScaleFactor`). Use `NSAttributedString` on a small dark rounded background.
  - Shift: force a square (use the smaller of |dx| and |dy|, keeping the drag direction).
  - Cursor: `NSCursor.crosshair` (set with `addCursorRect` or `resetCursorRects`, and `push()` on show).
- Cancel: Esc (`keyDown`, keyCode 53 / `cancelOperation`) or `rightMouseDown`. Tear down all panels and return to `idle`.
- Mouse-up: if the rect is smaller than 4×4 pt, cancel. Else pass the rect to the coordinator.

### 2.5 CoordinateSpace
- Convert Cocoa global (bottom-left origin, primary screen) to CG display space (top-left origin): `cgY = primaryScreen.frame.maxY - cocoaRect.maxY`. The primary screen is `NSScreen.screens[0]`.
- Unit test this function with sample rects (Phase 8 adds the tests file; write the function testable now).

### 2.6 ScreenCapturer (§4.4)
- `orderOut` all overlay panels.
- Wait one frame. Use `try await Task.sleep(for: .milliseconds(20))` or a `CATransaction` flush + display-link tick. Pick the simplest option that reliably keeps the overlay out of the image.
- `let image = try await SCScreenshotManager.captureImage(in: cgRect)`.
- Keep the result in memory. Write nothing to disk.
- On error: log it, return to `idle`. (A real error toast arrives in Phase 7.)

**Temporary check:** until Phase 3, show the captured image in a plain `NSWindow` with an `NSImageView` to confirm the region and resolution.

**Done when:** acceptance #2 (overlay on all displays in about 150 ms) and the capture half of #3 (exact region, native resolution) hold. Esc, right-click, and tiny clicks cancel. A second hotkey press during the overlay does nothing.

---

## Phase 3 — Editor foundation

**Goal:** the captured image opens in a correctly sized editor with a toolbar, the Select tool, the undo system, and Save/Cancel wiring. The tools come in Phases 4–5.

### 3.1 Model (`Model/EditorDocument.swift`)
```swift
nonisolated struct EditorDocument: Equatable, Sendable {
    var annotations: [Annotation]
    var cropRect: CGRect          // image px, top-left origin
}

nonisolated enum Annotation: Equatable, Sendable, Identifiable {
    case arrow(ArrowAnnotation)   // id, start, end, colorHex, strokeWidth
    case blur(BlurAnnotation)     // id, rect
    case text(TextAnnotation)     // id, origin, string, fontSize, colorHex
}
```
- Store color as a hex string (or RGBA components) so the model stays `Sendable`.
- `Geometry.swift`: point-to-segment distance, rect handle positions (8 handles), handle hit-testing, rect normalization, clamping.

### 3.2 EditorState (`@Observable`, main actor)
- `baseImage: CGImage`, `document: EditorDocument`, `tool: Tool` (`select`, `arrow`, `blur`, `text`, `crop`), `selectedID: Annotation.ID?`, `editingTextID`, `colorHex`.
- `commit(_ change: (inout EditorDocument) -> Void)`: registers the old document with the `UndoManager`, then applies the change (§5.9). Undo restores the snapshot and registers the redo with the same method.
- `updateLive(_:)`: changes the document without an undo step, for intermediate drags. On drag start, save the pre-drag document. On drag end, register that snapshot as the undo step.
- After each annotation is placed, set `tool = .select` and select the new annotation (§5.2).
- `Delete/Backspace` removes the selected annotation (committed).

### 3.3 EditorWindowController (§5.1)
- Standard titled, closable `NSWindow` (not a SwiftUI `WindowGroup`). `NSHostingView(rootView: EditorView(state:))` as the content view.
- Size: image size in points = `image.width / scale`, where `scale = image.width / captureRect.width` (§11). Clamp to 85% of the capture screen's `visibleFrame`, and scale down to fit. Set a minimum size (for example 480×240 content) so the toolbar fits. Center on the capture screen.
- `NSApp.activate()`, then `makeKeyAndOrderFront`.
- Window delegate: `windowWillClose` discards the capture and returns the coordinator to `idle`. `windowShouldClose` returns `true` with no prompt (§2 decision 2).
- The window's `undoManager` is the one `EditorState` uses. Returning a dedicated `UndoManager` from `windowWillReturnUndoManager` keeps history scoped to this window.

### 3.4 EditorView (SwiftUI chrome, §5.2)
- Top bar: `[Select] [Arrow] [Blur] [Text] [Crop] | [color swatch] … [Cancel] [Save]`. SF Symbols (`cursorarrow`, `arrow.up.right`, `drop.halffull` or `aqi.medium`, `textformat`, `crop`).
- Below the bar: `CanvasRepresentable`, with a neutral background and the image centered.
- Keyboard: Cmd-S (Save), Esc (Cancel, unless a text edit or a crop is active), Cmd-Z / Cmd-Shift-Z (through the standard Edit menu responder chain, or explicit `.keyboardShortcut`). Single-key tool shortcuts `V A B T C` only when no text box is being edited. Handle these in `CanvasView.keyDown` or with `.onKeyPress`, whichever is reliable with the canvas as first responder.
- Save: for now, close the window (Phase 6 connects the export pipeline).

### 3.5 CanvasView (NSView, flipped)
- `isFlipped = true`, so view coordinates match the top-left image space.
- Transform: `viewToImage` / `imageToView` using `fitScale` and the centered image offset. When a crop is applied (and the crop tool is not active), the visible area is `cropRect`, fitted to the view.
- `draw(_:)`: draw the base image, then the annotations through `AnnotationDrawing` (Phase 4). Apply the image transform to the `CGContext` once, so drawing code works in image pixels.
- Handles draw in **view space** at a fixed size (about 8 pt) so they stay usable at any zoom.
- Select tool: hit-test top-down (text and arrows before blurs, newest first). Click an empty area to deselect. Drag to move the selected annotation (live update, one undo step at mouse-up).
- Redraw on state change (observe `EditorState` and call `needsDisplay = true`).

### 3.6 Coordinator connection
- Replace the Phase 2 temporary image window with `EditorWindowController`. The coordinator holds it in the `editing` state.

**Done when:** a capture opens the editor at the correct size and position. Cancel, Esc, and the close button discard with no prompt (acceptance #8, apart from the save part). The hotkey during the editor brings it to the front. Tool buttons and keys switch the tool.

---

## Phase 4 — Arrow tool, blur tool, and color picker

**Goal:** fully working arrows and blurs, drawn with the shared drawing code, and a persistent color.

### 4.1 Shared drawing (`Rendering/AnnotationDrawing.swift`)
- `nonisolated` static functions that take a `CGContext` in image pixel space:
  - `drawArrow(_:in:)`: line with round caps plus a filled triangle head at the end. Head length about 4× stroke width, head width about 3.5× stroke width. Shorten the line so it ends at the head base.
  - `drawBlur(_:base:in:)`: calls `BlurRenderer`.
  - `drawText(_:in:)`: added in Phase 5.
- Draw order: all blurs first (creation order), then arrows and text in creation order (§5.8).

### 4.2 Arrow tool (§5.4)
- Stroke width: `clamp(0.004 × longSide, 3, 10)` px, where `longSide` is the long side of the base image. Store it on the annotation at creation.
- Drag start to end creates the arrow. A drag shorter than a few px is ignored.
- Selected: two round handles at `start` and `end`. Dragging a handle moves only that end. Dragging the body moves both.
- Hit-test: distance to the segment ≤ 8 pt (convert 8 pt to image px with the current fit scale).

### 4.3 Blur tool (§5.5)
- `BlurRenderer`: one shared `CIContext` (created once). Radius = `clamp(min(w, h) × 0.25, 12, 40)` px.
  - `CIImage(cgImage: base).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: rect)`. Convert the top-left `rect` to Core Image's bottom-left space before the crop.
  - Render with `ciContext.createCGImage(_:from:)`, then draw that `CGImage` into the rect.
  - Cache the result by `(rect, radius)`, so a redraw with no change does not blur again. During a move or resize, re-render each frame. If this is slow on large images, blur a cropped padded region (`rect.insetBy(-3 × radius)`) instead of the full image.
- Blur always samples `baseImage`, never other annotations.
- Selected: 8 resize handles plus a move by dragging inside. Enforce a minimum size (for example 8×8 px).

### 4.4 Color picker (§5.3)
- `ColorPicker("", selection:, supportsOpacity: false)` in the toolbar, bound to `EditorState.colorHex` through a `Color`/hex binding (`Util/Color+Hex.swift`, convert through `NSColor` in sRGB).
- Persist with `@AppStorage("annotationColorHex")`. Default `#FF3B30`.
- When the color changes and an arrow or text annotation is selected, apply the color to it as a committed change. Coalesce the continuous `NSColorPanel` updates into one undo step: commit on the first change, then use live updates until the selection or the panel changes.

**Done when:** the arrow and blur parts of acceptance #4 and all of acceptance #5 work. Undo/redo covers add, move, resize, delete, and color change.

---

## Phase 5 — Text tool and crop tool

### 5.1 Text model and drawing (§5.6)
- `TextAnnotation`: `origin` (top-left, image px), `string`, `fontSize` (px), `colorHex`.
- Attributes (one shared function, used by the editor and the export): `NSFont.systemFont(ofSize: fontSize, weight: .semibold)`, the color, `NSShadow` (`shadowBlurRadius = 1`, `shadowOffset = .zero`, color black 50%), and a paragraph style with a fixed `lineHeightMultiple` (for example 1.0).
- Size: measure with `NSAttributedString.boundingRect(with:options: [.usesLineFragmentOrigin])` and no width limit. Lines only break at Return.
- `AnnotationDrawing.drawText`: `NSGraphicsContext(cgContext:flipped: true)`, then `attributedString.draw(in: rect)`. Scale the shadow blur with the image transform, so the export matches the view.
- Default font size: `clamp(0.03 × longSide, 14, 48)` px.

### 5.2 Text editing
- `TextEditingOverlay`: an `NSTextView` added as a subview of `CanvasView`, positioned and scaled over the annotation (font size in view points = `fontSize × fitScale`). Transparent background, same color, same shadow.
- Click with the text tool: create an empty text annotation (not yet committed), start editing right away with the cursor visible.
- Double-click a text box (with any tool, or with Select): start editing it.
- End editing: click outside, Esc, or Cmd-Return. Return inserts a new line.
- On end: if the string is empty (after trimming whitespace), remove the annotation. Else commit the new text as one undo step. Esc here ends editing only (§5.6).
- While editing: the tool shortcut keys and Delete go to the text view, not the canvas.

### 5.3 Text move and resize
- Selected and not editing: drag the body to move.
- Corner handles resize uniformly: keep the opposite corner fixed. New `fontSize = newBoxHeight / lineCount / lineHeightMultiple` (§5.6). The width follows from the new font size. Clamp to a minimum font size (for example 6 px).

### 5.4 Crop tool (§5.7)
- Selecting Crop: show the **full** image with the current `cropRect` (initially the full image), the outside area dimmed (50% black), and 8 handles.
- Drag handles to resize, and drag inside to move. Clamp to the image bounds. The minimum is 8×8 px.
- **Return** or the toolbar ✓ (shown only in crop mode) applies the crop: commit `cropRect` as one undo step, then switch to Select. **Esc** restores the crop rect from before crop mode and switches to Select.
- When not in crop mode, the canvas fits and shows only `cropRect`. Annotations outside it are clipped (`context.clip(to: cropRect)`).
- Consider whether the editor window should resize after a crop. Default: keep the window size and refit the cropped area inside it (simpler, no window jumps).

**Done when:** all of acceptance #4 and #9 (including crop undo) work.

---

## Phase 6 — Export pipeline

**Goal:** Cmd-S writes the final file with the correct name, size, format, and compression (§6, §7). The pipeline runs off the main thread.

### 6.1 Renderer (flatten, §7.1)
- `nonisolated func flatten(base: CGImage, document: EditorDocument) -> CGImage`.
- Context: size = `cropRect` size in integer px, 8 bits per component, sRGB, `CGImageAlphaInfo.noneSkipLast`.
- Translate by `-cropRect.origin`, draw the base image, then call the same `AnnotationDrawing` functions as the canvas (blurs, then arrows and text).
- Flip handling: create the context, then apply `translateBy(0, height)` + `scaleBy(1, -1)` so drawing code uses top-left image coordinates, the same as the flipped canvas. Draw the base `CGImage` with a local flip, so it is not upside down.

### 6.2 Resize (§7.2)
- If `resizeEnabled` and `max(w, h) > maxLongSide`: `scale = maxLongSide / max(w, h)`. Use `CILanczosScaleTransform` (`scale`, `aspectRatio = 1`). Render to exact integer dimensions: `round(w × scale)` × `round(h × scale)`. Never scale up.
- Return `originalSize` and `finalSize`.

### 6.3 Encode (§7.3, `ImageEncoder`)
- `CGImageDestinationCreateWithData` + `CGImageDestinationAddImage` + `CGImageDestinationFinalize`.
- JPEG: `kCGImageDestinationLossyCompressionQuality` = 0.95 (off) or `jpegQuality` (on, default 0.80).
- PNG: the flattened image already has no alpha (`noneSkipLast`), so it encodes as 8-bit RGB.
- Compression on: pass no metadata. Set `kCGImagePropertyOrientation` only if needed. Do not copy EXIF/TIFF/GPS, and do not add DPI. Check with `mdls` or `sips -g all` in Phase 8.
- Encode twice when compression is on: the uncompressed version (for the "original" size) and the compressed version. If the compressed data is larger, write the uncompressed data and hide the compression line (§7.3).
- Sizes are formatted by `ByteCountFormatter` with `.file` style.

### 6.4 File name and write (§7.4, `FileNamer`)
- `DateFormatter` with `dateFormat = "MM-dd-yy HH.mm"`, `locale = en_US_POSIX`, the local time zone, and the **capture** time.
- Prefix: strip `/` and `:`, trim it. If it is empty, use `Screenshot`.
- Extension: `png` or `jpg`.
- Collision: if `{name}.{ext}` exists, try `{name} (2).{ext}`, `{name} (3).{ext}`, and so on.
- Destination: if the folder is missing or not a directory, use `~/Downloads` and set `usedFallback = true`.
- `data.write(to: url, options: .atomic)`.

### 6.5 Clipboard (§7.5)
- If `copyToClipboard`: `NSPasteboard.general.clearContents()`, then `writeObjects([url as NSURL])` and `setData(data, forType: .png)` or `.init("public.jpeg")` on the same pasteboard item. Check that pasting into Preview/Slack gives the image and pasting into Finder gives the file. If both types on one item conflict, use one `NSPasteboardItem` with both the file URL and the image data types.
- The pasteboard is main-thread only. Do this step after the background work returns.

### 6.6 ExportPipeline orchestration
- `EditorState.save()`: take a snapshot of `ExportSettings`, `baseImage`, `document`, and the capture date. Disable the Save button (prevent a double save).
- `Task.detached` (or a `nonisolated async` function) runs crop → flatten → resize → encode → write. It returns an `ExportResult { url, fileName, originalSize, finalSize, didResize, uncompressedBytes, finalBytes, showCompression, usedFallback }` or an error.
- Back on the main actor: clipboard, close the editor, return the coordinator to `idle`, and hand the result to the toast (Phase 7; log it until then).
- On a write error: keep the editor open and enable Save again. Report the error (a toast in Phase 7).

### 6.7 Unit tests (`peteshotsTests`, Swift Testing)
- `FileNamer`: format, prefix cleanup, empty prefix, collision suffixes (use a temp directory).
- Resize math: no-op below the threshold, exact dimensions above it, never scale up.
- `ImageEncoder`: PNG has no alpha (`CGImageSource` properties: `hasAlpha == false`), no EXIF when compression is on, JPEG quality changes the size.
- `Renderer`: a crop gives the correct output size. An arrow draws pixels in the expected area (sample a pixel).

**Done when:** acceptance #6, #8 (nothing written on cancel), and #10 hold. The unit tests pass (`xcodebuild test -scheme peteshots -destination 'platform=macOS'`).

---

## Phase 7 — Toast notification and full Settings window

### 7.1 Toast (§8)
- `ToastPanel`: `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`. It must never become key or main.
- Content: `NSVisualEffectView` (`.hudWindow` material, `.behindWindow`, corner radius about 10) hosting a SwiftUI `ToastView` with 13 pt system text.
- Lines (only the lines that apply):
  - `✓ Saved "{fileName}"`
  - `↘ Resized {W}×{H} → {W}×{H}` when resized.
  - `🗜 {original} 👉 {final}` when compression is on and it made the file smaller.
  - A warning line when the destination fell back to Downloads.
- Position: top-right of the capture screen's `visibleFrame`, with a margin of about 12 pt.
- Timing: fade in (0.2 s), visible 2.5 s, fade out (0.3 s), then `orderOut`. Error variant: red accent, 4 s.
- Click: `NSWorkspace.shared.activateFileViewerSelecting([url])`. After the fade, the panel is out of the window list, so it steals no clicks.
- Only one toast at a time: a new toast replaces the old one.
- Use the error toast for capture failures (Phase 2) and write failures (Phase 6).

### 7.2 SettingsView (§9)
- One SwiftUI `Form` (`.formStyle(.grouped)`), fixed width about 460 pt:
  - **Capture hotkey:** `KeyboardShortcuts.Recorder("Capture hotkey:", name: .takeScreenshot)`. The change takes effect right away (the library re-registers).
  - **Save to:** path text (abbreviated with `~`) + **Choose…** (`NSOpenPanel`, `canChooseDirectories = true`, `canChooseFiles = false`) + **Reveal** (`activateFileViewerSelecting`).
  - **Filename prefix:** text field that strips `/` and `:` as you type. Live preview `"{prefix} - 09-30-26 14.05.png"` (with the current format extension). An empty prefix previews as `Screenshot`.
  - **Format:** segmented `Picker` PNG / JPEG.
  - **Resize large images:** toggle + number field "Max long side (px)", clamped to 200–10000. Disabled when the toggle is off.
  - **Compression:** toggle.
  - **JPEG quality:** slider 60–95%, visible only when the format is JPEG and compression is on.
  - **Copy to clipboard on save:** toggle.
  - **Launch at login:** toggle + a status line.
- Opening Settings from a menu bar app: call `NSApp.activate()` so the window comes to the front.

### 7.3 Launch at login
- `LaunchAtLogin.swift`: `SMAppService.mainApp.register()` / `unregister()`. Show `status` (`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`). For `.requiresApproval`, show a button that calls `SMAppService.openSystemSettingsLoginItems()`.
- First launch: the default is on. If the `launchAtLogin` key has never been set, register once and store `true`. Afterwards, the toggle is the source of truth, and it reflects the real `status` when the window opens.
- Add `user-todo.md` items: install to `/Applications`, approve the login item (spec "Manual Setup" steps 3 and 4).

**Done when:** acceptance #7 and #11 hold. Every setting changes the next export with no restart.

---

## Phase 8 — Edge cases, polish, and acceptance testing

### 8.1 Edge cases (§11)
- **Multiple displays with different scale factors:** test a selection that crosses two displays. The editor uses `image.width / rect.width` as the scale.
- **Full-screen apps and other Spaces:** the overlay appears over a full-screen app (`.fullScreenAuxiliary`) and on the active Space.
- **Very large selections (6K):** the editor opens fast and fits the window. Check that blur drags stay smooth. If they are slow, use the padded-crop blur from §4.3, or show a lower-resolution preview while dragging.
- **Tiny editor images:** the minimum window size keeps the toolbar usable, and the image is centered.
- **Destination deleted or unmounted:** save falls back to Downloads with the toast warning.
- **Write failure:** make the folder read-only, save, check the error toast, and check that the editor stays open.
- **Permission revoked:** remove the Screen Recording permission, press the hotkey, check that the explanation window appears with no overlay.
- **Hotkey during overlay / editor:** ignored / editor to the front.
- **Protected content:** black pixels are fine. No special handling.

### 8.2 Performance
- Measure hotkey-to-overlay time (target about 150 ms) and hotkey-to-editor time (target about 300 ms after mouse-up) with `os_signpost` or simple `ContinuousClock` logs. Remove the logs after the check.
- Keep the `CIContext`, the date formatter, and the byte formatter as shared instances.

### 8.3 Privacy check (§10)
- `grep` the code for `URLSession`, `Network`, `NWConnection`, and `http`. There must be no matches outside comments.
- Check the saved files for metadata with `mdls` and `exiftool` (if installed) or `sips -g all`.
- Run the app with `nettop -p <pid>` during a full capture and save cycle. There must be no connections (acceptance #12).

### 8.4 Code cleanup
- Remove the temporary debug windows and logs.
- Fix all Swift 6 concurrency warnings.
- Delete the empty UI test template if it has no value, or add a smoke launch test.

### 8.5 Acceptance run
Go through spec §12 items 1–12 one by one on a Release build installed in `/Applications`. Record the results in this file under a short "Acceptance results" list. File a `user-todo.md` item for any step that needs Pete (for example, the Little Snitch/LuLu check, or a second display).

**Done when:** all 12 acceptance criteria pass.

---

## Risks and Notes

- **Screen Recording permission resets** with ad-hoc signing. Set a Development Team first (Phase 1 user-todo). Without it, every rebuild asks again.
- **Overlay in the capture:** if one frame is not enough, wait for the window server with a short `Task.sleep` (up to about 50 ms). Test on a ProMotion display.
- **Text WYSIWYG:** `NSTextView` layout and `NSAttributedString.draw` can differ by a pixel or two. Use the same attributes, no text container padding (`lineFragmentPadding = 0`, `textContainerInset = .zero`), and the same measuring function.
- **Blur performance on large captures:** see §4.3 and §8.1.
- **Swift 6 isolation:** Core Image, ImageIO, and `CGContext` work in `nonisolated` functions. Pass `CGImage` (it is `Sendable` in current SDKs) and value types across actors. Do not pass `NSImage` or views across actors.
- **SPM through pbxproj edits** can be fragile. Use the `user-todo.md` fallback if package resolution fails.
