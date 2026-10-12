# Deploy: public release + Homebrew install

Peteshots ships as a signed, notarized DMG on GitHub Releases. Users install and update it with Homebrew, from a cask that lives **in this repo** (`Casks/peteshots.rb`). There is no separate `homebrew-tap` repo.

This is the same model used for PeteKM. The general playbook is in `context/MACOS-HOMEBREW-DISTRIBUTION-GUIDE.md`. This file has the Peteshots-specific values and status.

What users run:

```sh
brew tap petemcpherson/peteshots https://github.com/petemcpherson/peteshots
brew install --cask petemcpherson/peteshots/peteshots
```

Then `brew upgrade` forever after.

```
Peteshots.xcodeproj ──scripts/release.sh──▶ build/Peteshots-<v>.dmg  (Developer ID signed, notarized, stapled)
                                                   │
                                       gh release create v<v>
                                                   ▼
            GitHub Release v<v>  ◀── download URL ──  Casks/peteshots.rb  (version + sha256)
```

---

## Status (checked 2026-10-11)

Done:

- [x] Repo is public: `github.com/petemcpherson/peteshots`. MIT license, README.
- [x] Developer ID Application certificate in keychain: `Developer ID Application: Peter McPherson (A2T9Q78M27)`, expires 2031-02-16.
- [x] Hardened Runtime on, App Sandbox off (fine for Developer ID distribution).
- [x] Target is named `Peteshots`, so the built app is `Peteshots.app`.
- [x] Version `1.0.0`, build `1` set in the project (the release script overrides them anyway).
- [x] App icon has real artwork.
- [x] Homebrew 7 installed.

To do before the first release:

- [x] Notary profile: the release script uses `petekm-notary` (PeteKM's, already in the keychain). One profile per developer is enough.
- [x] `scripts/release.sh` created.
- [x] `Casks/peteshots.rb` created.
- [x] README install commands use the tap URL form above.
- [x] 1.0.0 (build 1) built, notarized (Accepted), stapled. Gatekeeper: `source=Notarized Developer ID`. Universal (`x86_64 arm64`).
- [ ] Publish 1.0.0: tag, GitHub Release, push cask, verify with brew (Step 4.5 onward).

Decided and not changing:

- Team ID `A2T9Q78M27` is already committed in `project.pbxproj` and the repo is public, so the guide's `Config/Local.xcconfig` trick (keeping the Team ID out of git) adds nothing here. A Team ID is not a secret. Skip it.
- Minimum macOS is `26.2` (Tahoe). The cask uses `depends_on macos: :tahoe` (Homebrew 7 style; it means Tahoe or newer). Homebrew cannot require a point release.

---

## Step 1 — Notary credential (once per Mac)

The release script defaults to `petekm-notary`, which already exists on this Mac. Do this step only on a new Mac, or if that profile gets revoked. One profile per developer is enough. To create one:

1. Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.
2. Store it:

   ```sh
   xcrun notarytool store-credentials petekm-notary \
     --apple-id "pnm326@gmail.com" \
     --team-id "A2T9Q78M27" \
     --password "<app-specific password>"

   xcrun notarytool history --keychain-profile petekm-notary   # must not error
   ```

To use a different profile name, run the script with `NOTARY_PROFILE=<name>`.

Changing the Apple ID password revokes app-specific passwords. Redo this step if that happens.

## Step 2 — Release script (once)

`scripts/release.sh` (run `chmod +x`). It archives, exports with Developer ID, builds a DMG with an `Applications` shortcut, signs the DMG, notarizes, and staples. It stamps version and build at build time, so you never edit them in Xcode.

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="Peteshots"
VERSION="${1:?usage: release.sh <marketing-version> <build-number>}"
BUILD="${2:?usage: release.sh <marketing-version> <build-number>}"
TEAM="${DEVELOPMENT_TEAM:-A2T9Q78M27}"
PROFILE="${NOTARY_PROFILE:-petekm-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
ARCHIVE="$OUT/$APP.xcarchive"
EXPORT_DIR="$OUT/export"
STAGING="$OUT/dmg"
DMG="$OUT/$APP-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT" "$EXPORT_DIR" "$STAGING"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Archiving $VERSION ($BUILD)"
xcodebuild -project "$ROOT/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    DEVELOPMENT_TEAM="$TEAM" \
    archive

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"

codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/$APP.app"
echo "==> Architectures: $(lipo -archs "$EXPORT_DIR/$APP.app/Contents/MacOS/$APP")"

echo "==> Building disk image"
cp -R "$EXPORT_DIR/$APP.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "==> Signing disk image"
codesign --force --sign "Developer ID Application: Peter McPherson ($TEAM)" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done: $DMG"
shasum -a 256 "$DMG"
```

`build/` is already in `.gitignore`. The script writes `ExportOptions.plist` into `build/` at run time, so nothing else needs committing.

Notarizing the DMG covers the app inside it. A separate zip-and-notarize of the `.app` is not needed.

## Step 3 — Cask (once)

`Casks/peteshots.rb`:

```ruby
cask "peteshots" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_DMG"

  url "https://github.com/petemcpherson/peteshots/releases/download/v#{version}/Peteshots-#{version}.dmg"
  name "Peteshots"
  desc "Menu bar screenshot tool with arrows, blur, text and crop"
  homepage "https://github.com/petemcpherson/peteshots"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Peteshots.app"

  uninstall quit:       "com.peteshots.peteshots",
            login_item: "Peteshots"

  zap trash: [
    "~/Library/Application Scripts/com.peteshots.peteshots",
    "~/Library/Containers/com.peteshots.peteshots",
    "~/Library/Preferences/com.peteshots.peteshots.plist",
    "~/Library/Saved Application State/com.peteshots.peteshots.savedState",
  ]
end
```

Notes:

- No `auto_updates true`. Peteshots has no in-app updater, so plain `brew upgrade` updates it.
- No `depends_on arch:` if the script prints `x86_64 arm64`. If it prints only `arm64`, add `depends_on arch: :arm64`.
- `zap` runs only on `brew uninstall --zap`. The `Application Scripts` and `Containers` folders are left over from early sandboxed dev builds. Listing them is harmless.
- Bundle ID `com.peteshots.peteshots` never changes. Users would lose their Screen Recording permission and settings.

## Step 4 — Every release (including the first)

### 4.1 Numbers

- **Version** (shown to users): semver. Fixes `1.0.0` → `1.0.1`, features → `1.1.0`.
- **Build**: previous + 1. Never repeats, never decreases. See the release log at the bottom.

```sh
V=1.0.0
B=1
```

### 4.2 Gate

Quit any running copy of Peteshots first. UI tests that launch the app can hang if it is already running.

```sh
git status                                                   # clean, on main, pushed
xcodebuild -project Peteshots.xcodeproj -scheme Peteshots test   # green
```

### 4.3 Build, sign, notarize

```sh
scripts/release.sh "$V" "$B"
spctl -a -t open --context context:primary-signature -v "build/Peteshots-$V.dmg"   # "accepted"
```

If notarization fails: `xcrun notarytool log <submission-id> --keychain-profile petekm-notary`.

### 4.4 Test like a stranger (first release, or after big changes)

Copy the DMG to another Mac or a new user account (AirDrop or a download sets the quarantine flag, which is the real test). Open it, drag Peteshots to Applications, launch. Expect no "unidentified developer" warning. Do a capture and save, and check launch at login. Use the Phase 8 checklist in `context/user-todo.md`.

### 4.5 GitHub Release

```sh
git tag "v$V" && git push origin "v$V"
gh release create "v$V" "build/Peteshots-$V.dmg" --title "Peteshots $V" --notes "What changed."
```

The tag **must** be `v<version>` and the asset **must** be `Peteshots-<version>.dmg`, or the cask URL 404s.

### 4.6 Update the cask

Set `version` and `sha256` (printed by the script, or `shasum -a 256 "build/Peteshots-$V.dmg"`) in `Casks/peteshots.rb`. Commit and push to `main`. From that moment, `brew upgrade` delivers the release. Add a row to the release log below.

### 4.7 Verify

First release (fresh install):

```sh
brew untap petemcpherson/peteshots 2>/dev/null
brew tap petemcpherson/peteshots https://github.com/petemcpherson/peteshots
brew install --cask petemcpherson/peteshots/peteshots
brew audit --cask --strict petemcpherson/peteshots/peteshots
open -a Peteshots                                           # no Gatekeeper warning
```

Later releases (with the previous version installed):

```sh
brew update && brew upgrade --cask peteshots
```

---

## README install section

Use the long form. Two reasons:

- **The tap needs the URL**, because the repo is not named `homebrew-<something>`. The tap name `petemcpherson/peteshots` is arbitrary but must be used everywhere.
- **The install needs the fully qualified name.** Homebrew 7 refuses casks from untrusted third-party taps. `brew install --cask peteshots` alone fails with `Refusing to load cask … from untrusted tap`. Installing by `petemcpherson/peteshots/peteshots` trusts it automatically.

`brew upgrade --cask peteshots` and `brew uninstall --cask peteshots` work with the short name once installed.

---

## Gotchas

| Symptom | Cause / fix |
| --- | --- |
| `No Keychain password item found for profile` | Notary profile missing on this Mac, or revoked by an Apple ID password change. Redo Step 1. |
| Archive/export signing error | Developer ID cert missing or expired. Check `security find-identity -v -p codesigning`. |
| Notarization "Invalid" | Read the log (`xcrun notarytool log …`). Usually hardened runtime off or an unsigned nested binary. |
| Notarization rejected for agreements | Membership lapsed, or a new agreement needs accepting at developer.apple.com. |
| `brew install` SHA mismatch | `sha256` came from a different DMG than the uploaded one. Recompute from the Release asset. |
| `brew install` 404 | Tag isn't `v<version>` or DMG name doesn't match the cask URL. |
| `Refusing to load cask … from untrusted tap` | Install by the fully qualified name. |
| `brew upgrade` doesn't see the release | Cask commit not pushed to `main`, or run `brew update`. |
| Gatekeeper warning on first launch | DMG not notarized or not stapled. Check `xcrun stapler validate`. |
| Screen Recording prompt keeps coming back, though Peteshots is enabled in Settings | The Settings entry belongs to an old dev build (Apple Development signature). macOS matches the entry by signature, so the Developer ID build needs its own. Quit Peteshots, run `tccutil reset ScreenCapture com.peteshots.peteshots`, launch, grant, then quit and relaunch. Only affects this dev Mac. Real users never had a dev build, and later Developer ID releases keep the permission. |
| UI tests hang ~60 s at start | A copy of Peteshots is already running. Quit it. |

---

## Later (optional)

- **Automate 4.5–4.6** in `release.sh`: `gh release create`, then rewrite `version`/`sha256` in the cask with `sed`, then commit.
- **GitHub Actions.** Run the release on a pushed `v*` tag. Needs the Developer ID `.p12` and an App Store Connect API key (`.p8`) as repo secrets, in a protected Environment that needs your approval. Do this only after the manual flow works a few times.
- **Sparkle** for in-app updates. See the guide. If added, put `auto_updates true` in the cask.
- **Official `homebrew/cask`.** Once Peteshots has real traction (a few hundred stars for a self-submitted app), PR the cask to `Homebrew/homebrew-cask` at `Casks/p/peteshots.rb` so users can run `brew install --cask peteshots`. Then delete `Casks/` here and update the README.

---

## Quick reference

| Thing | Value |
|---|---|
| Project / scheme | `Peteshots.xcodeproj` / `Peteshots` |
| Bundle ID | `com.peteshots.peteshots` (never change) |
| Team ID | `A2T9Q78M27` |
| Signing identity | `Developer ID Application: Peter McPherson (A2T9Q78M27)` |
| Notary profile | `petekm-notary` (shared with PeteKM) |
| Tag format | `v1.0.0` |
| Asset name | `Peteshots-1.0.0.dmg` |
| Cask | `Casks/peteshots.rb` in this repo |
| Tap | `brew tap petemcpherson/peteshots https://github.com/petemcpherson/peteshots` |
| Install | `brew install --cask petemcpherson/peteshots/peteshots` |

## Release log

| Version | Build | Date | Notes |
|---|---|---|---|
| 1.0.0 | 1 | 2026-10-11 | First public release. |
