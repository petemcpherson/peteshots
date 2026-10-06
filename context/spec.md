# Peteshots — Spec

A personal, local-only macOS screenshot tool. Press a hotkey, drag a region, annotate it in a small editor, save. The app resizes and compresses the image and shows a short toast with the results.

Source: `context/notes.md`. This document covers **what** to build and the key technical decisions. The implementation plan comes later. **Status: final.**

---

## Decisions Summary

The spec is final. No open questions remain. These decisions resolve the earlier questions:

| # | Topic | Decision |
|---|---|---|
| 1 | App Sandbox | **Off.** Hardened Runtime stays on. See "Manual Setup" below. |
| 2 | Close without saving | Esc, Cancel, or the close button **discards** the capture with no confirmation. A hotkey press while the editor is open brings the editor to the front. |
| 3 | Clipboard | **Included.** It is a few lines of code. On save, the final image is also copied to the clipboard. A Settings toggle controls it (on by default). |
| 4 | Filename | `{prefix} - MM-dd-yy HH.mm.{ext}`, for example `Screenshot - 09-30-26 14.05.png`. On a name collision, append ` (2)`, ` (3)`, and so on. |
| 5 | Resize threshold units | **Real pixels** (the full captured resolution). Default limit: 2000 px. |
| 6 | Undo/redo | **Included**, with snapshot-based undo (§5.9). |
| 7 | Blur style | Strong **Gaussian blur** only. No pixelate option. |
| 8 | Launch at login | **Included.** Settings toggle, on by default. |
| 9 | Hotkey conflict | Accept it. Cmd-Shift-A is the default, and you can rebind it in Settings. |
| 10 | PNG compression | **Native ImageIO only** (lossless optimization). No third-party libraries. For small files, choose JPEG. |

Small items that were "nice-to-have" are now decided:
- **Included:** Shift for a square selection, single-key tool shortcuts, and a text shadow for readability.
- **Dropped from v1:** hover-to-pause on the toast, and the Settings "Restore Defaults" button.

## Manual Setup (Pete)

The implementation turns off the sandbox in code: it sets `ENABLE_APP_SANDBOX = NO` in the project build settings. In Xcode, this is the same as removing the **App Sandbox** capability under *Signing & Capabilities*. You don't need to do it yourself. The steps below need a person:

1. **Choose a signing team.** In Xcode, open *Target peteshots → Signing & Capabilities* and select your Personal/Development Team. With a stable signature, macOS keeps the Screen Recording permission across rebuilds.
2. **Grant Screen Recording.** At the first capture, allow Peteshots in *System Settings → Privacy & Security → Screen & System Audio Recording*. Then quit and relaunch the app if macOS asks.
3. **Install for daily use.** Copy the Release build to `/Applications`. Launch at login works best from there.
4. **Approve the login item** if macOS shows the "Background Items Added" notice. You can also do this in *System Settings → General → Login Items*.

---

## 1. Goals and Non-Goals

**Goals**
- Fast: hotkey to editor in under about 300 ms.
- A very simple editor: arrow, blur, text, crop, and a color picker.
- Automatic resize and compression, with visible feedback.
- 100% local. No network code, no analytics, no cloud storage.

**Non-Goals (v1)**
- Window capture, full-screen capture, timed capture, screen recording.
- Screenshot history or library, and cloud sync or upload.
- Shapes other than arrows (rectangles, highlighter, freehand), and numbered steps.
- App Store distribution, multiple users, and localization.

---

## 2. Platform and Project Baseline

| Item | Value |
|---|---|
| Xcode | 26.2 |
| Deployment target | macOS 26.2 (from the template; keep it) |
| Language | Swift. The template sets `SWIFT_VERSION = 5.0`. Upgrade to Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (already set). |
| UI | SwiftUI for Settings and the editor chrome. AppKit (`NSPanel`/`NSWindow`/`NSView`) for the selection overlay, the toast, and the editor canvas where needed. |
| Bundle ID | `com.peteshots.peteshots` |
| Dependencies | [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) (SPM) only. |

**Template cleanup.** Remove the SwiftData boilerplate: `Item.swift`, `ModelContainer`, and the `WindowGroup`/`ContentView`. The app stores no records. Settings go in `UserDefaults`.

**Entitlements and Info.plist**
- `LSUIElement = YES`: menu bar app, no Dock icon.
- App Sandbox **off** (`ENABLE_APP_SANDBOX = NO`). Remove the `ENABLE_USER_SELECTED_FILES` setting, because it has no effect without the sandbox. Plain file paths are used everywhere, and no security-scoped bookmarks are needed.
- Hardened Runtime stays **on**. It needs no extra exceptions.
- Screen Recording permission is a TCC prompt, not an entitlement. It is triggered the first time ScreenCaptureKit captures.

---

## 3. App Structure

A **menu bar app** (`MenuBarExtra`) with these items:
- **Take Screenshot** (shows the current hotkey)
- **Open Destination Folder**
- **Settings…** (Cmd-,)
- **Quit Peteshots**

Scenes:
- `MenuBarExtra`: the menu above.
- `Settings`: the preferences window (§9).
- The editor window is created on demand from AppKit. It is not a SwiftUI `WindowGroup`, so the app has full control over its size, position, and lifecycle.

Suggested components (names are only a guide):

| Component | Responsibility |
|---|---|
| `HotkeyService` | Registers the global shortcut through KeyboardShortcuts and starts a capture. |
| `CaptureCoordinator` | Runs the flow: permission check, overlay, capture, editor, export, save, toast. |
| `SelectionOverlay` | One borderless full-screen window per display. Handles the crosshair and drag-to-select. |
| `ScreenCapturer` | Wraps `SCScreenshotManager`. |
| `EditorWindow` / `EditorView` | Shows the captured image, the toolbar, and the annotation layer. |
| `AnnotationModel` | Value types for arrows, blurs, and text, plus the crop rectangle. |
| `Renderer` | Flattens the image and annotations into a `CGImage` at full pixel resolution. |
| `ExportPipeline` | Crop, flatten, resize, encode/compress, write, and report the results. |
| `Toast` | A small auto-dismissing notification panel. |
| `Settings` | `@AppStorage`-backed preferences. |

---

## 4. Capture Flow

### 4.1 Hotkey
- Use KeyboardShortcuts with `Name("takeScreenshot", initial: .init(.a, modifiers: [.command, .shift]))`.
- Trigger on key-down for a fast response.
- The hotkey uses the Carbon `RegisterEventHotKey` API. It needs no Accessibility permission.
- Ignore the hotkey while an overlay is already active. If the editor is open, bring the editor to the front.

### 4.2 Permission
- Before the first capture, check `CGPreflightScreenCaptureAccess()`. If access is not granted, call `CGRequestScreenCaptureAccess()`. Then show a small window that explains the problem and has an **Open System Settings** button, which deep-links to Privacy & Security, Screen Recording.
- **Development note:** TCC ties the permission to the code signature. Sign debug builds with a stable Development Team. Ad-hoc signing makes macOS ask for permission again after every rebuild.

### 4.3 Selection overlay
- Show one borderless, transparent `NSPanel` per `NSScreen` with these properties:
  - Level `.screenSaver` (above the menu bar and the Dock).
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
  - Ignores Mission Control, and does not appear in its own capture (it is hidden before capture; see below).
- Cursor: `NSCursor.crosshair`.
- Before the drag, the screen is dimmed slightly (about 20% black) as a cue.
- During the drag, the selected rectangle is clear (undimmed) with a 1 pt white border. A small label near the cursor shows the size in real pixels, for example `1024 × 640`.
- The rectangle is free-form and can be dragged in any direction. Hold **Shift** to force a square.
- **Esc** or a right-click cancels. **Mouse-up** confirms.
- If the selection is smaller than 4×4 pt, treat it as a click: cancel, with no capture.
- A selection that crosses two displays is allowed. The `SCScreenshotManager` rectangle APIs support multiple displays.

### 4.4 Capture
- On mouse-up:
  1. Hide the overlay windows (`orderOut`).
  2. Wait one frame so the overlay does not appear in the screenshot.
  3. Call `SCScreenshotManager.captureImage(in: rect)`.
- `rect` is in **global display space points**. Convert from the Cocoa global coordinate system (bottom-left origin) to CoreGraphics display space (top-left origin, primary display).
- The result is a `CGImage` at native pixel resolution, for example 2× on Retina.
- Nothing is written to disk at this point. The image stays in memory.

---

## 5. Editor

### 5.1 Window
- A standard titled `NSWindow`, activated and made key when it opens. The app calls `NSApp.activate()` because it is an `LSUIElement` app.
- The window opens centered on the display where the capture happened.
- Size: the image at 1:1 in **points** (a Retina capture shows at its screen size). The window is limited to about 85% of the visible screen frame. If the image is larger, scale it down to fit (no scrolling or zoom in v1). A minimum size keeps the toolbar usable for tiny captures, with the image centered on a neutral background.
- All annotation geometry is stored in **image pixel coordinates**. The view converts between view and image coordinates, so the display scale never affects the output.

### 5.2 Toolbar
A slim top bar, left to right:

`[Select] [Arrow] [Blur] [Text] [Crop]  |  [● color swatch]  ……  [Cancel] [Save]`

- Tools are mutually exclusive. **Select** is the default tool after each annotation is placed. This avoids placing an annotation by accident, and you can move things right after you draw them. Pressing the same tool button again keeps that tool active.
- Single-key tool shortcuts: `V` select, `A` arrow, `B` blur, `T` text, `C` crop. These keys work only when no text box is being edited.
- **Cmd-S** or **Save** saves and closes. **Esc**, **Cancel**, or the window close button discards the capture with no confirmation. **Delete/Backspace** removes the selected annotation. Cmd-Z and Cmd-Shift-Z undo and redo (§5.9).

### 5.3 Color picker
- The swatch opens the system `NSColorPanel` (through the SwiftUI `ColorPicker`). This gives hex entry, the eyedropper, and saved swatches.
- Arrows and text use the color. Blur does not.
- The current color is saved to `UserDefaults` as a hex string (for example `#FF3B30`), so it persists between sessions. Default: `#FF3B30` (red).
- If an annotation is selected when the color changes, the annotation changes to the new color.

### 5.4 Arrow tool
- Drag from the start point to the end point to create an arrow. The arrowhead is at the end point.
- Style: a solid line with a filled triangular head and rounded caps. Stroke width scales with the image size (about 0.8% of the long side, clamped to 4–20 px). A toolbar menu sets the arrow weight (Thin 0.6×, Regular 1×, Bold 1.5×, Heavy 2× that width). The weight is saved to `UserDefaults`, and a selected arrow takes the new weight.
- Outline: arrows and text can have an outline (see §5.6a).
- When the arrow is selected, it shows **two handles**, one at each end. Drag a handle to move only that end.
- Drag the line body to move the whole arrow.
- Hit-testing uses a tolerance of about 8 pt around the line.

### 5.5 Blur tool
- Drag a rectangle to create a blur region. The region shows the blurred pixels of the **original** image under it, live.
- When selected, the region shows 8 resize handles (corners and edges). Drag inside the region to move it. The blur updates as the region moves.
- Implementation: `CIGaussianBlur` on the clamped source (`clampedToExtent()`), cropped to the rectangle. Radius = `clamp(min(boxWidth, boxHeight) × 0.25, 12, 40)` px, so text is unreadable. There is no pixelate option.
- Blur always samples the base image, never other annotations. Blurs can overlap.

### 5.6 Text tool
- Click to place a text box, and start editing right away. The box shows an inline `NSTextView`/`TextField` with a cursor.
- Font: the system font (`NSFont.systemFont`, SF Pro) in semibold, in the current color. Plain, with no background. A subtle dark shadow (`NSShadow`, 1 px blur, 50% black) helps the text read on any background. The editor and the export use the same shadow.
- **Editing:** double-click an existing box to edit. Click outside, or press Esc, to finish editing. Esc while editing ends editing only; it does not discard the screenshot. A box that is empty after editing is deleted.
- **Move:** drag the box body when the box is selected and not being edited.
- **Resize changes the font size:** the box shows corner handles. Dragging a handle scales the box uniformly, and the font size changes with it. Rule: `fontSize = boxHeight / lineCount / lineHeightMultiple`, and the width reflows to fit the text. No separate font-size control.
- Default font size: about 4.5% of the image's long side, clamped to 18–72 px.
- Text can be multi-line. Return adds a new line. Cmd-Return ends editing.

### 5.6a Outline
- Arrows and text can have an outline drawn behind them, so they read on any background. The toolbar has an outline color swatch and a width menu: Off, Thin, Medium, Thick.
- The width scales with the annotation: 0.2× / 0.35× / 0.5× of the stroke width on each side for arrows, and 3% / 6% / 9% of the font size for text. Joins are round.
- With an outline, the text shadow is drawn on the outline instead of the fill.
- The outline color and width are saved to `UserDefaults`. Default: white, Medium. A selected arrow or text annotation takes the new outline. Outline color changes coalesce into one undo step, like the annotation color.

### 5.6b Background
- A toolbar button opens a popover with **None**, 8 built-in gradients, and a **Padding** slider. There are no custom gradients.
- Gradients: Sunset, Ocean, Grape, Aurora, Mint, Peach (colorful), Cloud (almost white/gray), and Midnight (almost black). Each is a diagonal linear gradient from the top-left to the bottom-right.
- Padding on each side is a fraction of the crop's long side: 2–20%, default 8%. The output image is the crop plus the padding on each side.
- With a background, the screenshot has rounded corners (1.2% of the long side, clamped to 6–24 px) and a soft drop shadow (blur 2% of the long side, clamped to 8–40 px). Annotations are clipped to the screenshot.
- The background is part of the document, so choosing a gradient is one undo step and one slider drag is one undo step. Each capture starts with no background. The padding is saved to `UserDefaults`.
- In crop mode the canvas hides the background. The button is disabled.

### 5.7 Crop tool
- Select the crop tool to show a crop rectangle over the whole image, with 8 handles. The area outside the rectangle is dimmed.
- Drag handles to resize the rectangle, and drag inside to move it.
- **Return** or the toolbar ✓ applies the crop. **Esc** cancels the crop only.
- The crop is **non-destructive**. The editor stores `cropRect` and shows only that area. Annotations keep their coordinates in image space, and annotations outside the crop are cut off at export. Selecting Crop again shows the full image with the current crop rectangle, so you can change it.
- The crop cannot be smaller than 8×8 px.

### 5.8 Selection and layering
- Z-order is the creation order: the newest is on top. Blurs always render **below** arrows and text, so a blur never hides an annotation.
- Only one annotation can be selected at a time. The selection shows handles. Click an empty area to deselect.

### 5.9 Undo / redo
- The editor state is one value type: `EditorDocument { annotations: [Annotation], cropRect: CGRect }`.
- **Snapshot undo.** Before each *committed* change, register the previous `EditorDocument` with the window's `UndoManager`. Committed changes are: adding an annotation, the end of a move or resize drag, deleting an annotation, finishing a text edit, a color change on a selected annotation, and applying a crop. Undo restores the snapshot and registers the redo.
- Intermediate drag updates are not undo steps.
- Undo history lasts only as long as the editor window.

---

## 6. Save Timing (decision)

**Save once, after editing, on Cmd-S or Save.** Nothing touches the disk before that.

Reasons:
- The file is written once, with the final edits, size, and compression. No temp file cleanup, and no half-finished screenshots in Downloads.
- The resize and compression summary describes the real final file.
- Risk: an accidental Esc loses the capture. This is acceptable for a quick tool: you can press the hotkey again.

Export runs off the main thread. After a successful write, the editor closes right away and the toast appears.

---

## 7. Export Pipeline

The pipeline runs in this order:

```
base CGImage (native px)
  → apply crop            (cropRect in px)
  → flatten annotations   (blur regions, then arrows, then text; rendered into a CGContext at full px)
  → resize (optional)     (only if longest side > threshold)
  → encode + compress     (PNG or JPEG)
  → write to destination
  → clipboard (if enabled)
  → toast
```

### 7.1 Flatten
- Draw into an 8-bit sRGB `CGContext` sized to the crop. The screenshot has no transparency, so use `noneSkipLast` (no alpha).
- Blur: render the `CIImage` output from the Core Image blur for each region into the context.
- Arrows: draw as `CGPath`s. Text: draw with `NSAttributedString.draw(in:)`, or Core Text, in a flipped context.
- The output must look the same as the editor view (WYSIWYG). Draw with the same geometry code in the editor and in the export.

### 7.2 Resize
- Setting: **Max long side (px)**, with an enable toggle. Default: enabled, **2000 px**. The unit is real pixels. A value of 1600–2000 px keeps text readable in Retina captures.
- If `max(width, height) > threshold`, scale down so the long side equals the threshold. Keep the aspect ratio, and round to whole pixels.
- Never scale up.
- Scale with `CILanczosScaleTransform`. It keeps small text sharper when it scales down.
- Record `originalSize` and `finalSize` for the toast.

### 7.3 Encode and compress — "simplest and best"
Use **ImageIO** only (`CGImageDestination`). It is built in, fast, and has no dependencies.

| Format | Compression **off** | Compression **on** (default) |
|---|---|---|
| **JPEG** | Quality 0.95 | Quality **0.80** (`kCGImageDestinationLossyCompressionQuality`). This setting is the best size/quality balance for screenshots. |
| **PNG** | Standard PNG, 8-bit RGB | Indexed palette PNG (median cut), no metadata (EXIF/TIFF/DPI), sRGB. Level **Light** (default): 256 colors, dithered. **Medium**: 128 colors, dithered. **Strong**: 64 colors, no dithering. Images that already fit the palette stay exact. |

Also, whenever compression is on, write **no metadata** (EXIF/TIFF/GPS) in either format. This is also a privacy benefit.

Settings:
- **Format:** PNG / JPEG. Default: PNG. Screenshots of text and UI look better as PNG. Choose JPEG for small files.
- **Compression:** on/off. Default: on.
- **JPEG quality slider** (30–95%), shown only for JPEG with compression on. Default: 80%.
- **PNG compression:** Light / Medium / Strong, shown only for PNG with compression on. Default: Light.

**Size shown in the toast:** "original" is the same image (after crop, annotations, and resize) encoded with compression **off**, so the before/after numbers compare only the effect of compression. Encoding twice costs a few milliseconds and is acceptable. If the compressed encoding is ever *larger*, write the uncompressed encoding and do not show the compression line.

File sizes use `ByteCountFormatter` (`.file` style): `1.4 MB`, `312 KB`.

### 7.4 Write
- Path: `{destination}/{prefix} - {MM-dd-yy HH.mm}.{png|jpg}`. The timestamp is the **capture** time in the local time zone.
- If the name exists, add ` (2)`, ` (3)`, and so on.
- Write atomically (`Data.write(to:options: .atomic)`).
- If the destination folder is missing, fall back to `~/Downloads` and say so in the toast.
- On failure (disk full, no permission), show an error toast and **keep the editor open**, so no work is lost.

### 7.5 Clipboard
- If enabled (default: on), clear `NSPasteboard.general`. Then write the saved file's URL and the encoded image data (`.png` or `.jpeg`). Pasting into apps gives the image, and pasting into Finder gives the file.

---

## 8. Toast Notification

- A small, borderless, non-activating `NSPanel` with a translucent material background (`.hudWindow`/`.popover` style), rounded corners, and about 13 pt system text.
- Position: top-right of the display where the capture happened, under the menu bar. It does not take focus, and it does not steal clicks after it fades out.
- It is visible for **2.5 s** with fade in and fade out. Click opens the file in Finder: `NSWorkspace.activateFileViewerSelecting`.
- Content has one or more lines. Show only the lines that apply:

```
✓ Saved "Screenshot - 09-30-26 14.05.png"
↘ Resized 2354×1480 → 2000×1257
🗜 1.8 MB 👉 1.1 MB
```

- If there was no resize and no compression line, show only the "Saved" line.
- Errors use the same panel with a red accent. They stay visible for 4 s.

---

## 9. Settings

A SwiftUI `Settings` scene with one form (tabs are not needed). All values are `@AppStorage`/`UserDefaults`.

| Setting | Control | Default |
|---|---|---|
| Capture hotkey | `KeyboardShortcuts.Recorder` | Cmd-Shift-A |
| Save to | Path + **Choose…** (`NSOpenPanel`, folders only) + **Reveal** | `~/Downloads` |
| Filename prefix | Text field. Preview shows `"{prefix} - 09-30-26 14.05.png"`. Strips `/` and `:`. Empty falls back to `Screenshot`. | `Screenshot` |
| Format | Segmented: PNG / JPEG | PNG |
| Resize large images | Toggle + number field "Max long side (px)" (200–10000) | On, 2000 |
| Compression | Toggle | On |
| JPEG quality | Slider 30–95% (JPEG + compression only) | 80% |
| PNG compression | Segmented: Light / Medium / Strong (PNG + compression only) | Light |
| Copy to clipboard on save | Toggle | On |
| Launch at login | Toggle (`SMAppService.mainApp`) | On |
| Annotation color | Not in Settings. Set from the editor swatch and saved. | `#FF3B30` |

Changes take effect right away. Changing the hotkey re-registers it right away. The launch-at-login toggle calls `SMAppService.mainApp.register()` / `unregister()`, and shows the current status from `SMAppService.mainApp.status`.

---

## 10. Privacy and Local-Only Guarantees

- No networking code or frameworks. No analytics, crash reporting, or update checker.
- Images exist only in memory until saved, and only in the destination folder after saving (plus the clipboard, if enabled).
- Compressed output has no metadata.

---

## 11. Edge Cases

- **No Screen Recording permission:** explain the problem, then deep-link to System Settings. Do not show the overlay.
- **Multiple displays / different scale factors:** show an overlay on every screen. The capture uses native pixels. A selection across displays with different scale factors: accept the image that ScreenCaptureKit returns. Scale factor for the editor display: use `image.width / rect.width`.
- **Full-screen apps and other Spaces:** the overlay must appear over full-screen apps (`.fullScreenAuxiliary`).
- **Hotkey pressed during an overlay:** ignore it. **During the editor:** focus the editor.
- **Very large selections** (for example a 6K display): the editor fits the image to the window. Export works at full resolution, so resize is important here.
- **Tiny selections** (under 4 pt): cancel with no capture.
- **Destination deleted or unmounted:** fall back to Downloads and show a warning in the toast.
- **Protected content** (DRM video, some password fields): ScreenCaptureKit returns black pixels. This is expected, and the app does nothing special.

---

## 12. Acceptance Criteria (v1)

1. On launch, the app shows only a menu bar icon, with no Dock icon.
2. Cmd-Shift-A (or the rebound hotkey) shows the crosshair overlay on all displays within about 150 ms.
3. Drag and release opens the editor with the exact selected region at native resolution.
4. Arrow: create, move, and drag each endpoint. Blur: create, move, and resize, with the blur updating live. Text: create, edit, move, and resize with the font scaling. Crop: set and change.
5. The color persists after an app restart, and it applies to arrows and text.
6. Cmd-S writes one file to the destination with the correct name, format, resize, and compression. The saved image matches the editor view.
7. The toast appears for about 2.5 s with accurate resize and size lines, shown only when they apply.
8. Esc, Cancel, or closing the editor discards the capture, and nothing is written.
9. Cmd-Z / Cmd-Shift-Z undo and redo each committed editor change, including a crop.
10. With the clipboard toggle on, the saved image can be pasted into other apps right after the save.
11. All Settings persist and take effect without a restart. Launch at login works from `/Applications`.
12. The app makes no network connections (check with Little Snitch/LuLu or `nettop`).
