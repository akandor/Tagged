# Sparkle Auto-Updates via GitHub Releases — Integration Template

A copy-paste-able recipe for adding [Sparkle](https://sparkle-project.org)
auto-updates to a **macOS SwiftUI app**, distributed through **GitHub Releases**,
where a **GitHub Action generates and signs the appcast** every time you publish a
release.

This is written to be reused across projects and handed to coding agents. Replace
the placeholders throughout:

| Placeholder | Meaning | Example |
| --- | --- | --- |
| `<OWNER>` | GitHub org/user | `akandor` |
| `<REPO>` | GitHub repo name | `UpturtleMon` |
| `<AppName>` | Xcode target / product name | `UpturtleMon` |
| `<bundle-id>` | `PRODUCT_BUNDLE_IDENTIFIER` | `com.toepper.rocks.UpturtleMon` |

> Assumptions this template is built on (change with care):
> - The app is **sandboxed** (`com.apple.security.app-sandbox`) and hardened-runtime.
> - The app already has the **outgoing network** entitlement
>   (`com.apple.security.network.client`) — so Sparkle downloads in-process and the
>   Downloader XPC service is **not** needed.
> - The Xcode project uses `GENERATE_INFOPLIST_FILE = YES` (no hand-maintained
>   Info.plist). Modern Xcode (objectVersion 77 / file-system-synchronized groups).
> - You build/notarize **locally** and upload the zipped `.app` to a GitHub Release.
>   CI only generates the appcast — it does not build or notarize.

---

## How it fits together (the mental model)

```
                        ┌──────────────────────────────────────────┐
   You (local Mac)      │  GitHub                                   │
 ┌───────────────┐      │                                          │
 │ Archive app   │      │  Release "1.1"                            │
 │ Developer-ID  │      │   ├── <AppName>-1.1.zip   (you upload)    │
 │ sign+notarize │─────►│   └── appcast.xml         (Action makes)  │
 │ ditto → .zip  │      │            ▲                              │
 └───────────────┘      │            │ generate_appcast + EdDSA sign│
                        │   GitHub Action (.github/workflows)       │
                        └────────────┬─────────────────────────────┘
                                     │  SUFeedURL =
                                     │  .../releases/latest/download/appcast.xml
                                     ▼
                        ┌──────────────────────────────────────────┐
                        │ Installed app → Sparkle checks feed,      │
                        │ verifies EdDSA signature, installs update │
                        └──────────────────────────────────────────┘
```

The trick that makes it "just work": the app's feed URL points at
`https://github.com/<OWNER>/<REPO>/releases/latest/download/appcast.xml`. GitHub
always resolves `releases/latest/download/<asset>` to the newest **non-prerelease**
release's asset. So as long as the Action attaches a fresh `appcast.xml` to each
release, every installed copy is served the newest appcast with **no separate
hosting** (no GitHub Pages, no server).

**Security model:** distribution trust comes from two independent things —
(1) the app is Developer-ID **notarized**, and (2) each update's archive is signed
with your **EdDSA private key**, which Sparkle verifies against the **public key**
baked into the app's Info.plist. A compromised GitHub release alone cannot push a
malicious update without the EdDSA private key.

---

## Part 1 — One-time Xcode / project changes

There are four edits: add the package, entitlements, Info.plist keys, and code.

### 1.1 Add the Sparkle Swift package

In Xcode: **File → Add Package Dependencies…** →
`https://github.com/sparkle-project/Sparkle` → **Up to Next Major**, minimum
`2.6.0` → add the **Sparkle** library to your app target.

<details>
<summary>Doing it by hand in <code>project.pbxproj</code> (for agents editing without Xcode)</summary>

Use unique 24-hex-char object IDs (shown here as `AABB…A1/A2/A3`). Five edits:

1. A `PBXBuildFile` in a `PBXBuildFile` section:
   ```
   AABB010000000000000000A3 /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = AABB010000000000000000A2 /* Sparkle */; };
   ```
2. Add it to the target's `PBXFrameworksBuildPhase` `files = ( … );`.
3. Add the product dependency to the target's `packageProductDependencies = ( … );`:
   ```
   AABB010000000000000000A2 /* Sparkle */,
   ```
4. Add a `packageReferences = ( … );` array to the `PBXProject` object:
   ```
   AABB010000000000000000A1 /* XCRemoteSwiftPackageReference "Sparkle" */,
   ```
5. Add the two objects at file scope:
   ```
   /* Begin XCRemoteSwiftPackageReference section */
       AABB010000000000000000A1 /* XCRemoteSwiftPackageReference "Sparkle" */ = {
           isa = XCRemoteSwiftPackageReference;
           repositoryURL = "https://github.com/sparkle-project/Sparkle";
           requirement = { kind = upToNextMajorVersion; minimumVersion = 2.6.0; };
       };
   /* End XCRemoteSwiftPackageReference section */

   /* Begin XCSwiftPackageProductDependency section */
       AABB010000000000000000A2 /* Sparkle */ = {
           isa = XCSwiftPackageProductDependency;
           package = AABB010000000000000000A1 /* XCRemoteSwiftPackageReference "Sparkle" */;
           productName = Sparkle;
       };
   /* End XCSwiftPackageProductDependency section */
   ```
Then `xcodebuild -resolvePackageDependencies` to fetch it.
</details>

Sparkle's `Installer.xpc` / `Downloader.xpc` services are **inside**
`Sparkle.framework` and get embedded automatically when you link the SPM product —
you don't add them manually.

### 1.2 Entitlements (sandboxed apps only)

A sandboxed app must whitelist Sparkle's XPC mach services. Add to your
`.entitlements` (keep your existing `network.client`):

```xml
<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
<array>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
</array>
```

`$(PRODUCT_BUNDLE_IDENTIFIER)` is expanded at build time, so the same file works
for any bundle id. Verify after building:

```bash
codesign -d --entitlements - --xml "$APP" | plutil -p - | grep -A3 mach-lookup
# → "<bundle-id>-spks" and "<bundle-id>-spki"
```

> If your app is **not** sandboxed, skip this entirely — no entitlements needed.

### 1.3 Info.plist keys

Sparkle needs three keys. **Gotcha:** if you use `GENERATE_INFOPLIST_FILE = YES`,
you **cannot** add arbitrary keys via `INFOPLIST_KEY_*` build settings — Xcode only
injects its own known allowlist (`INFOPLIST_KEY_LSUIElement`, etc.) and silently
drops unknown ones like `SUFeedURL`. (This bites everyone; verify with
`PlistBuddy -c "Print :SUFeedURL"` on the built app — it'll say *Does Not Exist*.)

The clean fix: keep generation on **and** add a small partial `Info.plist` that
Xcode merges into the generated one.

1. Create `Info.plist` at the **repo root** (NOT inside a file-system-synchronized
   source group, or Xcode will also try to copy it as a bundle resource and you'll
   get "Multiple commands produce Info.plist"):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>SUFeedURL</key>
       <string>https://github.com/<OWNER>/<REPO>/releases/latest/download/appcast.xml</string>
       <key>SUPublicEDKey</key>
       <string>REPLACE_WITH_YOUR_SPARKLE_EDDSA_PUBLIC_KEY</string>
       <key>SUEnableInstallerLauncherService</key>
       <true/>
   </dict>
   </plist>
   ```

2. In **both** Debug and Release build configs of the target, keep
   `GENERATE_INFOPLIST_FILE = YES` and add:
   ```
   INFOPLIST_FILE = Info.plist;
   ```

| Key | Purpose |
| --- | --- |
| `SUFeedURL` | Where the app fetches the appcast. Uses the `releases/latest/download/…` trick. |
| `SUPublicEDKey` | Your EdDSA **public** key (Part 2). Until real, updates fail verification **by design**. |
| `SUEnableInstallerLauncherService` | **Required for sandboxed apps.** Enables the Installer XPC. Omit if not sandboxed. |

Verify the merge worked (both Sparkle keys **and** generated keys present):

```bash
APP=path/to/Built/<AppName>.app
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist"
```

### 1.4 Code — the updater + a "Check for Updates…" control

Add one file. `SPUStandardUpdaterController(startingUpdater: true, …)` starts
background checks on Sparkle's own schedule; the button drives a manual check.

```swift
import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater so SwiftUI can trigger update checks and
/// reflect availability. Create once at app launch. Feed URL + public key are
/// read from Info.plist (SUFeedURL / SUPublicEDKey).
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// Reusable "Check for Updates…" button (menu + settings).
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterViewModel
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
```

Wire it into the `App`. Note the `.commands` block adds a native menu item (visible
when a normal window is key — important for menu-bar / `LSUIElement` apps that have
no always-on app menu):

```swift
@main
struct <AppName>App: App {
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {                       // or MenuBarExtra { … }
            ContentView()
                .environmentObject(updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
        }
    }
}
```

Then drop `CheckForUpdatesButton(updater: updater)` anywhere else you want it
(e.g. an About/Settings screen) using `@EnvironmentObject var updater: UpdaterViewModel`.

---

## Part 2 — One-time signing-key setup

Sparkle signs updates with **EdDSA** (separate from Apple code-signing).

1. Download the Sparkle tools from the
   [Sparkle releases page](https://github.com/sparkle-project/Sparkle/releases)
   (`Sparkle-<version>.tar.xz`) and unpack. Tools are in `bin/`.

2. Generate the keypair (private key is stored in your login Keychain):
   ```bash
   ./bin/generate_keys
   ```
   It prints the **public** key (base64). Reprint anytime with
   `./bin/generate_keys -p`.

3. Paste the public key into `Info.plist` → `SUPublicEDKey` (replacing the
   placeholder). Ship at least one build with the correct key **before** relying on
   updates — older installs must already contain the matching public key.

4. Export the **private** key and store it as a GitHub Actions **secret** named
   `SPARKLE_PRIVATE_KEY` (repo → Settings → Secrets and variables → Actions):
   ```bash
   ./bin/generate_keys -x sparkle_private_key.txt
   # paste file contents into the SPARKLE_PRIVATE_KEY secret, then:
   rm sparkle_private_key.txt
   ```

---

## Part 3 — The GitHub Action (generates + signs the appcast)

Create `.github/workflows/appcast.yml`. On each **published release**, it:
downloads the release's `.zip`, runs `generate_appcast` (which computes the version
from the app bundle **and** EdDSA-signs the archive), and uploads the resulting
`appcast.xml` back onto the same release.

```yaml
name: Generate Sparkle appcast

on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: "Release tag to (re)generate the appcast for"
        required: true

permissions:
  contents: write

jobs:
  appcast:
    runs-on: macos-14
    env:
      SPARKLE_VERSION: 2.9.4          # pin to the version you tested with
      TAG: ${{ github.event.release.tag_name || inputs.tag }}
      GH_TOKEN: ${{ github.token }}
    steps:
      - name: Download Sparkle tools
        run: |
          set -euo pipefail
          curl -fsSL -o sparkle.tar.xz \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
          mkdir sparkle && tar -xf sparkle.tar.xz -C sparkle
          ./sparkle/bin/generate_appcast --help >/dev/null

      - name: Download release archive(s)
        run: |
          set -euo pipefail
          mkdir -p updates
          gh release download "$TAG" --repo "$GITHUB_REPOSITORY" --dir updates --pattern '*.zip'
          ls -la updates

      - name: Generate and sign appcast
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          printf '%s' "${SPARKLE_PRIVATE_KEY}" | ./sparkle/bin/generate_appcast \
            --ed-key-file - \
            --download-url-prefix "https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG}/" \
            --full-release-notes-url "https://github.com/${GITHUB_REPOSITORY}/releases" \
            -o appcast.xml \
            updates
          cat appcast.xml

      - name: Upload appcast to release
        run: gh release upload "$TAG" appcast.xml --repo "$GITHUB_REPOSITORY" --clobber
```

Why each flag matters:

| Flag | Why |
| --- | --- |
| `--ed-key-file -` | Reads the EdDSA private key from **stdin** (piped from the secret) — never touches disk or the runner Keychain. |
| `--download-url-prefix …/download/${TAG}/` | The enclosure URL each installed app downloads. Because each asset lives under **its own tag**, the prefix is the current release's tag. |
| `-o appcast.xml` | Output path (allowed because only one appcast is produced). |
| `updates` | Positional: the directory of archives to sign. Here it holds just this release's `.zip`. |
| `--clobber` | Overwrite any prior `appcast.xml` on the release when re-running. |

**Design note — single-item appcast.** Because each release's zip lives under its
own `/releases/download/<tag>/` URL, this workflow generates a **one-item** appcast
per release (just the newest version) and serves it via `releases/latest`. That's
simple and correct for "update to latest," but it means **no Sparkle delta updates**
and no historical version list. If you later want deltas, host **all** archives
under one stable URL prefix (e.g. GitHub Pages) and point both `SUFeedURL` and
`--download-url-prefix` there, downloading every past archive into `updates/` before
generating.

---

## Part 4 — Cutting a release (the repeatable checklist)

Sparkle requires updates to be **Developer-ID signed + notarized**, and to keep the
**same Developer-ID team** across versions (a Development-signed build won't update).

1. **Bump the version** (both matter — Sparkle compares `CFBundleVersion`):
   - `MARKETING_VERSION` → user-facing (e.g. `1.1`)
   - `CURRENT_PROJECT_VERSION` → must **strictly increase** every release
2. **Archive & export** Developer-ID: Xcode → Product → Archive → Distribute App →
   **Developer ID** → export.
3. **Notarize & staple:**
   ```bash
   xcrun notarytool submit <AppName>.zip --keychain-profile "NOTARY" --wait
   xcrun stapler staple <AppName>.app
   ```
4. **Zip for Sparkle** (preserves symlinks/metadata correctly — don't use Finder zip):
   ```bash
   ditto -c -k --sequesterRsrc --keepParent <AppName>.app <AppName>-1.1.zip
   ```
5. **Create the GitHub Release:** tag = version (`1.1`), attach `<AppName>-1.1.zip`,
   **Publish** (not draft/prerelease, so `releases/latest` picks it up).
6. The **appcast workflow** runs automatically → signed `appcast.xml` uploaded to the
   release. Installed apps update on their next check (or **Check for Updates…**).

Re-run manually: Actions → *Generate Sparkle appcast* → **Run workflow** → pass the tag.

---

## Verification checklist

- [ ] `xcodebuild … -resolvePackageDependencies` fetches Sparkle.
- [ ] Built app has `Contents/Frameworks/Sparkle.framework` with `XPCServices/Installer.xpc`.
- [ ] `PlistBuddy -c "Print :SUFeedURL"` on the built app returns your URL (merge worked).
- [ ] `codesign -d --entitlements -` shows `-spks` / `-spki` mach-lookup (sandboxed apps).
- [ ] First shipped build contains the **real** `SUPublicEDKey`.
- [ ] `SPARKLE_PRIVATE_KEY` secret exists in the repo.
- [ ] After a test release, `https://github.com/<OWNER>/<REPO>/releases/latest/download/appcast.xml` returns a signed appcast.

## Common failure modes

| Symptom | Cause / fix |
| --- | --- |
| `SUFeedURL` missing from built Info.plist | Used `INFOPLIST_KEY_SUFeedURL` — Xcode drops custom keys. Use a merged partial `Info.plist` (§1.3). |
| "Multiple commands produce Info.plist" | Partial `Info.plist` is inside a source/synchronized group. Move it to repo root. |
| Update check fails signature verification | `SUPublicEDKey` is the placeholder, or the installed app predates the key. Public key must ship *before* signed updates. |
| Sandboxed update silently does nothing | Missing `SUEnableInstallerLauncherService` and/or the `-spks`/`-spki` mach-lookup entitlements. |
| "will damage your computer" / won't update | Update build isn't notarized, or changed Developer-ID team vs. the installed version. |
| Action can't sign | `SPARKLE_PRIVATE_KEY` secret missing/malformed, or `--ed-key-file -` not receiving it via stdin. |
```
