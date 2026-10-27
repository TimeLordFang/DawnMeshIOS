#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  exec "$FLUTTER_ROOT/bin/flutter" "$@"
fi
exec flutter "$@"
