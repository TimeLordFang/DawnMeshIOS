#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -version
command -v pod >/dev/null
./scripts/flutter.sh config --no-enable-swift-package-manager
./scripts/flutter.sh pub get --enforce-lockfile
# Regenerates Flutter config and plugin registrant before installing local pods.
./scripts/flutter.sh build ios --config-only --no-codesign
if [[ -f ios/Podfile.lock ]]; then
  (cd ios && pod install --deployment)
else
  echo "Generating the initial Podfile.lock; review and commit it before distributing a build." >&2
  (cd ios && pod install)
fi
./scripts/flutter.sh build ios --release --no-codesign --no-pub
