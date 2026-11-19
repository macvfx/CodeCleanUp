# Code Project Backup

A macOS menu bar app that mirrors [`find_xcode_projects_cleanup.sh`](https://github.com/macvfx/find)
(the original shell script): it scans a folder for Xcode projects/workspaces,
estimates recoverable space, optionally runs `xcodebuild clean`, removes matching
`DerivedData`, and creates a password-protected zip archive — now on a schedule,
with no terminal needed.

> **Repo name:** this project lives in the `CodeCleanUp` repository — the name
> reflects what it does: clean the unneeded code cruft (`.build`, `DerivedData`,
> caches, build products) before backing up your project files with the
> Code Project Backup app.

## Features

- **Menu bar app** — lives in the status bar, no Dock icon (`LSUIElement`)
- **Scan** for `.xcodeproj` / `.xcworkspace`, detect shared schemes via `xcodebuild -list`
- **Estimate** recoverable `.build` + `DerivedData` space before cleaning
- **Cleanup** — `xcodebuild clean` on detected schemes + remove matching `DerivedData` folders
- **Build folder removal** (off by default) — deletes `.build` and Xcode build-output
  folders under the search root. They are found by content (`Build/Products`,
  `CompilationCache.noindex`, …), not by name. Folders with git-tracked files or
  changed in the last hour are kept. **Preview Build Cleanup** in the menu lists
  them first and deletes nothing.
- **Archive** — skips the exact build trees the scan found, plus credential files when
  the archive is unencrypted (or always, if set). Password-protected (or unencrypted) `zip` with the same cache/build
  excludes as the script (`.build`, `DerivedData`, `Pods`, `Carthage/Build`,
  `.swiftpm`, `SourcePackages`, `node_modules`, `.DS_Store`, `__MACOSX`, `.app`,
  `.dSYM`, build products/intermediates, Archiware P5 container blocks `*.p5b`, …)
- **Password modes**
  - `Keychain` — saves to (and reads) the `zip_password` Keychain item, the same
    account name the shell script uses. Create it via **Save to Keychain** in
    Settings, or with `security add-generic-password -s CodeProjectBackup -a zip_password -w <password>`
  - `Custom` — a separate app-only password stored under the `custom_password`
    Keychain item, for when you want a different password than `zip_password`
  - `None` — unencrypted archive
- **Scheduled runs** — hourly, daily, or weekly. Checks every minute; missed runs
  are caught up after launch/wake. Scheduled runs use the Keychain/Custom password,
  never prompt.
- **Reports** — timestamped `alias_folder_YYYY-MM-DD_HH-MM-SS.txt` and `.csv` in
  the report directory (default `~/Desktop`); optional alias and search-root
  folder name are included in the filename

## Settings

Open Settings from the menu bar icon. All settings persist in `UserDefaults`.

| Setting | Default | Notes |
|---|---|---|
| Search root | `~/My Coding Projects` | folder to scan/back up |
| Report directory | `~/Desktop` | where `.txt`/`.csv` reports go |
| Run `xcodebuild clean` | on | |
| Remove DerivedData | on | |
| Create zip archive | on | |
| Archive path | `~/Downloads` | folder or full file path; empty = Downloads |
| Password mode | Keychain | |
| Schedule | Manual | Manual / Hourly / Daily / Weekly; one "Run at" time that follows the Mac's 12 or 24-hour setting |
| Remove build folders | off | preview first |
| Archive exclusions | 28 patterns | editable, one per line |
| Pruned scan paths | `~/Library /System /Volumes /private /usr /opt` | editable |

## Running the pipeline

`Run Backup Now` (menu or Settings) runs: scan → clean → DerivedData removal →
archive → reports. `Scan` skips all destructive/archive steps and just
writes reports. `Cancel` stops between steps (and terminates a running `zip`).

## Menu & launch options

The menu bar icon opens a small window:

- A status banner: what the run is doing now, or how the last one went (green is fine, orange
  has warnings or was cancelled, red failed, with a link to the log).
- **Back Up Now** (blue) runs everything turned on in Settings.
- **Preview** works out what a run would remove and zip, and opens a summary window. It
  changes nothing.
- **Scan** finds projects and build output and writes the reports. It deletes and zips nothing.
- **Cancel** (orange) replaces them while a run is going.
- Footer links: Run Log, Reports, Archives, Settings, Help, Updates, Quit.

### Preview

Preview scans the folder, lists the build folders a run would remove, and does a dry run of
the zip. The summary window shows:

- how many Xcode projects were scanned and how many build folders were found;
- what would be removed (count and size), what would be kept and why, and the DerivedData
  that would go;
- what the zip would hold: the number of files and the size before compression (the zip
  itself will be smaller), and whether it would be encrypted;
- how many files the exclusions leave out, grouped by rule;
- warnings, such as a missing password or a very large sparse file.

Settings that are off (build folder removal, the zip) are noted, so the figures say what a run
*would* do if they were on. **Copy Summary** puts it on the clipboard, **Full Log** opens the
whole run log, and **Run Backup Now** runs it for real.

### Logs and warnings

A run can finish with warnings: things that went wrong without stopping it, such as a
folder that could not be removed. The menu banner turns orange, shows how many and the first
one, and **View** opens the Run Log with every warning listed at the top. Each run's full log is
saved in `~/Library/Logs/CodeProjectBackup/runs/` (the newest 40 are kept); the Run Log
window's clock menu switches between them and **Show in Finder** reveals the file.
`~/Library/Logs/CodeProjectBackup/runs.log` has one line per run, marked OK, WARN or ERROR, and
each report lists its warnings at the bottom.

### Help and updates

**Help** in the footer explains each button, the cleanup rules, the archive, the schedule and
common problems. **Updates** checks GitHub for a newer release, including pre-releases, and the
app checks once a day on launch.

Launch with `--open-settings` to open the Settings window on startup:

```bash
open -a CodeProjectBackup --args --open-settings
```

## Build & release

Requires Xcode + [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd CodeProjectBackup
xcodegen generate
xcodebuild -project CodeProjectBackup.xcodeproj -scheme CodeProjectBackup -configuration Release build
```

The app lands in `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/CodeProjectBackup.app`.
Copy it to `/Applications` if desired.

### Notarized DMG release (`scripts/build-app.sh`)

`scripts/build-app.sh` runs `xcodegen`, archives with `xcodebuild`, Developer ID
signs with hardened runtime, builds a `.dmg`, then submits to Apple notarization,
staples, and validates the ticket. Adapted from the Folder Copy Compare and
PrivacyPreserving-macOS release scripts.

```bash
# Local ad-hoc build (no signing, no notarization) -> dist/CodeProjectBackup.dmg
./scripts/build-app.sh

# Notarized release
export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TEAM_ID='TEAMID'
export NOTARY_PROFILE='notary-profile'   # xcrun notarytool store-credentials ...
./scripts/build-app.sh
```

Credentials can also live in `scripts/signing.env` (see `signing.env.example`);
that file is gitignored so secrets stay out of the repo. Outputs: the DMG, a
`SHA-256` checksum file, and a `.release.txt` receipt in `dist/`.

## Permissions

The app is unsandboxed (it needs broad file access like the shell script). On
first use macOS may prompt for access to folders such as `~/Library` (for
`DerivedData`) and `~/Downloads`. If scans/cleanups fail on protected paths,
grant **Full Disk Access** to the app in:
`System Settings → Privacy & Security → Full Disk Access`.

## Safety

- Cleanup and archiving are **off by default per-action toggles away** from the
  destructive steps: nothing runs until you trigger a run.
- Deleting `.build` and `DerivedData` is safe — Xcode/SPM regenerates them.
- Use **Keychain** password mode for unattended scheduled backups. The password is
  passed to `zip` with `-P`, so other local processes can see it in the process
  arguments while `zip` runs, and zip's built-in encryption (ZipCrypto) is weak.
  Keep archives on trusted storage.
- Build folder removal is off by default, skips folders with git-tracked files or
  recent changes, and never touches paths outside the search root.
