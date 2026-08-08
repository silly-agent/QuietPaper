#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_BUNDLE_NAME="${QUIETPAPER_APP_BUNDLE_NAME:-QuietPaper.app}"
APP_DIR="$PROJECT_DIR/dist/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
VERSION_FILE="$PROJECT_DIR/Sources/QuietPaper/Infrastructure/AppVersion.swift"
ICON_FILE="$PROJECT_DIR/Resources/QuietPaper.icns"
BUILD_SCRATCH_PATH="${QUIETPAPER_BUILD_SCRATCH_PATH:-$PROJECT_DIR/.build}"
BUILD_TRIPLE="${QUIETPAPER_BUILD_TRIPLE:-}"
EXPECTED_ARCH="${QUIETPAPER_EXPECTED_ARCH:-}"
RELEASE_VERSION="${QUIETPAPER_RELEASE_VERSION:-}"
CODESIGN_IDENTITY="${QUIETPAPER_CODESIGN_IDENTITY:--}"

cd "$PROJECT_DIR"

# 本地打包默认递增补丁号；标签发布使用已经写入 AppVersion.swift 的固定版本。
CURRENT_VERSION=$(sed -n 's/^    static let current = "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$VERSION_FILE")
if [ -z "$CURRENT_VERSION" ]; then
  echo "error: 无法从 $VERSION_FILE 解析版本号" >&2
  exit 1
fi
if [ -n "$RELEASE_VERSION" ]; then
  if ! printf '%s\n' "$RELEASE_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: 发布版本号必须使用 major.minor.patch 格式：$RELEASE_VERSION" >&2
    exit 1
  fi
  if [ "$RELEASE_VERSION" != "$CURRENT_VERSION" ]; then
    echo "error: 发布版本 $RELEASE_VERSION 与 AppVersion.current $CURRENT_VERSION 不一致" >&2
    exit 1
  fi
  NEW_VERSION="$CURRENT_VERSION"
  echo "发布版本号：$NEW_VERSION（不自动递增）"
else
  MAJOR="${CURRENT_VERSION%%.*}"
  REST="${CURRENT_VERSION#*.}"
  MINOR="${REST%%.*}"
  PATCH="${REST#*.}"
  NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
  sed -i '' "s|^\(    static let current = \"\)[^\"]*\"|\1$NEW_VERSION\"|" "$VERSION_FILE"
  echo "版本号：$CURRENT_VERSION -> $NEW_VERSION"
fi

MACOS_SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
BUILD_ARGUMENTS=(
  -c release
  --scratch-path "$BUILD_SCRATCH_PATH"
  --sdk "$MACOS_SDK_PATH"
  -Xcxx -isystem
  -Xcxx "$MACOS_SDK_PATH/usr/include/c++/v1"
)
if [ -n "$BUILD_TRIPLE" ]; then
  BUILD_ARGUMENTS+=(--triple "$BUILD_TRIPLE")
fi

swift build "${BUILD_ARGUMENTS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)
BINARY_PATH="$BIN_DIR/QuietPaper"

if [ ! -f "$BINARY_PATH" ]; then
  echo "error: 未找到构建产物 $BINARY_PATH" >&2
  exit 1
fi
if [ ! -f "$ICON_FILE" ]; then
  echo "error: 未找到应用图标 $ICON_FILE" >&2
  exit 1
fi
if [ -n "$EXPECTED_ARCH" ]; then
  ACTUAL_ARCHS=$(lipo -archs "$BINARY_PATH")
  if [[ " $ACTUAL_ARCHS " != *" $EXPECTED_ARCH "* ]]; then
    echo "error: 构建产物架构为 $ACTUAL_ARCHS，预期包含 $EXPECTED_ARCH" >&2
    exit 1
  fi
fi

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BINARY_PATH" "$CONTENTS_DIR/MacOS/QuietPaper"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ICON_FILE" "$CONTENTS_DIR/Resources/QuietPaper.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/QuietPaper"
CODESIGN_ARGUMENTS=(--force --deep --sign "$CODESIGN_IDENTITY")
if [ "$CODESIGN_IDENTITY" != "-" ]; then
  CODESIGN_ARGUMENTS+=(--options runtime --timestamp)
fi
codesign "${CODESIGN_ARGUMENTS[@]}" "$APP_DIR"

# 已存在的 app 包只更新 Contents 时，Finder 可能继续使用旧的图标与版本缓存。
# 刷新包目录时间并通知 Spotlight 重新读取 Info.plist，确保打包后立即显示最新元数据。
touch "$APP_DIR"
mdimport "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
