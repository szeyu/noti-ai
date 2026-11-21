#!/bin/zsh
# Builds Noti AI.
#   ./build.sh            build, install to ~/Applications, and launch
#   ./build.sh app        only build build/NotiAI.app (doesn't touch the installed app)
#   ./build.sh dmg        build build/NotiAI.dmg for sharing
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-install}"
APP="build/NotiAI.app"
DEST="$HOME/Applications/NotiAI.app"
BUNDLE_ID="com.szeyu.notiai"
# A local self-signed certificate. Signing with the same identity every time keeps the
# Accessibility permission valid across rebuilds; ad-hoc signing breaks it on each build.
IDENTITY="Noti AI Local Signing"

mkdir -p build
echo "› Compiling (Apple silicon + Intel)…"
# Build each architecture with the plain toolchain (a combined --arch build needs full Xcode),
# then merge them into one universal binary.
SLICES=()
for ARCH in arm64 x86_64; do
  FLAGS=(-c release --triple "$ARCH-apple-macosx13.0" --scratch-path ".build/$ARCH")
  if ! swift build "${FLAGS[@]}" > "build/swift-$ARCH.log" 2>&1; then
    grep -E "error" "build/swift-$ARCH.log" | head -20
    echo "Build failed for $ARCH (full log: build/swift-$ARCH.log)"; exit 1
  fi
  SLICES+=("$(swift build "${FLAGS[@]}" --show-bin-path)/NotiAI")
done
BIN="build/NotiAI-universal"
lipo -create -output "$BIN" "${SLICES[@]}"

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/NotiAI"
[[ -f Assets/AppIcon.icns ]] || (cd Assets && swift make-icon.swift . >/dev/null)
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
  STABLE=1
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  STABLE=0
fi

case "$MODE" in
  app)
    echo "Built $APP"
    ;;
  dmg)
    DMG="build/NotiAI.dmg"
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "Noti AI" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Built $DMG"
    ;;
  install)
    pkill -x NotiAI 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # With an ad-hoc signature the old Accessibility entry goes stale (looks on, isn't).
    [[ $STABLE == 0 ]] && tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    open "$DEST"
    echo "Installed and launched $DEST"
    ;;
  *)
    echo "Usage: ./build.sh [install|app|dmg]"; exit 1
    ;;
esac
