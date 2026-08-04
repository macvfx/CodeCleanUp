# Code Project Backup

A macOS menu bar app that mirrors `find_xcode_projects_cleanup.sh`: it scans a
folder for Xcode projects/workspaces, estimates recoverable space, optionally
runs `xcodebuild clean`, removes matching `DerivedData`, and creates a
password-protected zip archive — now on a schedule, with no terminal needed.

## Features

- **Menu bar app** — lives in the status bar, no Dock icon (`LSUIElement`)
- **Scan** for `.xcodeproj` / `.xcworkspace`, detect shared schemes via `xcodebuild -list`
- **Estimate** recoverable `.build` + `DerivedData` space before cleaning
- **Cleanup** — `xcodebuild clean` on detected schemes + remove matching `DerivedData` folders
- **Archive** — password-protected (or unencrypted) `zip` with the same cache/build
  excludes as the script (`.build`, `DerivedData`, `Pods`, `Carthage/Build`,
  `.swiftpm`, `SourcePackages`, `node_modules`, `.DS_Store`, `__MACOSX`, `.app`,
  `.dSYM`, build products/intermediates, …)
- **Password modes**
  - `Keychain` — password stored in macOS Keychain (create your own via `security add-generic-password`, same method as the script)
  - `Custom` — your own password saved to Keychain under `custom_password`
  - `None` — unencrypted archive
- **Scheduled runs** — hourly, daily, or weekly. Checks every minute; missed runs
  are caught up after launch/wake. Scheduled runs use the Keychain/Custom password,
  never prompt.
- **Reports** — timestamped `xcode_projects_YYYY-MM-DD_HH-MM-SS.txt` and `.csv` in
  the report directory (default `~/Desktop`)

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
| Schedule | Manual | Manual / Hourly / Daily / Weekly |
| Archive exclusions | 18 patterns | editable, one per line |
| Pruned scan paths | `~/Library /System /Volumes /private /usr /opt` | editable |

## Running the pipeline

`Run Backup Now` (menu or Settings) runs: scan → clean → DerivedData removal →
archive → reports. `Run Scan Only` skips all destructive/archive steps and just
writes reports. `Cancel` stops between steps (and terminates a running `zip`).

## Menu & launch options

The menu bar icon (`terminal` symbol) exposes: Run Backup Now, Run Scan Only,
Cancel Run, Run Log, Settings…, Open Reports Folder, Open Archives Folder, and Quit.
Settings opens in its own window (AppKit-managed so it always comes to front).

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
- Use **Keychain** password mode for unattended scheduled backups; the password
  never appears on a command line (the app passes it to `zip` via the `-P` flag
  only for the duration of the run, same as the script).
