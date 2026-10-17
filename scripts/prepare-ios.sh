#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：./scripts/prepare-ios.sh [--no-open]

准备本地 Xcode 真机安装：检查工具、安装锁定依赖、生成 Flutter 配置，
然后打开 ios/Runner.xcworkspace。构建模式沿用 Runner scheme 的 Run 配置。

  --no-open  仅准备，不打开 Xcode
  -h, --help 显示帮助

Flutter 可放在 PATH 中，或通过 FLUTTER_ROOT 指定 SDK 目录。
EOF
}

fail() {
  printf '准备失败：%s\n' "$*" >&2
  exit 1
}

open_workspace=true
for arg in "$@"; do
  case "$arg" in
    --no-open) open_workspace=false ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "未知参数：$arg" ;;
  esac
done

cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || fail '此脚本需要 macOS 和完整 Xcode。'
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  [[ -x "$FLUTTER_ROOT/bin/flutter" ]] || fail 'FLUTTER_ROOT 未指向有效的 Flutter SDK。'
else
  command -v flutter >/dev/null || fail '未找到 Flutter，请加入 PATH 或设置 FLUTTER_ROOT。'
fi
command -v pod >/dev/null || fail '未找到 CocoaPods，请安装后重试。'
xcodebuild -version || fail '无法使用完整 Xcode，请检查 xcode-select 或 DEVELOPER_DIR。'
xcrun --sdk iphoneos --show-sdk-path >/dev/null || fail '未找到 iPhoneOS SDK，请先完成 Xcode 初始化。'
[[ -f pubspec.lock && -f ios/Podfile.lock ]] || fail '缺少依赖锁文件，请恢复仓库中的 pubspec.lock 和 ios/Podfile.lock。'

scheme=ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
configuration=$(/usr/bin/xmllint --xpath 'string(/Scheme/LaunchAction/@buildConfiguration)' "$scheme")
case "$configuration" in
  Debug) mode=debug ;;
  Profile) mode=profile ;;
  Release) mode=release ;;
  *) fail "无法识别 Runner scheme 的 Run 配置：$configuration" ;;
esac

printf '\n[1/3] 安装锁定的 Flutter 依赖\n'
./scripts/flutter.sh pub get --enforce-lockfile
printf '\n[2/3] 生成 iOS 配置（%s）\n' "$configuration"
./scripts/flutter.sh build ios "--$mode" --config-only --no-codesign --no-pub
printf '\n[3/3] 安装锁定的 CocoaPods 依赖并应用项目补丁\n'
(cd ios && pod install --deployment)

if "$open_workspace"; then
  open ios/Runner.xcworkspace
fi
cat <<EOF

准备完成，Xcode Run 配置：${configuration}。
在 ios/Runner.xcworkspace 中选择 Runner 和自己的 iPhone，
首次使用时在 Signing & Capabilities 选择自己的 Team，再点击 Run（⌘R）。
EOF
