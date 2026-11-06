#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/temp/outputs}"
mkdir -p "$output_dir/Sumbar.app/Contents/MacOS"
cd "$project_dir"
bash scripts/swift.sh build -c release
binary_dir="$(bash scripts/swift.sh build -c release --show-bin-path)"
cp "$binary_dir/Sumbar" "$output_dir/Sumbar.app/Contents/MacOS/Sumbar"
cat > "$output_dir/Sumbar.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sumbar</string>
<key>CFBundleIdentifier</key><string>uz.sumbar.desktop</string>
<key>CFBundleName</key><string>Sumbar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$output_dir/Sumbar.app"
ditto -c -k --sequesterRsrc --keepParent "$output_dir/Sumbar.app" "$output_dir/Sumbar-macOS.zip"
echo "$output_dir/Sumbar.app"
