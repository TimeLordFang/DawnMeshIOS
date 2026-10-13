#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  exec "$FLUTTER_ROOT/bin/flutter" "$@"
fi
exec flutter "$@"
