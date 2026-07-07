# Tagged for Windows (TaggdWin)

A Windows port of the Tagged time tracker, built as a **system-tray app** in
**WPF (.NET 8, C#)** — the Windows equivalent of the macOS menu-bar app.

- The tray icon (bottom-right, near the clock) replaces the macOS status-bar icon.
- **Left-click** the tray icon → a popup with the timer, description, tags, and
  Start / Pause / Resume / Stop — same dark styling and Roboto Mono type.
- **Right-click** the tray icon → a menu with **Settings…** and **Quit Tagged**.
- The **gear** and **power** buttons in the popup open Settings and quit.
- **Settings** opens a normal window (it shows in the taskbar — the Windows
  analog of the macOS Dock icon): server URL + API token, Confirm-before-stop,
  Launch-at-Login, tag manager, and updates.
- **Auto-updates** come from GitHub Releases via **Velopack** — the Windows
  analog of Sparkle.

Everything is stored in `%APPDATA%\Tagged\` (`settings.json`, `tags.json`).

---

## 1. Install the tools (one time)

You need **Visual Studio 2022** (the free **Community** edition is fine),
version 17.8 or newer.

1. Download from <https://visualstudio.microsoft.com/downloads/>.
2. Run the installer. On the **Workloads** screen, tick:
   - **.NET desktop development**  ← this is the important one (it includes WPF
     and the .NET 8 SDK).
3. Finish the install.

> Prefer the command line only? Install just the **.NET 8 SDK** from
> <https://dotnet.microsoft.com/download/dotnet/8.0> and skip Visual Studio.

---

## 2. Get the code onto the Windows machine

Copy the whole project folder over (USB drive, network share, or `git clone` if
you put it in a repo). You need at least these two items at the top level:

```
TaggdWin.sln
TaggdWin\        (the folder with all the code)
```

---

## 3. Open and run it

1. Double-click **`TaggdWin.sln`** — it opens in Visual Studio.
2. Visual Studio restores the NuGet packages automatically the first time
   (you'll see "Restore" activity in the status bar). Wait for it to finish.
3. Press **F5** (or the green ▶ **Start** button) to build and run.

There is **no main window** — that's expected. Look at the **system tray** in
the bottom-right corner of the taskbar (you may need to click the **^** arrow to
show hidden icons). You'll see the gold **Tagged** icon.

- **Left-click** it → the timer popup appears.
- **Right-click** it → Settings / Quit menu.

To stop debugging, press the red ■ **Stop** button in Visual Studio, or choose
**Quit Tagged** from the tray menu.

> Command-line alternative (from the folder containing `TaggdWin.sln`):
> ```
> dotnet run --project TaggdWin
> ```

---

## 4. What to test

- **Timer:** Start → the numbers turn gold and count up. Pause / Resume / Stop.
- **Description + tags:** type a description; click **+ Add** to pick a tag or
  create a new one; click a tag chip to remove it.
- **Popup dismiss:** click anywhere outside the popup — it hides (like the macOS
  popover). Click the tray icon again to reopen.
- **Settings window:** click the gear. It opens as a separate window with a
  taskbar entry. Toggle **Launch at Login**, **Confirm Before Stop**.
- **Tag manager:** Settings → **Manage Tags** → add / rename / reorder (▲▼) /
  delete. **‹ Settings** goes back.
- **TimeTagger sync (optional):** in Settings enter your server URL + API token,
  click **Test Connection**. When configured, stopping a session uploads the
  time; a "Saved" / "Not saved" toast appears in the popup.
- **Confirm Before Stop:** with it on, Stop asks for confirmation first.

### TimeTagger sync details
Enter the install root as the **Server URL** (e.g. `https://timetagger.example.com`;
for a sub-path install use `https://host/timetagger`). Create the **API token**
in TimeTagger under **Account → API token**. This is identical to the macOS app
and the two share the same server.

---

## 5. Packaging a real release with updates (Velopack)

The in-app **Check for Updates…** only does something when the app is running
from a **Velopack install** (not from Visual Studio / `dotnet run`). Here's how
to produce that install and wire it to GitHub Releases so Sparkle-style
auto-updates work.

**One-time:** install the Velopack CLI.
```
dotnet tool install -g vpk
```

**Each release** (run in a *Developer Command Prompt* / PowerShell on Windows,
from the folder with `TaggdWin.sln`):

```powershell
# 1) Publish a self-contained build (bump the version each release).
dotnet publish TaggdWin\TaggdWin.csproj -c Release -r win-x64 --self-contained true -o publish

# 2) Package it into an installer + update feed.
vpk pack --packId Tagged --packVersion 1.0.0 --packDir publish --mainExe Tagged.exe --packTitle Tagged

# -> creates a "Releases" folder containing Setup.exe, the update packages,
#    and a RELEASES manifest.

# 3) Publish those assets to a GitHub Release.
vpk upload github --repoUrl https://github.com/akandor/Tagged --publish `
    --releaseName "Tagged 1.0.0" --tag v1.0.0 --token <YOUR_GITHUB_TOKEN>
```

- Give people **`Setup.exe`** from the `Releases` folder to install the app.
- For the **next** version, bump `--packVersion` (and the `<Version>` in the
  `.csproj`), repeat the three commands. Installed apps will find the new
  GitHub Release and update themselves. The feed URL is already wired in
  `Services/UpdaterService.cs` (`https://github.com/akandor/Tagged`).

### Code signing (recommended for distribution)
Velopack's Windows security model is **Authenticode code signing** (the analog
of Sparkle's EdDSA key). Without a signature, Windows SmartScreen will warn
users on first run. If you have a code-signing certificate, pass it to `vpk`:
```
vpk pack ... --signParams "/a /fd sha256 /td sha256 /tr http://timestamp.digicert.com"
```
For testing on your own machine you can skip signing entirely.

---

## Notes & limitations

- **Where the tray icon lives:** Windows often hides new tray icons behind the
  **^** overflow arrow. Drag it onto the visible taskbar to pin it.
- **Launch at Login** uses the per-user `Run` registry key and points at the
  currently running `Tagged.exe`. For the login item to survive, enable it from
  the **installed** build (step 5), not the Visual Studio output.
- **Updates require an installed build** (see step 5). From Visual Studio,
  "Check for Updates…" will just say updates apply to installed builds only —
  that's expected.
- **Popup position** anchors to the bottom-right of the primary monitor's work
  area. On multi-monitor setups it appears on the primary display.
- This project was authored on macOS and cross-compiles cleanly, but has not
  been run on Windows yet — please report anything visual that looks off and
  it's an easy fix.
```
