#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

export QUIETPAPER_APP_BUNDLE_NAME="QuietPaper-Intel.app"
export QUIETPAPER_BUILD_SCRATCH_PATH="$PROJECT_DIR/.build-intel"
export QUIETPAPER_BUILD_TRIPLE="x86_64-apple-macosx13.0"
export QUIETPAPER_EXPECTED_ARCH="x86_64"

exec "$PROJECT_DIR/scripts/build-app.sh"
