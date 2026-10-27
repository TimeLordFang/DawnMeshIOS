#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
cd "$(dirname "$0")/.."
for tool in cmake swiftc pod xcodebuild; do
  command -v "$tool" >/dev/null || { echo "Required local tool is not on PATH: $tool" >&2; exit 1; }
done
./scripts/check.sh
./scripts/build-ios.sh "$@"
