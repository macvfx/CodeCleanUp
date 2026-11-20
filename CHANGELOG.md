# Changelog

## 1.2.0 (build 7, unreleased)

### Features
- **Optional cleanup of Xcode and developer-tool leftovers**, in Settings, Cleanup, under
  "Xcode and developer tools". Off by default. When on, it runs as one more step of every
  backup, so it follows the same schedule, and Preview lists what it would do. It works
  outside the search root and covers: Xcode archives older than a chosen number of days
  (default 60; the newest archive of each app is always kept, because an archive holds the
  only debug symbols for that build), old device-support folders (newest per device model
  kept), the Xcode and SwiftPM caches and simulator logs (skipped while Xcode is open), and
  simulator devices Xcode already marks unavailable. Everything except the simulators goes to
  the Trash, so it can be put back; the space is freed when the Trash is emptied. Removal is
  limited to those Xcode folders and refuses any other path. The same rules are in
  `dev_space_cleanup.sh` in the find repo.

## 1.2.0 (build 6, unreleased)

### Features
- **Settings window with a sidebar.** Folders, Cleanup, Archive, Schedule and Advanced each
  get a pane with a large title. Run Log, Reports, Archives, Help and Updates are in the
  sidebar too. Back Up Now is a blue button pinned at the bottom of every pane, with an
  orange Cancel while a run is going.

### Fixes
- **Schedule time was hard to read and its clock was not stated.** Hour and Minute were two
  separate pop-ups pushed to opposite edges of the page, always 24-hour with no label saying
  so. Now one "Run at" time control follows the Mac's 12 or 24-hour setting, and a sentence
  under the schedule says exactly when it runs, in both forms, for example "Runs every day at
  02:00 (2:00 AM)." Stored settings are unchanged (hour and minute as numbers).

## 1.2.0 (builds 4 and 5)

### Features
- **Preview summary window.** Preview now ends in a window that says what a run would do:
  projects scanned, build folders it would remove (count, size, and which are kept and why),
  DerivedData it would remove, how many files the zip would hold and its size before
  compression, how many files the exclusions leave out grouped by rule, and warnings. Before,
  Preview only wrote to the Run Log, which it did not open, and never estimated the zip.
  The zip estimate comes from a dry run of the same `zip` command (`zip -sf`).
- **New menu.** The plain system menu is now a window with a status banner, a blue Back Up Now,
  Preview and Scan buttons, an orange Cancel while running, and a footer of Run Log, Reports,
  Archives, Settings, Help, Updates and Quit. The banner shows the current step while running
  and the last run's result afterwards.
- **Help window** explaining each button, cleanup safety, the archive, schedules and
  troubleshooting.
- **Update checking** through the shared GitHub update checker, once a day on launch and from
  Updates in the menu. It includes pre-releases, since every release so far is one.

### Fixes
- **Warnings were invisible.** A run could finish "with warnings" and give no way to see
  them. Causes: the failure detail existed only in the Run Log window's memory (lost when the
  app restarted or the next run cleared it); `runs.log` marked the run OK with no failure
  count; the report said "Clean failures: 16" without saying which; and the failure reason
  was just the last line of stderr, often empty. Now: every run's full log is saved
  (`~/Library/Logs/CodeProjectBackup/runs/`, newest 40 kept); each problem is collected as a
  warning with a readable cause and listed at the end of the log, at the bottom of the
  report, and at the top of the Run Log window; the menu banner shows the count and the first
  warning with a View button; `runs.log` records WARN and the count; the Run Log window can
  switch between saved runs and show the file in Finder.
- **The 16 warnings in a test run** were all one cause. The scan counted the generated
  `.swiftpm/xcode/package.xcworkspace` inside Swift packages as a project, and
  `xcodebuild clean` on it always fails ("Building a Swift package requires a destination").
  Scanning now skips `.swiftpm` folders. Swift packages are cleaned by removing `.build`.
- Scan and Preview no longer run `xcodebuild -list` on every project. It took minutes for 60
  projects and only `xcodebuild clean` needs the schemes, so it now runs only when clean is
  turned on. Scan and Preview on a 60-project folder take about 8 seconds. The reports say
  "(not checked)" for schemes in that case.
- The Run Log is now opened by the app rather than by a SwiftUI window scene, so Preview and
  the menu can open it reliably.

## 1.1.1 (build 3)

### Features
- Archive leaves out Archiware P5 container block files (`*.p5b`). They are large and
  regenerable, and a test setup can hold several hundred MB of them. Saved exclusion lists
  pick the pattern up once; delete the line in Settings to back them up.

## 1.1.0 (build 2)

### Features
- Removes `.build` and Xcode build-output folders in the search root (off by default).
  Build output is recognised by what it contains (`Build/Products`,
  `CompilationCache.noindex`, precompiled-module caches, `XCBuildData`), not by its
  name, so folders such as `Build`, `BuildPortFix` and `build` are found.
- Folders with git-tracked files, or changed in the last hour, are never removed.
  Every path is re-checked to sit inside the search root.
- Menu item **Preview Build Cleanup** lists what would be removed and deletes nothing.
- Archive step leaves out the exact build trees the scan found.
- Credential files (`signing.env`, `.sentryclirc`, `.env`, `.p12`, `.mobileprovision`,
  SSH keys) are left out automatically when the archive has no password, or always
  with the new setting.
- Reports list every build folder with its size and why it was kept.

### Fixes
- Archive no longer reads `CompilationCache.noindex`, which can hold a sparse file that
  reports tens of GB (one project showed 36 GB on 48 KB of disk), making `zip` very slow.
  Cause: the default exclusions predated Xcode's compilation cache.
- Archive now also leaves out `SwiftExplicitPrecompiledModules`,
  `SDKExplicitPrecompiledModules`, `SDKStatCaches.noindex`, `XCBuildData`,
  `.claude/worktrees`, `.venv*` and `__pycache__`.
- Saved exclusion lists no longer hide new defaults: patterns added in a newer version
  are appended once, and the user's edits are kept. Cause: saved settings overrode the
  defaults entirely.
- README no longer claims the password never appears on a command line. `zip -P` puts
  it in the process arguments, and ZipCrypto is weak encryption; the run log now says so.

Measured on a 44.6 GB projects folder: archive input 44.6 GB to 2.5 GB, 70 build
folders (18.8 GB) detected.
