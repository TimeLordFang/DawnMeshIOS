#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s test -p release_policy_test.py
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh analyze --no-pub
./scripts/flutter.sh test test/ios_room_creation_test.dart --no-pub
./scripts/flutter.sh test --concurrency=1 --no-pub
./scripts/check-native.sh
