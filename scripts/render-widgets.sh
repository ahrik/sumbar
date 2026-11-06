#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p temp/module-cache
xcrun swiftc -parse-as-library -D WIDGET_PREVIEW -module-cache-path temp/module-cache \
    -target "$(uname -m)-apple-macosx14.0" \
    Sources/Sumbar/CurrencyModels.swift Sources/Sumbar/CBUProvider.swift \
    Sources/Sumbar/HTTPClient.swift Sources/Sumbar/WidgetData.swift \
    Sources/SumbarWidgets/SumbarWidgets.swift scripts/widget-preview.swift \
    -o temp/widget-preview
# Match the extension's localized bundle for the standalone preview executable.
for language in ru uz; do
    mkdir -p "temp/$language.lproj"
    cp "Sources/Sumbar/Resources/$language.lproj/Localizable.strings" "temp/$language.lproj/Localizable.strings"
done
temp/widget-preview "${1:-$project_dir/temp/widget-previews}"
