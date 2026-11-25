#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
ARGS=" $* "

echo "→ тесты логики"
tmpt=$(mktemp -d)
swiftc Shared/Language.swift Shared/Config.swift Shared/Policy.swift Tests/main.swift -o "$tmpt/tests" 2>&1 | grep -E "error" && exit 1
"$tmpt/tests" | tail -1
rm -rf "$tmpt"
[[ "$ARGS" == *" --test "* ]] && exit 0

APP=build/Buttery.app
ICNS=Resources/AppIcon.icns

if [[ "$ARGS" == *" --icon "* || ! -f "$ICNS" ]]; then
  echo "→ иконка"
  tmp=$(mktemp -d)
  swiftc -O Tools/MakeIcon.swift -o "$tmp/makeicon"
  "$tmp/makeicon" "$tmp/icon.png"
  set="$tmp/AppIcon.iconset"; mkdir "$set"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$tmp/icon.png" --out "$set/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$tmp/icon.png" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$ICNS"
  sips -z 512 512 "$tmp/icon.png" --out docs/icon.png >/dev/null
  rm -rf "$tmp"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "let buildID = \"$(date +%Y%m%d%H%M%S)\"" > Shared/BuildInfo.swift

echo "→ помощник butteryd"
swiftc -O Shared/*.swift Daemon/main.swift -framework IOKit \
  -target arm64-apple-macos14 -o "$APP/Contents/Resources/butteryd"

echo "→ приложение Buttery"
swiftc -O -parse-as-library Shared/*.swift App/*.swift \
  -framework IOKit -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -target arm64-apple-macos14 -o "$APP/Contents/MacOS/Buttery"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/com.buttery.daemon.plist "$ICNS" "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/butteryd"
codesign --force --sign - "$APP"
echo "Готово: $APP"

if [[ "$ARGS" == *" --install "* ]]; then
  pkill -x Buttery 2>/dev/null || true
  rm -rf /Applications/Buttery.app
  cp -R "$APP" /Applications/
  echo "Установлено: /Applications/Buttery.app"
  open /Applications/Buttery.app
fi

if [[ "$ARGS" == *" --dmg "* ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  DMG="build/Buttery-$VERSION.dmg"
  stage=$(mktemp -d)
  cp -R "$APP" "$stage/"
  ln -s /Applications "$stage/Applications"
  rm -f "$DMG"
  hdiutil create -quiet -srcfolder "$stage" -volname Buttery -fs HFS+ -format UDZO -imagekey zlib-level=9 -o "$DMG"
  rm -rf "$stage"
  echo "Образ: $DMG"
fi
