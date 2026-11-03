#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/NextWord.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Resources/Info.plist")"
INSTALL=0
RUN=0
DIST=0

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    --debug) CONFIG=debug ;;
    --dist) DIST=1 ;;
  esac
done

cd "$ROOT"
BUILD_ARGS=(-c "$CONFIG")
if (( DIST )); then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
xcrun swift build "${BUILD_ARGS[@]}"
BIN="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)/NextWord"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  xcrun swift "$ROOT/Scripts/make-icon.swift" "$ROOT/Resources/AppIcon.icns"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NextWord"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if (( DIST )); then
  IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
  if [[ -z "$IDENTITY" ]]; then
    echo "No Developer ID Application certificate found. Set SIGN_IDENTITY." >&2
    exit 1
  fi
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  ZIP="$ROOT/build/NextWord.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarized and stapled: $ZIP"
  else
    echo "Signed but not notarized (set NOTARY_PROFILE to a notarytool keychain profile): $ZIP"
  fi
  exit 0
fi

# A stable signing identity keeps the Accessibility grant valid across rebuilds; ad-hoc signatures change every build.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
codesign --force --options runtime --sign "${IDENTITY:--}" --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if (( INSTALL )); then
  pkill -x NextWord 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/NextWord.app"
  cp -R "$APP" "$HOME/Applications/NextWord.app"
  APP="$HOME/Applications/NextWord.app"
  echo "Installed $APP"
fi

if (( RUN )); then
  pkill -x NextWord 2>/dev/null || true
  open "$APP"
fi
