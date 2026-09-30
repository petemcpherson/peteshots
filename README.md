# Peteshots

A small macOS menu bar screenshot tool. Select a region, annotate it (arrows, blur, text, crop), and save it with optional resizing and compression.

Everything stays on your Mac. The app has no network code.

## Requirements

- macOS 26.2 or later
- Xcode 26.2 or later

## Build

1. Open `peteshots.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your own development team.
3. Build and run the `peteshots` scheme.

The app asks for the Screen Recording permission the first time you take a screenshot.

## Dependencies

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Swift Package Manager)
