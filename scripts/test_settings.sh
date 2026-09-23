#!/bin/bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
framework_dir="${1:?Pass the absolute Debug Build/Products directory containing GureumCore.framework}"
test_dir="$(mktemp -d /private/tmp/hanjaime-settings-test.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
cp "$root_dir/tests/SettingsUpdateMain.swift" "$test_dir/main.swift"
xcrun swiftc -module-cache-path "$test_dir/cache" -F "$framework_dir" -framework GureumCore -framework Hangul -Xlinker -rpath -Xlinker "$framework_dir" "$root_dir/Sources/ConfigurationWindow.swift" "$test_dir/main.swift" -o "$test_dir/settings-tests"
"$test_dir/settings-tests"
