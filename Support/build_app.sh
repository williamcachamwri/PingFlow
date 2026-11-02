#!/usr/bin/env bash
# Assembles PingFlow.app by hand: a release binary, the Info.plist, the extracted assets and an
# ad-hoc signature. No Xcode project, because the app is one executable and a resource folder.
#
#   ./Support/build_app.sh              # arm64 release build
#   ./Support/build_app.sh --debug      # keep the debug build
#   ./Support/build_app.sh --universal  # arm64 + x86_64
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

configuration="release"
arch_flags=(--arch arm64)
for argument in "$@"; do
	case "$argument" in
	--debug) configuration="debug" ;;
	--universal) arch_flags=(--arch arm64 --arch x86_64) ;;
	*) echo "unknown option: $argument" >&2 && exit 64 ;;
	esac
done

build_directory=".build/${configuration}"
app="build/PingFlow.app"

echo "▸ swift build -c ${configuration} ${arch_flags[*]}"
swift build -c "${configuration}" "${arch_flags[@]}"

echo "▸ assembling ${app}"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "${build_directory}/PingFlow" "$app/Contents/MacOS/PingFlow"
chmod +x "$app/Contents/MacOS/PingFlow"
cp Support/Info.plist "$app/Contents/Info.plist"
printf 'APPL????' >"$app/Contents/PkgInfo"

# Assets sit inside the bundle so the app works from anywhere; AssetCatalog looks for
# Contents/Resources/Assets first.
mkdir -p "$app/Contents/Resources/Assets"
cp -R Assets/textures Assets/sounds "$app/Contents/Resources/Assets/"
if [[ -d Assets/emotes ]]; then
	cp -R Assets/emotes "$app/Contents/Resources/Assets/"
fi
cp Assets/ATTRIBUTION.md "$app/Contents/Resources/Assets/ATTRIBUTION.md"

# The app icon comes from the extracted generic-ping mark, so the Dock and the About page agree.
mark="Assets/textures/generic_ping.png"
if [[ -f "$mark" ]] && command -v iconutil >/dev/null 2>&1; then
	iconset="build/AppIcon.iconset"
	mkdir -p "$iconset"
	for size in 16 32 128 256 512; do
		sips -z "$size" "$size" "$mark" --out "$iconset/icon_${size}x${size}.png" >/dev/null
		sips -z "$((size * 2))" "$((size * 2))" "$mark" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
	done
	iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
	rm -rf "$iconset"
fi

echo "▸ ad-hoc code signature"
codesign --force --options runtime --sign - "$app" >/dev/null 2>&1 || codesign --force --sign - "$app"
codesign --verify --verbose=2 "$app" 2>&1 | tail -3 || true

cat >build/INSTALL.txt <<'TEXT'
PingFlow — install

1. Copy build/PingFlow.app to /Applications.
2. Open it once. It lives in the menu bar; no window stays open.
3. macOS asks for Accessibility (Privacy & Security → Accessibility → PingFlow). Turn it on.
   The app re-checks every 1.5 s, so the wheel works the moment you flip the switch — no relaunch.
   Because this build is ad-hoc signed, an update may leave a stale entry in that list: remove
   PingFlow, re-add it with "+", and it works again. The Permissions page has the buttons.
4. Hold ⌥ anywhere, move, release over a slice. ⌃⌥P turns PingFlow off and on.
5. Launch at Login is on the General page and uses SMAppService, so it survives a reboot.

Limits that are macOS's, not the app's: no overlay above another app's exclusive full screen or
protected video; keystrokes inside secure input fields are hidden from every tap.

League of Legends art and audio belong to Riot Games — see Assets/ATTRIBUTION.md inside the bundle.
TEXT

echo "▸ done: $app ($(du -sh "$app" | cut -f1))"
