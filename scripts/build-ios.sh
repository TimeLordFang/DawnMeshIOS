#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
dawnmesh_aware=false
if [[ "${1:-}" == "--wifi-aware" && "$#" -eq 1 ]]; then
  dawnmesh_aware=true
elif [[ "$#" -ne 0 ]]; then
  echo "Usage: $0 [--wifi-aware]" >&2
  exit 2
fi
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
if [[ "$dawnmesh_aware" == true ]]; then
  dawnmesh_derived="$PWD/build/ios/aware-derived"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$dawnmesh_derived" \
    -xcconfig ios/Flutter/Signing.wifi-aware.xcconfig CODE_SIGNING_ALLOWED=NO build
  # Keep CocoaPods' per-target product paths; stage only the completed app.
  rm -rf "$PWD/build/ios/iphoneos-aware/Runner.app"
  mkdir -p "$PWD/build/ios/iphoneos-aware"
  ditto "$dawnmesh_derived/Build/Products/Release-iphoneos/Runner.app" \
    "$PWD/build/ios/iphoneos-aware/Runner.app"
else
  ./scripts/flutter.sh build ios --release --no-codesign --no-pub
fi
