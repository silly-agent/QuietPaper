#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
VERSION="${1:-}"
TARGET="${2:-}"
OUTPUT_DIR="${QUIETPAPER_RELEASE_OUTPUT_DIR:-$PROJECT_DIR/release}"

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: $0 <major.minor.patch> <apple-silicon|intel>" >&2
  exit 1
fi

case "$TARGET" in
  apple-silicon)
    APP_NAME="QuietPaper.app"
    EXPECTED_ARCH="arm64"
    ASSET_ARCH="Apple-Silicon"
    BUILD_SCRIPT="$PROJECT_DIR/scripts/build-app.sh"
    ;;
  intel)
    APP_NAME="QuietPaper-Intel.app"
    EXPECTED_ARCH="x86_64"
    ASSET_ARCH="Intel"
    BUILD_SCRIPT="$PROJECT_DIR/scripts/build-app-intel.sh"
    ;;
  *)
    echo "usage: $0 <major.minor.patch> <apple-silicon|intel>" >&2
    exit 1
    ;;
esac

export QUIETPAPER_RELEASE_VERSION="$VERSION"
export QUIETPAPER_EXPECTED_ARCH="$EXPECTED_ARCH"
"$BUILD_SCRIPT"

APP_PATH="$PROJECT_DIR/dist/$APP_NAME"
BINARY_PATH="$APP_PATH/Contents/MacOS/QuietPaper"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
ARCHIVE_NAME="QuietPaper-$VERSION-macOS-$ASSET_ARCH.zip"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
NOTARY_ARCHIVE="$OUTPUT_DIR/QuietPaper-$VERSION-$TARGET-notarization.zip"

ACTUAL_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")
if [ "$ACTUAL_VERSION" != "$VERSION" ]; then
  echo "error: app 版本为 $ACTUAL_VERSION，预期为 $VERSION" >&2
  exit 1
fi

ACTUAL_ARCHS=$(lipo -archs "$BINARY_PATH")
if [[ " $ACTUAL_ARCHS " != *" $EXPECTED_ARCH "* ]]; then
  echo "error: app 架构为 $ACTUAL_ARCHS，预期包含 $EXPECTED_ARCH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
mkdir -p "$OUTPUT_DIR"

NOTARY_VALUES=("${APPLE_ID:-}" "${APPLE_APP_PASSWORD:-}" "${APPLE_TEAM_ID:-}")
NOTARY_VALUE_COUNT=0
for VALUE in "${NOTARY_VALUES[@]}"; do
  if [ -n "$VALUE" ]; then
    NOTARY_VALUE_COUNT=$((NOTARY_VALUE_COUNT + 1))
  fi
done
if [ "$NOTARY_VALUE_COUNT" -ne 0 ] && [ "$NOTARY_VALUE_COUNT" -ne 3 ]; then
  echo "error: 公证需要同时配置 APPLE_ID、APPLE_APP_PASSWORD 与 APPLE_TEAM_ID" >&2
  exit 1
fi
if [ "$NOTARY_VALUE_COUNT" -eq 3 ]; then
  if [ "${QUIETPAPER_CODESIGN_IDENTITY:--}" = "-" ]; then
    echo "error: 公证需要 Developer ID Application 签名" >&2
    exit 1
  fi
  rm -f "$NOTARY_ARCHIVE"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ARCHIVE"
  xcrun notarytool submit "$NOTARY_ARCHIVE" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$NOTARY_ARCHIVE"
fi

rm -f "$ARCHIVE_PATH" "$ARCHIVE_PATH.sha256"
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")

echo "$ARCHIVE_PATH"
echo "$ARCHIVE_PATH.sha256"
