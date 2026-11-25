#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NexBar"
SCHEME="NexBar"
PROJECT="$ROOT_DIR/NexBar.xcodeproj"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="${BUILD_DIR:-/tmp/NexBarReleaseBuild}"
VERSION=""
ARCH="arm64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --arch)
      ARCH="${2:-arm64}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -n 's/.*"MARKETING_VERSION"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PROJECT/project.xcproj" | head -n 1)"
  VERSION="${VERSION:-1.0.0}"
fi
# Strip optional leading 'v' from tag versions (e.g., v1.0.0 -> 1.0.0)
VERSION="${VERSION#v}"

echo "==> Building $APP_NAME $VERSION ($ARCH, Release)..."
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

XCODEBUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Release
  -derivedDataPath "$BUILD_DIR"
  -destination "platform=macOS,arch=$ARCH"
  MARKETING_VERSION="$VERSION"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  DEVELOPMENT_TEAM=""
  build
)

xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: Built app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Signing $APP_NAME.app (ad-hoc for direct non-App-Store distribution)..."
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGE_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_NAME="$APP_NAME-$VERSION-$ARCH.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Generating SHA-256 checksum..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "==> Done!"
ls -lh "$DIST_DIR"
cat "$DIST_DIR/$DMG_NAME.sha256"
