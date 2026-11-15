#!/usr/bin/env bash
# Shared gate for local release preparation and every unsigned tvOS archive.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

python3 scripts/checks/clean_translations.py --check --strict
bash scripts/codegen.sh --check
bash scripts/ci_guard_checks.sh
python3 scripts/checks/check_hardcoded_strings.py
python3 scripts/checks/check_user_facing_errors.py
find lib test -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -type f -print0 |
  xargs -0 dart format --output=none --set-exit-if-changed
dart run scripts/checks/check_icon_consistency.dart
dart run scripts/checks/check_analyzer.dart
bash scripts/run_tests.sh
