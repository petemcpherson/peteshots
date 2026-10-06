# Deploy: public release + Homebrew install

Goal: anyone can install Peteshots with one command, like Vorssaint:

```sh
brew install --cask petemcpherson/tap/peteshots
```

…or download a DMG from the GitHub Releases page.

## How Vorssaint does it (and what we copy)

Vorssaint's pipeline:

1. Build the `.app`, signed with a **Developer ID Application** certificate.
2. **Notarize** it with Apple (`xcrun notarytool`) and **staple** the ticket.
3. Package it in a DMG (`Vorssaint-<version>.dmg`), then notarize and staple the DMG too.
4. Upload the DMG to a **GitHub Release** tagged `v<version>`.
5. A Homebrew **cask** (a small Ruby file) points to that release URL with a `sha256`.

One difference: Vorssaint's cask lives in the **official** `homebrew/cask` repo, which is why their command is just `brew install --cask vorssaint`. Homebrew only accepts popular apps there (it checks GitHub stars, forks, and watchers). Peteshots has 0 stars today, so it would be rejected.

The fix is a **personal tap**: your own GitHub repo named `homebrew-tap`. It works the same way. The only cost is a slightly longer install command. Move to the official repo later (Step 10) once Peteshots is popular enough.

Also: Homebrew now refuses casks for apps that fail Gatekeeper. The app must be signed and notarized. Unsigned builds are not an option.

## What you already have

- Public repo: `github.com/petemcpherson/peteshots`
- **Developer ID Application: Peter McPherson (A2T9Q78M27)** certificate, already in your keychain
- Hardened Runtime on, App Sandbox off (fine for Developer ID distribution)
- MIT license, README
- No network code, so there is no in-app updater. Homebrew handles updates (`brew upgrade`).

---

## Step 1 — Prepare the app for release

1. **Rename the built app (recommended).** Today `PRODUCT_NAME = $(TARGET_NAME)`, so the app is `peteshots.app` (lowercase). In Xcode, set the target's **Product Name** to `Peteshots` so users see `Peteshots.app` in `/Applications`.
   - Note: the bundle ID stays `com.peteshots.peteshots`. Do not change it after the first release, or users lose their Screen Recording permission and settings.
2. **Set the version.** In the target's General tab, set **Version** (`MARKETING_VERSION`) to `1.0.0` and **Build** (`CURRENT_PROJECT_VERSION`) to `1`. Raise both on every release.
3. **Check the minimum macOS version.** It is currently `26.2`, so users on macOS 15 and older cannot install. Lower it only if the code supports older systems. Whatever you choose goes into the cask in Step 6.
4. **App icon.** Make sure `AppIcon.appiconset` has real artwork. It shows in Finder, the DMG, and Homebrew listings.
5. **Commit everything.** Releases must come from a clean `main`.

## Step 2 — One-time Apple notarization setup

Notarization needs credentials stored in your keychain. Pick one option.

**Option A — App-specific password (simplest)**

1. Go to [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords. Create one named `notarytool`.
2. Run this once, then paste the password when asked:

   ```sh
   xcrun notarytool store-credentials "peteshots-notary" \
     --apple-id "pnm326@gmail.com" \
     --team-id "A2T9Q78M27"
   ```

**Option B — App Store Connect API key (needed later for CI, Step 9)**

1. App Store Connect → Users and Access → Integrations → App Store Connect API → generate a key with **Developer** access. Download the `.p8` file (one download only).
2. Run once:

   ```sh
   xcrun notarytool store-credentials "peteshots-notary" \
     --key ~/path/AuthKey_XXXXXX.p8 --key-id XXXXXX --issuer <issuer-uuid>
   ```

Both options store a keychain profile named `peteshots-notary`. The release script uses that name.

## Step 3 — Add a release script to this repo

Create `scripts/release.sh` (Claude can write this). It must do the following, in order:

1. Read the version from the project (`MARKETING_VERSION`).
2. Archive a Release build:
   `xcodebuild -project peteshots.xcodeproj -scheme peteshots -configuration Release -archivePath build/Peteshots.xcarchive archive`
3. Export with Developer ID signing, using an `scripts/ExportOptions.plist` with `method = developer-id`, `teamID = A2T9Q78M27`, `signingStyle = automatic`:
   `xcodebuild -exportArchive -archivePath build/Peteshots.xcarchive -exportPath build/export -exportOptionsPlist scripts/ExportOptions.plist`
4. Verify the signature: `codesign --verify --deep --strict --verbose=2 build/export/Peteshots.app`
5. Zip the app and notarize it, then staple the ticket to the `.app`:
   `xcrun notarytool submit <zip> --keychain-profile peteshots-notary --wait`
   `xcrun stapler staple build/export/Peteshots.app`
6. Build the DMG with the app plus an `Applications` shortcut (`hdiutil create -volname Peteshots -srcfolder <staging> -format UDZO dist/Peteshots-<version>.dmg`). A styled background like Vorssaint's is optional.
7. Sign, notarize, and staple the DMG:
   `codesign --sign "Developer ID Application: Peter McPherson (A2T9Q78M27)" dist/Peteshots-<version>.dmg`
   `xcrun notarytool submit dist/Peteshots-<version>.dmg --keychain-profile peteshots-notary --wait`
   `xcrun stapler staple dist/Peteshots-<version>.dmg`
8. Check Gatekeeper accepts it: `spctl -a -vvv -t install dist/Peteshots-<version>.dmg` (expect `accepted` and `source=Notarized Developer ID`).
9. Print the SHA-256 for the cask: `shasum -a 256 dist/Peteshots-<version>.dmg`

Add `build/` and `dist/` to `.gitignore`.

If notarization fails, see the log:
`xcrun notarytool log <submission-id> --keychain-profile peteshots-notary`

## Step 4 — Test the build like a stranger would

1. Copy the DMG to another Mac, or a new user account. AirDrop or a download both set the quarantine flag, which is the real test.
2. Open the DMG, drag Peteshots to Applications, launch it.
3. Expected: no "unidentified developer" warning, only the normal "downloaded from the internet" prompt.
4. Do a capture and save, and check launch at login. Use the Phase 8 checklist in `context/user-todo.md`.

## Step 5 — Publish the GitHub Release

1. Tag the release commit and push:

   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. Create the release and upload the DMG:

   ```sh
   gh release create v1.0.0 dist/Peteshots-1.0.0.dmg \
     --title "Peteshots 1.0.0" --notes "First public release."
   ```

3. The download URL is now:
   `https://github.com/petemcpherson/peteshots/releases/download/v1.0.0/Peteshots-1.0.0.dmg`

Keep this naming pattern (`v<version>` tag, `Peteshots-<version>.dmg` file) on every release. The cask builds the URL from it.

## Step 6 — Create your Homebrew tap

1. Create a new **public** GitHub repo named exactly `homebrew-tap`:

   ```sh
   gh repo create petemcpherson/homebrew-tap --public \
     --description "Homebrew tap for Peteshots"
   ```

   Homebrew maps `petemcpherson/tap` to `github.com/petemcpherson/homebrew-tap`. The `homebrew-` prefix is required.

2. In that repo, add `Casks/peteshots.rb`:

   ```ruby
   cask "peteshots" do
     version "1.0.0"
     sha256 "<sha256 from Step 3>"

     url "https://github.com/petemcpherson/peteshots/releases/download/v#{version}/Peteshots-#{version}.dmg"
     name "Peteshots"
     desc "Menu bar screenshot tool with arrows, blur, text and crop"
     homepage "https://github.com/petemcpherson/peteshots"

     livecheck do
       url :url
       strategy :github_latest
     end

     depends_on macos: ">= :tahoe"

     app "Peteshots.app"

     uninstall quit:       "com.peteshots.peteshots",
               login_item: "Peteshots"

     zap trash: [
       "~/Library/Preferences/com.peteshots.peteshots.plist",
       "~/Library/Saved Application State/com.peteshots.peteshots.savedState",
     ]
   end
   ```

   Notes:
   - `depends_on macos:` must match Step 1.3. `:tahoe` is macOS 26. Homebrew cannot require a point release such as 26.2.
   - No `auto_updates true`, because Peteshots has no updater. That way `brew upgrade` updates it.
   - No `depends_on arch:`, because Release archives are Universal by default (Intel + Apple Silicon). Confirm with `lipo -archs Peteshots.app/Contents/MacOS/Peteshots`. If it prints only `arm64`, add `depends_on arch: :arm64`.
   - `zap` lists files that `brew uninstall --zap` deletes. Before the first release, find the real files with `ls ~/Library/*/ | grep -i peteshots` and add any extras, such as a Caches folder.

3. Lint and test locally:

   ```sh
   brew tap petemcpherson/tap
   brew audit --cask --strict --online petemcpherson/tap/peteshots
   brew style petemcpherson/tap/peteshots
   brew install --cask petemcpherson/tap/peteshots
   brew uninstall --cask petemcpherson/tap/peteshots
   ```

4. Commit and push the cask.

Users can now install with either:

```sh
brew install --cask petemcpherson/tap/peteshots
# or
brew tap petemcpherson/tap
brew install --cask peteshots
```

## Step 7 — Update the README

Put a user-facing **Install** section above the "Build" section, like Vorssaint's:

````md
## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask petemcpherson/tap/peteshots
```

Or download the DMG from the [releases page](https://github.com/petemcpherson/peteshots/releases) and drag Peteshots into Applications.

Builds are signed with an Apple Developer ID and notarized.

## Uninstall

```sh
brew uninstall --cask peteshots          # app only
brew uninstall --zap --cask peteshots    # app + settings
```
````

Also:

- Keep the build-from-source steps under a "Build it yourself" heading.
- Add a screenshot or GIF near the top. It sells the app more than text.
- Optional badges: latest release, downloads, macOS version.
- Add a `CHANGELOG.md` and update it each release.

## Step 8 — Checklist for every new release

1. Raise **Version** and **Build** in Xcode. Add a `CHANGELOG.md` entry. Commit to `main`.
2. Run `scripts/release.sh`. Note the SHA-256.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`
4. `gh release create vX.Y.Z dist/Peteshots-X.Y.Z.dmg --title "Peteshots X.Y.Z" --notes-file <notes>`
5. In `homebrew-tap`, update `version` and `sha256` in `Casks/peteshots.rb`, then commit and push.
6. Check: `brew update && brew upgrade --cask peteshots`

## Step 9 — Optional: automate with GitHub Actions

Vorssaint runs Steps 2–5 on GitHub Actions whenever a `v*` tag is pushed. Do this only after the manual flow works.

1. Export the Developer ID certificate and its private key from Keychain Access as a `.p12` file with a password.
2. Add these repo secrets (Settings → Secrets and variables → Actions):
   - `SIGNING_CERT_P12` — `base64 -i cert.p12 | pbcopy`
   - `SIGNING_CERT_PASSWORD`
   - `NOTARY_API_KEY_P8` — base64 of the `.p8` from Step 2 Option B
   - `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`
3. Add `.github/workflows/release.yml`. On a `v*` tag it runs on `macos-26`, imports the certificate into a temporary keychain, runs `scripts/release.sh`, and uploads the DMG with `gh release create`. Vorssaint's `Tools/ci-setup-signing.sh` and `Tools/notarize.sh` are good templates.
4. Add a final job that updates the cask automatically. It needs a fine-grained token with write access to `homebrew-tap`, stored as secret `TAP_GITHUB_TOKEN`. The job edits `version` and `sha256` and pushes. Then a release is only: bump version, commit, push tag.
5. Security: put signing secrets in a protected GitHub **Environment** that needs your approval. Run the workflow only for tags you push. Vorssaint's workflow shows both.

## Step 10 — Later: move to the official Homebrew repo

When Peteshots is popular enough, submit it to `Homebrew/homebrew-cask`. Users can then run `brew install --cask peteshots` with no tap.

1. Read Homebrew's "Acceptable Casks" docs for the current popularity rules. Rules are stricter when the author submits their own app (a few hundred stars at the time of writing).
2. Fork `Homebrew/homebrew-cask` and add the same cask at `Casks/p/peteshots.rb`.
3. Run `brew audit --new --cask peteshots` and `brew style --fix`, then open a PR.
4. After the merge, Homebrew's autobump bot usually picks up new GitHub releases on its own.
5. Update the README install command. In the tap, keep the cask for a while or replace it with a note that points to the official cask.

---

## Quick reference

| Thing | Value |
|---|---|
| Bundle ID | `com.peteshots.peteshots` (never change) |
| Team ID | `A2T9Q78M27` |
| Signing identity | `Developer ID Application: Peter McPherson (A2T9Q78M27)` |
| Notary profile | `peteshots-notary` |
| Tag format | `v1.0.0` |
| Asset name | `Peteshots-1.0.0.dmg` |
| Tap repo | `github.com/petemcpherson/homebrew-tap` |
| Install command | `brew install --cask petemcpherson/tap/peteshots` |
