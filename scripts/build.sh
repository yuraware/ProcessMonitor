#!/usr/bin/env bash
#
# Builds ProcessMonitor.app locally.
#
#   scripts/build.sh                 build dist/ProcessMonitor.app
#   scripts/build.sh --install       build and copy to /Applications, then launch
#   scripts/build.sh --run           build and launch from dist/
#   scripts/build.sh --dmg           build and also create dist/ProcessMonitor-<version>.dmg
#   scripts/build.sh --universal     build an arm64 + x86_64 binary
#   scripts/build.sh --clean         remove .build and dist first
#
# Environment:
#   CODESIGN_IDENTITY   signing identity (default: "-" for ad-hoc signing)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ProcessMonitor"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
PLIST_SRC="$ROOT/Support/Info.plist"
ICON_SRC="$ROOT/Support/AppIcon.icns"
IDENTITY="${CODESIGN_IDENTITY:--}"

INSTALL=0; RUN=0; DMG=0; UNIVERSAL=0; CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    --dmg) DMG=1 ;;
    --universal) UNIVERSAL=1 ;;
    --clean) CLEAN=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ $CLEAN -eq 1 ]]; then
  log "Cleaning"
  rm -rf "$ROOT/.build" "$DIST"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

log "Building $APP_NAME $VERSION ($BUILD_NUMBER)"
BUILD_ARGS=(-c release --package-path "$ROOT")
if [[ $UNIVERSAL -eq 1 ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"

if [[ ! -f "$ICON_SRC" ]]; then
  log "Generating app icon"
  "$ROOT/scripts/make-icon.sh"
fi

log "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$PLIST_SRC" "$APP/Contents/Info.plist"
cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

log "Signing (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP"
codesign --verify --strict "$APP"

if [[ $DMG -eq 1 ]]; then
  DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
  log "Creating $DMG_PATH"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
  rm -rf "$STAGING"
fi

if [[ $INSTALL -eq 1 ]]; then
  TARGET="/Applications/$APP_NAME.app"
  log "Installing to $TARGET"
  if pgrep -xq "$APP_NAME"; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    sleep 1
  fi
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  log "Launching $TARGET"
  open "$TARGET"
elif [[ $RUN -eq 1 ]]; then
  log "Launching $APP"
  open "$APP"
fi

log "Done: $APP"
