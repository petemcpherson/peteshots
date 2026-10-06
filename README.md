<h1 align="center">Peteshots</h1>

<p align="center">
  <strong>Snap it. Mark it up. Shrink it. Done.</strong><br>
  A tiny macOS menu bar screenshot tool with a built-in editor and automatic compression.
</p>

<p align="center">
  <a href="https://github.com/petemcpherson/peteshots/releases"><img src="https://img.shields.io/github/v/release/petemcpherson/peteshots?label=release&color=ff3b30" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26.2%2B-black" alt="macOS 26.2 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/network%20calls-zero-brightgreen" alt="Zero network calls">
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#the-editor">Editor</a> ·
  <a href="#settings">Settings</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#faq">FAQ</a>
</p>

<!-- TODO: add a screenshot or GIF of the editor here, e.g. docs/editor.png -->

---

Most screenshot workflows go like this: take the screenshot, find the file, open it in another app, draw an arrow, blur your email address, export it, then notice it's a 4 MB PNG and compress it somewhere else.

Peteshots does all of that in one go. Press **⌘⇧A**, drag a box, add an arrow, and press **⌘S**. You get a small, clean file in your Downloads folder and on your clipboard, plus a short note that tells you how much it shrank.

```
✓ Saved "Screenshot - 10-05-26 14.05.png"
↘ Resized 2354×1480 → 2000×1257
🗜 1.8 MB 👉 412 KB
```

## Highlights

- **Fast.** Hotkey to crosshair feels instant. The editor opens as soon as you let go of the mouse.
- **A small editor that covers the basics:** arrows, blur, text, crop, colors, outlines, and gradient backgrounds.
- **Automatic resize.** Big Retina captures scale down to a long side you choose (2000 px by default).
- **Real compression.** PNGs use a 256-color palette, which often cuts the size by more than half. JPEG quality is adjustable.
- **Clipboard ready.** Every save also goes to the clipboard. Paste the image into Slack, or paste the file into Finder.
- **Local only.** No network code, no analytics, no account. Saved files have no metadata.
- **Stays out of the way.** Menu bar icon only, no Dock icon. It can launch at login.

## Install

### Homebrew (recommended)

```sh
brew install --cask petemcpherson/tap/peteshots
```

To update later:

```sh
brew upgrade --cask peteshots
```

### Download

1. Download the latest `Peteshots-x.y.z.dmg` from the [Releases page](https://github.com/petemcpherson/peteshots/releases).
2. Open it and drag **Peteshots** into **Applications**.
3. Launch Peteshots. A small viewfinder icon with a **P** appears in your menu bar.

Builds are signed with an Apple Developer ID and notarized by Apple, so macOS opens them normally.

### Requirements

- macOS 26.2 (Tahoe) or later
- Apple Silicon or Intel Mac

## First launch

Peteshots needs one permission: **Screen Recording**. Without it, macOS does not let any app read the screen.

1. Press **⌘⇧A**. Peteshots explains what it needs and shows an **Open System Settings** button.
2. In **System Settings → Privacy & Security → Screen & System Audio Recording**, turn on **Peteshots**.
3. Quit Peteshots and open it again if macOS asks you to.

If you see a **"Background Items Added"** notice, that is the launch-at-login feature. Leave it on to start Peteshots when you log in. You can change it in **System Settings → General → Login Items**.

## How it works

1. **Press ⌘⇧A.** Every display dims a little and the cursor becomes a crosshair.
2. **Drag a box.** A label shows the size in real pixels. Hold **Shift** for a perfect square. Selections can cross two displays.
3. **Let go.** The editor opens with your capture.
4. **Mark it up** (or skip this step).
5. **Press ⌘S.** Peteshots crops, flattens, resizes, compresses, saves, and copies the image. A toast shows what happened. Click the toast to show the file in Finder.

Changed your mind? Press **Esc** or right-click to cancel the selection. In the editor, **Esc**, **Cancel**, or the close button throws the capture away. Nothing is written to disk until you save.

## The editor

| Tool | Key | What it does |
|---|---|---|
| Select | `V` | Click to select. Drag to move. Drag handles to reshape. |
| Arrow | `A` | Drag from tail to head. Drag either end later to re-aim it. Four weights: Thin, Regular, Bold, Heavy. |
| Blur | `B` | Drag a box over anything private. The blur is strong enough to make text unreadable, and it updates live as you move or resize the box. |
| Text | `T` | Click and type. Return adds a line. Drag a corner to resize, and the font scales with it. Double-click to edit again. |
| Crop | `C` | Drag the handles, then press Return to apply or Esc to cancel. Crop again at any time to change it. Nothing is lost. |

Also in the toolbar:

- **Color.** Applies to arrows and text. Peteshots remembers it between sessions. The default is a bold red, `#FF3B30`.
- **Outline.** Adds a white (or any color) outline behind arrows and text, so they stand out on busy backgrounds. Choose Off, Thin, Medium, or Thick.
- **Background.** Places your screenshot on a gradient with rounded corners and a soft shadow, ready to share. Choose from eight gradients (Sunset, Ocean, Grape, Aurora, Mint, Peach, Cloud, Midnight) and set the padding.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧A | Take a screenshot (you can change it in Settings) |
| ⌘S | Save and close |
| Esc | Cancel the editor, or stop editing text, or cancel a crop |
| ⌘Z / ⌘⇧Z | Undo / redo |
| Delete | Remove the selected annotation |
| Return | Apply the crop |
| ⌘Return | Finish editing text |

Tool keys (`V` `A` `B` `T` `C`) do not work while you type in a text box. They type letters instead.

## Settings

Open **Settings…** from the menu bar icon, or press **⌘,** while the menu is open. Changes apply right away.

| Setting | Default | Notes |
|---|---|---|
| Capture hotkey | ⌘⇧A | Record any shortcut you like. |
| Save to | `~/Downloads` | If the folder disappears, Peteshots saves to Downloads and tells you. |
| Filename prefix | `Screenshot` | Files are named `Screenshot - MM-dd-yy HH.mm.png`. Duplicates get ` (2)`, ` (3)`, and so on. |
| Format | PNG | PNG keeps text and UI sharp. JPEG makes smaller files for photos. |
| Resize large images | On, 2000 px | Scales the long side down to this size. Never scales up. |
| Compression | On | Also removes all metadata. |
| PNG compression | Light | Light = 256 colors, Medium = 128, Strong = 64. |
| JPEG quality | 80% | 30–95%. |
| Copy to clipboard on save | On | |
| Launch at login | On | Works best when the app is in `/Applications`. |

## Privacy

Peteshots is local only, and the code proves it:

- **No network code.** No analytics, crash reports, update checks, or cloud uploads. You can confirm this with `nettop`, Little Snitch, or LuLu.
- **Memory first.** A capture stays in memory until you press Save. Cancel, and it is gone.
- **No metadata.** Compressed files have no EXIF, GPS, or camera data.
- **One permission.** Screen Recording is used only when you press the hotkey.

## Uninstall

With Homebrew:

```sh
brew uninstall --cask peteshots          # the app
brew uninstall --zap --cask peteshots    # the app and its settings
```

Manual: quit Peteshots from the menu bar and drag `Peteshots.app` to the Trash. To remove the settings too, run:

```sh
defaults delete com.peteshots.peteshots
```

## FAQ

**I pressed ⌘⇧A and nothing happened.**
Another app may use the same shortcut. Choose a different one in Settings. Also check that Peteshots is running: look for the icon in the menu bar.

**The capture is black, or only shows my wallpaper.**
Screen Recording is off, or macOS needs a restart of the app after you turn it on. Check **System Settings → Privacy & Security → Screen & System Audio Recording**, then quit and reopen Peteshots. Some protected content, such as DRM video, always captures as black.

**Why is my PNG so small? Did it lose quality?**
Compressed PNGs use a 256-color palette. Screenshots of apps and text rarely use more colors than that, so they look the same. If an image already fits in the palette, it stays pixel-perfect. For photos or gradients, use **Light**, choose JPEG, or turn compression off.

**Can it capture a window, the full screen, or video?**
Not yet. Peteshots does one thing: a region you choose. Drag across the whole screen for a full-screen shot.

**Does Peteshots keep a history of my screenshots?**
No. Your files are in your save folder, and nowhere else.

## Build it yourself

You need Xcode 26.2 or later.

```sh
git clone https://github.com/petemcpherson/peteshots.git
cd peteshots
open peteshots.xcodeproj
```

1. In **Signing & Capabilities**, select your own development team. A stable signature keeps the Screen Recording permission across rebuilds.
2. Build and run the `peteshots` scheme.

Run the tests:

```sh
xcodebuild test -project peteshots.xcodeproj -scheme peteshots -destination 'platform=macOS'
```

### Under the hood

- Swift 6, SwiftUI for settings and editor controls, AppKit for the overlay, canvas, and toast.
- ScreenCaptureKit for capture, Core Image for blur and Lanczos resizing, and ImageIO for encoding.
- A custom median-cut quantizer for palette PNGs.
- One dependency: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, for the global hotkey.

## Contributing

Bug reports and ideas are welcome. Please [open an issue](https://github.com/petemcpherson/peteshots/issues). Peteshots is meant to stay small and simple, so feature requests that keep it that way are the most likely to land.

## License

[MIT](LICENSE), © 2026 Pete McPherson.
