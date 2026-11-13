#!/bin/bash
# Embed requested entitlements in the unsigned executables for tvsign's signer.
# This is ad-hoc metadata, not an Apple identity or provisioning profile.
set -euo pipefail

app_path=${1:?Pass the archived Runner.app path}
script_dir=$(cd "$(dirname "$0")" && pwd)
project_dir=$(cd "$script_dir/.." && pwd)
runner_binary="$app_path/Runner"
shelf_binary="$app_path/PlugIns/TopShelfExtension.appex/TopShelfExtension"

test -f "$runner_binary"
test -f "$shelf_binary"
codesign --force --sign - --entitlements "$project_dir/Runner/Runner.entitlements" "$runner_binary"
codesign --force --sign - --entitlements "$project_dir/TopShelfExtension/TopShelfExtension.entitlements" "$shelf_binary"

for binary in "$runner_binary" "$shelf_binary"; do
  codesign -d --entitlements :- "$binary" 2>/dev/null | grep -q 'com.apple.security.application-groups'
done
