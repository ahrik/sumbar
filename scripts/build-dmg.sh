#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/temp/outputs}"
python_bin="${SUMBAR_PYTHON:-$project_dir/temp/distribution-venv/bin/python}"
if [[ ! -x "$python_bin" ]]; then
    echo "Install packaging/requirements.txt in temp/distribution-venv or set SUMBAR_PYTHON." >&2
    exit 1
fi
bash "$project_dir/scripts/build-app.sh" "$output_dir"
rm -f "$output_dir/Sumbar.dmg"
"$python_bin" -m dmgbuild -s "$project_dir/packaging/dmg-settings.py" \
    -D "app=$output_dir/Sumbar.app" -D "assets=$project_dir/temp/distribution-assets" \
    "Sumbar" "$output_dir/Sumbar.dmg"
cd "$output_dir"
shasum -a 256 Sumbar.dmg Sumbar-macOS.zip > SHA256SUMS
echo "$output_dir/Sumbar.dmg"
