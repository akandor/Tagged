<div align="center">

# Tagged

**A fast, privacy‑friendly [TimeTagger](https://timetagger.app) client for iPhone, Mac, and Windows.**

Track your work, study sessions, client projects, or daily routines with a single tap — using
flexible tags instead of rigid projects, and syncing to your own self‑hosted TimeTagger backend.

</div>

---

## What it is

Tagged is a companion app for [TimeTagger](https://github.com/almarklein/timetagger), the
open‑source time tracker. It brings TimeTagger's tag‑based workflow to native apps with a
shared dark theme, a gold accent, and Roboto Mono type across every platform:

| Platform | Target | Form factor | Tech |
| --- | --- | --- | --- |
| iOS / iPadOS | `Taggd` | Full‑screen app + Live Activity widget | SwiftUI |
| macOS | `TaggdMac` | Menu‑bar app with a settings window | SwiftUI + [Sparkle](https://sparkle-project.org) |
| Windows | `TaggdWin` | System‑tray app | WPF (.NET 8) + [Velopack](https://velopack.io) |

The Apple targets share their model, networking, and design code (`Taggd/Models.swift`,
`TimeTaggerClient.swift`, `TagStore.swift`, `Theme.swift`, …); the Windows app is an
independent port that mirrors the same behavior and styling.

## Features

- **Tag‑based tracking** — categorize time with lightweight tags instead of fixed projects.
- **One‑tap timer** — start, pause, resume, and stop with a live elapsed display.
- **Sync to your own server** — connect a self‑hosted TimeTagger backend with a URL and API token; stopped sessions upload automatically with a saved / not‑saved toast.
- **Offline‑friendly** — track locally and sync when reachable.
- **Live Activity (iOS)** — running timer on the Lock Screen and Dynamic Island.
- **Menu‑bar / tray native feel** — quick popover on macOS and Windows, with a full settings window.
- **Tag manager** — add, rename, reorder, and delete your tag library.
- **Auto‑updates** — Sparkle on macOS, Velopack on Windows, both delivered from GitHub Releases.
- **Privacy‑first** — no cookies, no analytics, no third‑party services. Your data lives on your device and your server.

## Requirements

- **iOS / iPadOS 26.5+** — Xcode 26+, an Apple developer account for device installs.
- **macOS 14 (Sonoma)+** — Xcode 26+.
- **Windows 10/11** — Visual Studio 2022 (17.8+) with the *.NET desktop development* workload, or the .NET 8 SDK.

## Building

### Apple (iOS & macOS)

The iOS app builds from `Taggd.xcodeproj`. The macOS project is generated from
`project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
# Regenerate the macOS project after editing project.yml (optional; the
# generated TaggdMac.xcodeproj is committed).
brew install xcodegen
xcodegen generate

# Build the menu-bar app.
xcodebuild -project TaggdMac.xcodeproj -scheme TaggdMac -configuration Debug build
```

Open either `.xcodeproj` in Xcode and press **Run** to launch on a simulator, device, or your Mac.

### Windows

See [`TaggdWin/README.md`](TaggdWin/README.md) for the full walkthrough (Visual Studio setup,
running from the tray, and packaging releases with Velopack). In short:

```bash
dotnet run --project TaggdWin
```

## Connecting to TimeTagger

1. Open **Settings** in the app.
2. Enter your **Server URL** — the TimeTagger install root, e.g. `https://timetagger.example.com`
   (for a sub‑path install, `https://host/timetagger`).
3. Create an **API token** in TimeTagger under **Account → API token** and paste it in.
4. Tap **Test Connection**. Once connected, stopping a session uploads the tracked time.

All platforms use the same protocol and can share a single server.

## Project layout

```
Taggd/           iOS app + shared cross-platform Swift sources
TaggdMac/        macOS menu-bar app (SwiftUI, Sparkle)
TaggdWidget/     iOS Live Activity / widget
TaggdWin/        Windows tray app (WPF, .NET 8, Velopack)
Shared/          Sources shared between the app and the widget
project.yml      XcodeGen spec for the macOS target
```

## Releases & auto‑updates

- **macOS** ships via Sparkle from GitHub Releases, verified with an EdDSA signature. The feed
  (`appcast.xml`) and public key are configured in `project.yml`.
- **Windows** ships via Velopack from the same GitHub Releases. See the packaging steps in
  [`TaggdWin/README.md`](TaggdWin/README.md).

## License

© Toepper.Rocks. See repository for details.
