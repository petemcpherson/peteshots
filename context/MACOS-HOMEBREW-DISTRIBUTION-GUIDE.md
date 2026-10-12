# Shipping a macOS App via Homebrew (first time)

A project-agnostic playbook for distributing a SwiftUI/AppKit Mac app **outside the Mac App Store**, as a signed + notarized DMG on GitHub Releases, installed and updated with Homebrew from a cask that lives **in the app's own repo** (no separate tap repo).

Proven end to end on PeteKM (October 2026, Xcode 26, macOS 26, Homebrew 7).

Placeholders used throughout:

| Placeholder | Example |
| --- | --- |
| `<App>` | `PeteKM` (Xcode scheme, `.app` name, DMG prefix) |
| `<app>` | `petekm` (lowercase cask token) |
| `<owner>/<repo>` | `petemcpherson/petekm` |
| `<bundle.id>` | `com.petekm.PeteKM` |
| `<TEAMID>` | 10-character Apple Team ID |
| `<APP>` | `PETEKM` (uppercase prefix for the xcconfig variable) |

---

## The model

```
Xcode project ──release.sh──▶ build/<App>-<v>.dmg  (Developer ID signed, notarized, stapled)
                                     │
                         gh release create v<v>
                                     ▼
          GitHub Release v<v>  ◀── download URL ──  Casks/<app>.rb  (version + sha256)
                                                          │
                                   brew tap <owner>/<app> <repo URL>; brew upgrade
```

- **One public repo** holds source, releases, and the cask.
- **Users update with `brew upgrade`.** No in-app updater needed. (Sparkle can be added later; see the end.)
- Per-release cost once set up: ~20 minutes, mostly waiting on tests and Apple's notary service.

What costs money: the Apple Developer Program, $99/year. Everything else is free.

---

## Phase 1: Apple account and credentials (once per developer, reusable across apps)

Skip any step already done for a previous app. The certificate and notary profile work for every app on the same team.

### 1.1 Apple Developer Program

Enroll at <https://developer.apple.com/programs/>. Approval can take a day or more. Find your **Team ID** at <https://developer.apple.com/account> → Membership details.

### 1.2 Developer ID Application certificate

Xcode → Settings → Accounts → add your Apple ID → select the team → Manage Certificates → **+** → **Developer ID Application**.

Check it:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
security find-certificate -c "Developer ID Application" -p | openssl x509 -noout -enddate
```

It lasts ~5 years. Back it up: Keychain Access → find the cert → expand to include its private key → select both → Export as `.p12` → store in a password manager. Apple limits how many you can create.

### 1.3 Notary credential in the keychain

1. Create an app-specific password at <https://account.apple.com> → Sign-In and Security → App-Specific Passwords.
2. Store it under a profile name (one per developer is enough; naming it per app is fine too):

```bash
xcrun notarytool store-credentials <app>-notary \
  --apple-id "<Apple ID email>" \
  --team-id "<TEAMID>" \
  --password "<app-specific password>"

xcrun notarytool history --keychain-profile <app>-notary   # must not error
```

Changing your Apple ID password revokes app-specific passwords. Redo this step if that happens.

---

## Phase 2: Prepare the Xcode project (once per app)

### 2.1 Keep the Team ID out of git

Don't set the team in Signing & Capabilities: it gets written into `project.pbxproj`. Instead:

`Config/Shared.xcconfig` (committed):

```
#include? "Local.xcconfig"
DEVELOPMENT_TEAM = $(<APP>_DEVELOPMENT_TEAM)
```

`Config/Local.xcconfig` (gitignored, per machine):

```
<APP>_DEVELOPMENT_TEAM = <TEAMID>
```

Add `Config/Local.xcconfig` to `.gitignore`. In Xcode, set `Shared.xcconfig` as the base configuration for the project (Project → Info → Configurations). Without `Local.xcconfig`, builds fall back to ad-hoc "Sign to Run Locally", so contributors can still build.

### 2.2 Build settings

| Setting | Value | Why |
| --- | --- | --- |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization. |
| `ENABLE_APP_SANDBOX` | your choice | Not required outside the App Store. Turn it off if the app shells out to CLI tools (`git`, editors, Terminal). Keep it on if you don't need to. |
| `ENABLE_USER_SELECTED_FILES` | `readwrite` if sandboxed and writing user-chosen files | Only matters when sandboxed. |
| `PRODUCT_BUNDLE_IDENTIFIER` | `<bundle.id>` | Decide now and **never change it** after the first release. Prefs, caches and the cask `zap` paths depend on it. |
| `MACOSX_DEPLOYMENT_TARGET` | lowest macOS you support | Must agree with the cask's `depends_on macos:`. |
| `CODE_SIGN_STYLE` | `Automatic` | The export step picks the Developer ID cert. |

Debug builds don't need any of the release machinery.

### 2.3 Release script

`scripts/release.sh` (make it executable with `chmod +x`). It archives, exports with Developer ID, builds a DMG, signs it, notarizes, and staples. It stamps version and build at build time, so you never edit them in Xcode.

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="<App>"
VERSION="${1:?usage: release.sh <marketing-version> <build-number>}"
BUILD="${2:?usage: release.sh <marketing-version> <build-number>}"
TEAM="${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple Developer team ID}"
PROFILE="${NOTARY_PROFILE:-<app>-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
ARCHIVE="$OUT/$APP.xcarchive"
EXPORT_DIR="$OUT/export"
DMG="$OUT/$APP-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT" "$EXPORT_DIR"

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

echo "==> Building disk image"
hdiutil create -volname "$APP" -srcfolder "$EXPORT_DIR/$APP.app" -ov -format UDZO "$DMG"

echo "==> Signing disk image"
codesign --force --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done: $DMG"
```

Add `build/` to `.gitignore`.

---

## Phase 3: Make the repo public (once per app)

The cask downloads from GitHub Releases and Homebrew clones the repo, so both must be public.

1. Add a `LICENSE` (MIT is the simple default) and a `README.md` with the install commands from Phase 6.
2. Scan for things you wouldn't publish: hardcoded home paths (`grep -rn "/Users/" .`), API keys, tokens, personal notes in docs. Check **the full git history**, not only the current tree (for example `git log -p | grep -iE "api[_-]?key|secret|token|password"`). Going public exposes every past commit.
3. Optional: hide your email on future commits. GitHub → Settings → Emails → "Keep my email addresses private", then `git config user.email "<id>+<user>@users.noreply.github.com"`. Old commits keep the old address.
4. Flip it (treat this as permanent; clones and forks can't be recalled):

```bash
gh repo edit <owner>/<repo> --visibility public --accept-visibility-change-consequences
```

---

## Phase 4: The cask in your own repo (once per app)

Homebrew can tap **any** git repo if you give it the URL explicitly. The repo just needs a `Casks/` folder. So no `homebrew-<app>` repo is needed. Trade-off: `brew tap` clones the whole repo, which is fine for small repos.

`Casks/<app>.rb`:

```ruby
cask "<app>" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHA256_OF_RELEASE_DMG"

  url "https://github.com/<owner>/<repo>/releases/download/v#{version}/<App>-#{version}.dmg"
  name "<App>"
  desc "One-line description, no leading article, no app name"
  homepage "https://github.com/<owner>/<repo>"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"   # match MACOSX_DEPLOYMENT_TARGET

  app "<App>.app"

  zap trash: [
    "~/Library/Application Support/<App>",
    "~/Library/Caches/<bundle.id>",
    "~/Library/Preferences/<bundle.id>.plist",
  ]
end
```

Notes:

- Leave out `auto_updates true` unless the app updates itself (for example, Sparkle). Without it, plain `brew upgrade` upgrades the app.
- `zap` runs only on `brew uninstall --zap`. List app support files only, never user documents.
- `depends_on macos:` takes codenames (`:sonoma`, `:sequoia`, `:tahoe`, …).

---

## Phase 5: Every release (including the first)

### 5.1 Numbers

- **Version** (shown to users): semver. Fixes `1.0.0` → `1.0.1`, features → `1.1.0`.
- **Build**: previous + 1. Never repeats, never decreases.

Keep a release log table (version, build, date, notes) in the repo's distribution doc so you can find the last build number.

```bash
V=1.0.0
B=1
```

### 5.2 Gate

```bash
git status                                     # clean, on main, pushed
xcodebuild -scheme <App> test                  # green
```

Quit any running copy of the app first. UI tests that launch the app can hang if it's already running.

### 5.3 Build, sign, notarize

```bash
export DEVELOPMENT_TEAM=$(sed -n 's/^<APP>_DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig)
scripts/release.sh "$V" "$B"
spctl -a -t open --context context:primary-signature -v "build/<App>-$V.dmg"   # "accepted"
```

### 5.4 GitHub Release

```bash
git tag "v$V" && git push origin "v$V"
gh release create "v$V" "build/<App>-$V.dmg" --title "<App> $V" --notes "What changed."
```

The tag **must** be `v<version>` and the asset **must** be `<App>-<version>.dmg`, or the cask URL 404s.

### 5.5 Update the cask

```bash
shasum -a 256 "build/<App>-$V.dmg"
```

Set `version` and `sha256` in `Casks/<app>.rb`, then commit and push to `main`. From that moment, `brew upgrade` delivers the release.

### 5.6 Verify

First release (fresh install):

```bash
brew untap <owner>/<app> 2>/dev/null
brew tap <owner>/<app> https://github.com/<owner>/<repo>
brew install --cask <owner>/<app>/<app>
brew audit --cask --strict <owner>/<app>/<app>
open -a <App>                                  # no Gatekeeper warning
```

Later releases (upgrade path, with the previous version installed):

```bash
brew update && brew upgrade --cask <app>
```

---

## Phase 6: What users run

```bash
brew tap <owner>/<app> https://github.com/<owner>/<repo>
brew install --cask <owner>/<app>/<app>
```

Then `brew upgrade` forever after.

Why the long form:

- **The tap needs the URL** because the repo isn't named `homebrew-<something>`. The tap name `<owner>/<app>` is arbitrary but must be used consistently.
- **The install needs the fully qualified name.** Homebrew 7 refuses casks from untrusted third-party taps. Installing by `<owner>/<app>/<app>` trusts it automatically. A bare `brew install --cask <app>` fails with `Refusing to load cask … from untrusted tap`. (Alternative: `brew trust <owner>/<app>` once.)

Put these two lines in the README.

---

## Gotchas learned the hard way

| Symptom | Cause / fix |
| --- | --- |
| `No Keychain password item found for profile` | Notary profile missing on this Mac, or revoked by an Apple ID password change. Redo 1.3. |
| Archive/export signing error | Developer ID cert missing/expired, or `DEVELOPMENT_TEAM` empty. Check 1.2 and 2.1. |
| Notarization "Invalid" | `xcrun notarytool log <submission-id> --keychain-profile <profile>`. Usually hardened runtime off or an unsigned nested binary (embedded helper, framework, CLI tool). |
| Notarization rejected for agreements | Membership lapsed, or a new agreement needs accepting at developer.apple.com. |
| `brew install` SHA mismatch | `sha256` computed from a different DMG than the uploaded one. Recompute from the Release asset. |
| `brew install` 404 | Tag isn't `v<version>` or DMG name doesn't match the cask URL. |
| `Refusing to load cask … from untrusted tap` | Install by the fully qualified name. |
| `brew upgrade` doesn't see the release | Cask commit not pushed to the default branch, or run `brew update`. |
| Gatekeeper warning on first launch | DMG not notarized or not stapled. Check `xcrun stapler validate`. |
| UI tests hang ~60 s at start | A copy of the app is already running. Quit it. |

---

## Optional later

- **Sparkle** for in-app updates. Add the Swift package, generate an EdDSA key once (`generate_keys`, back it up; losing it strands existing installs), put `SUFeedURL` + `SUPublicEDKey` in a partial `Info.plist`, host `appcast.xml` in the repo (raw.githubusercontent URL), and per release run `sign_update` on the DMG and add an appcast item. Then add `auto_updates true` to the cask. Safe to add after launch: brew users get the Sparkle build through `brew upgrade`.
- **Official `homebrew/cask`.** Once the app has real traction (stars, forks, watchers; a higher bar for self-submitted apps), PR the cask upstream so users can run plain `brew install --cask <app>`. Then delete `Casks/` from your repo.
- **Automate 5.4–5.5** in `release.sh`: `gh release create`, then rewrite `version`/`sha256` in the cask with `sed`, then commit.
