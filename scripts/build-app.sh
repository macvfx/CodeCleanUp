#!/usr/bin/env bash
#
# Build, sign, notarize, staple, and package CodeProjectBackup as a DMG.
#
# Adapted from:
#   - Folder Copy Compare/scripts/build-sign-notarize-dmg.sh
#   - PrivacyPreserving-macOS/Scripts/build-app.sh
#
# Credentials can come from scripts/signing.env (gitignored) or environment:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID="TEAMID"
#   NOTARY_PROFILE="notary-profile"   # xcrun notarytool store-credentials profile
#   NOTARIZE=1                        # set 0 to skip notarization
#
# If SIGN_IDENTITY is empty the app is built ad-hoc (local-only) and
# notarization is skipped automatically.
#
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-app.sh [--out DIR] [--dmg-name NAME] [--no-notarize]

Options:
  --out DIR           Output directory for the DMG (default: <repo>/dist)
  --dmg-name NAME     DMG filename without .dmg (default: CodeProjectBackup)
  --no-notarize       Skip the Apple notarization + staple step
  -h, --help          Show this help

Environment:
  SIGN_IDENTITY / MAC_APP_SIGN_IDENTITY   Developer ID identity
  TEAM_ID / MAC_APP_TEAM_ID               Apple Developer team ID
  NOTARY_PROFILE / MAC_APP_NOTARY_PROFILE notarytool Keychain profile
  NOTARIZE                                0 disables notarization

Example (notarized release):
  export SIGN_IDENTITY='Developer ID Application: Name (TEAMID)'
  export TEAM_ID='TEAMID'
  export NOTARY_PROFILE='notary-profile'
  ./scripts/build-app.sh
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/scripts/signing.env" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/signing.env"
fi

APP_NAME="CodeProjectBackup"
SCHEME="CodeProjectBackup"
CONFIGURATION="Release"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:-${MAC_APP_SIGN_IDENTITY:-}}"
TEAM_ID="${TEAM_ID:-${MAC_APP_TEAM_ID:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-${MAC_APP_NOTARY_PROFILE:-notary-profile}}"
NOTARIZE="${NOTARIZE:-1}"
DMG_NAME="CodeProjectBackup"
KEEP_WORK_DIR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || die "--out requires a path"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --dmg-name)
      [[ $# -ge 2 ]] || die "--dmg-name requires a name"
      DMG_NAME="$2"
      shift 2
      ;;
    --no-notarize)
      NOTARIZE=0
      shift
      ;;
    --keep-work-dir)
      KEEP_WORK_DIR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

for command_name in xcodegen xcodebuild codesign hdiutil ditto plutil lipo spctl shasum; do
  require_command "$command_name"
done

[[ -f "$ROOT/CodeProjectBackup.xcodeproj/project.pbxproj" ]] || {
  log "Generating Xcode project with xcodegen"
  xcodegen generate
}

if [[ -n "$SIGN_IDENTITY" ]]; then
  log "Signing identity: $SIGN_IDENTITY"
  security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null ||
    die "Signing identity not found in Keychain: $SIGN_IDENTITY"
else
  log "No signing identity — building ad-hoc (local-only)."
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
final_dmg="$OUTPUT_DIR/$DMG_NAME.dmg"
checksum_file="$OUTPUT_DIR/$DMG_NAME.sha256.txt"
receipt_file="$OUTPUT_DIR/$DMG_NAME.release.txt"

work_dir="$(mktemp -d "/private/tmp/cpb-build.XXXXXX")"
archive_path="$work_dir/$APP_NAME.xcarchive"
archive_app="$archive_path/Products/Applications/$APP_NAME.app"
stage_dir="$work_dir/DMG"
unsigned_dmg="$work_dir/$DMG_NAME.dmg"
mount_dir="$work_dir/mount"
mounted=0
succeeded=0

cleanup() {
  if [[ "$mounted" == "1" ]]; then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  if [[ "$succeeded" == "1" && "$KEEP_WORK_DIR" == "0" ]]; then
    rm -rf "$work_dir"
  else
    printf '\nWork directory retained: %s\n' "$work_dir" >&2
  fi
}
trap cleanup EXIT

sign_args=(CODE_SIGN_STYLE=Manual)
if [[ -n "$SIGN_IDENTITY" ]]; then
  sign_args+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID")
else
  sign_args+=(CODE_SIGN_IDENTITY=-)
fi

log "Archiving $APP_NAME ($SCHEME, $CONFIGURATION)"
xcodebuild archive \
  -project "$ROOT/CodeProjectBackup.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  ONLY_ACTIVE_ARCH=NO \
  "${sign_args[@]}"

[[ -d "$archive_app" ]] || die "Expected app not found in archive: $archive_app"

version="$(plutil -extract CFBundleShortVersionString raw "$archive_app/Contents/Info.plist")"
build="$(plutil -extract CFBundleVersion raw "$archive_app/Contents/Info.plist")"
executable_name="$(plutil -extract CFBundleExecutable raw "$archive_app/Contents/Info.plist")"
architectures="$(lipo -archs "$archive_app/Contents/MacOS/$executable_name")"

log "Code signing the archived app"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$archive_app"
else
  codesign --force --deep --sign - "$archive_app"
fi
codesign --verify --deep --strict --verbose=2 "$archive_app"

log "Creating $DMG_NAME.dmg"
mkdir -p "$stage_dir"
ditto "$archive_app" "$stage_dir/$APP_NAME.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$stage_dir" \
  -ov \
  -format UDZO \
  "$unsigned_dmg"

if [[ "$NOTARIZE" == "1" && -n "$SIGN_IDENTITY" ]]; then
  log "Submitting DMG to Apple notarization (profile: $NOTARY_PROFILE)"
  notary_output="$work_dir/notarytool.txt"
  xcrun notarytool submit "$unsigned_dmg" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$notary_output"
  submission_id="$(awk '/^[[:space:]]*id:/ { print $2; exit }' "$notary_output")"
  grep -q 'status: Accepted' "$notary_output" ||
    die "Apple did not accept the notarization submission"

  log "Stapling and validating notarization ticket"
  xcrun stapler staple "$unsigned_dmg"
  xcrun stapler validate "$unsigned_dmg"

  log "Final delivery checks"
  mkdir -p "$mount_dir"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$unsigned_dmg"
  mounted=1
  mounted_app="$mount_dir/$APP_NAME.app"
  [[ -d "$mounted_app" ]] || die "Mounted app is missing: $mounted_app"
  [[ -L "$mount_dir/Applications" ]] || die "Mounted DMG is missing its Applications shortcut"
  codesign --verify --deep --strict --verbose=2 "$mounted_app"
  spctl -a -vv -t exec "$mounted_app"
  hdiutil detach "$mount_dir"
  mounted=0
else
  log "Skipping notarization"
fi

log "Saving final artifacts"
ditto "$unsigned_dmg" "$final_dmg"
checksum="$(shasum -a 256 "$final_dmg" | awk '{ print $1 }')"
printf '%s  %s\n' "$checksum" "$(basename "$final_dmg")" >"$checksum_file"

{
  printf 'App: %s\n' "$APP_NAME"
  printf 'Scheme: %s\n' "$SCHEME"
  printf 'Configuration: %s\n' "$CONFIGURATION"
  printf 'Version: %s\n' "$version"
  printf 'Build: %s\n' "$build"
  printf 'Architectures: %s\n' "$architectures"
  printf 'Signing identity: %s\n' "${SIGN_IDENTITY:-ad-hoc}"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    printf 'Team ID: %s\n' "$TEAM_ID"
    printf 'Notary profile: %s\n' "$NOTARY_PROFILE"
    printf 'Notary submission: %s\n' "${submission_id:-unknown}"
    printf 'Gatekeeper: accepted, Notarized Developer ID\n'
  else
    printf 'Gatekeeper: not applicable (ad-hoc local build)\n'
  fi
  printf 'DMG: %s\n' "$final_dmg"
  printf 'SHA-256: %s\n' "$checksum"
  printf 'Completed UTC: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} >"$receipt_file"

succeeded=1

log "Release artifact complete"
printf 'DMG: %s\n' "$final_dmg"
printf 'SHA-256: %s\n' "$checksum"
printf 'Receipt: %s\n' "$receipt_file"
