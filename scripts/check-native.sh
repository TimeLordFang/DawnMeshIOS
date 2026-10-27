#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Debug
cmake --build native/build --parallel 4
ctest --test-dir native/build --output-on-failure
ruby test/ios_pod_patches_test.rb
native/build/ios_codec_test test/interop/android-opus-16k-20ms.bin
mkdir -p build/native-tests
swiftc -module-cache-path "$PWD/build/swift-module-cache" ios/Runner/WireSupport.swift test/swift/main.swift -o build/native-tests/wire-tests
build/native-tests/wire-tests
swiftc -module-cache-path "$PWD/build/swift-module-cache" ios/Runner/ApplePeerWiFi.swift test/swift_peer/main.swift -o build/native-tests/peer-tests
build/native-tests/peer-tests
swiftc -frontend -parse ios/Runner/*.swift
plutil -lint ios/Runner/PrivacyInfo.xcprivacy ios/Runner/en.lproj/InfoPlist.strings ios/Runner/zh-Hans.lproj/InfoPlist.strings ios/Runner/Info.plist ios/Runner/Runner.entitlements ios/Runner/RunnerAware.entitlements ios/Runner.xcodeproj/project.pbxproj
