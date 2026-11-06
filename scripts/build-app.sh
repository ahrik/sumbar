#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/temp/outputs}"
mkdir -p "$output_dir/Sumbar.app/Contents/MacOS"
cd "$project_dir"
build_options=(-c release)
if [[ "${SUMBAR_UNIVERSAL:-0}" == "1" ]]; then
    build_options+=(--arch arm64 --arch x86_64)
fi
bash scripts/swift.sh build "${build_options[@]}"
binary_dir="$(bash scripts/swift.sh build "${build_options[@]}" --show-bin-path)"
cp "$binary_dir/Sumbar" "$output_dir/Sumbar.app/Contents/MacOS/Sumbar"
mkdir -p "$output_dir/Sumbar.app/Contents/Resources"
ditto "$binary_dir/Sumbar_Sumbar.bundle" "$output_dir/Sumbar.app/Contents/Resources/Sumbar_Sumbar.bundle"
cp "$project_dir/LICENSE" "$output_dir/Sumbar.app/Contents/Resources/LICENSE"
asset_dir="$project_dir/temp/distribution-assets"
mkdir -p "$asset_dir"
xcrun swift -module-cache-path "$project_dir/temp/module-cache" "$project_dir/scripts/distribution-assets.swift" "$asset_dir"
iconutil -c icns "$asset_dir/Sumbar.iconset" -o "$asset_dir/Sumbar.icns"
cp "$asset_dir/Sumbar.icns" "$output_dir/Sumbar.app/Contents/Resources/Sumbar.icns"
cat > "$output_dir/Sumbar.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sumbar</string>
<key>CFBundleIdentifier</key><string>uz.sumbar.desktop</string>
<key>CFBundleName</key><string>Sumbar</string>
<key>CFBundleIconFile</key><string>Sumbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleDevelopmentRegion</key><string>ru</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -n "${SUMBAR_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SUMBAR_SIGN_IDENTITY" "$output_dir/Sumbar.app"
else
    codesign --force --sign - "$output_dir/Sumbar.app"
fi
ditto -c -k --sequesterRsrc --keepParent "$output_dir/Sumbar.app" "$output_dir/Sumbar-macOS.zip"
echo "$output_dir/Sumbar.app"
