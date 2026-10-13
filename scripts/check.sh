#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/flutter.sh pub get --enforce-lockfile
./scripts/flutter.sh analyze
./scripts/flutter.sh test --concurrency=1
./scripts/check-native.sh
