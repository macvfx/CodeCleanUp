# Changelog

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
