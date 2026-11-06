#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
task_temp="$project_dir/temp"
mkdir -p "$task_temp/module-cache" "$task_temp/system"
export CLANG_MODULE_CACHE_PATH="$task_temp/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$task_temp/module-cache"
export TMPDIR="$task_temp/system/"
cd "$project_dir"
exec swift "$@" --scratch-path "$task_temp/build" --cache-path "$task_temp/cache" --config-path "$task_temp/config" --security-path "$task_temp/security"
