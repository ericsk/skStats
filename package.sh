#!/usr/bin/env bash
#
# package.sh - Build, package, and install skStats macOS Release App
#

set -euo pipefail

# Directory locations
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/Release"
INFO_PLIST="${PROJECT_ROOT}/skStats/Info.plist"
XCODEPROJ="${PROJECT_ROOT}/skStats.xcodeproj"
APPLICATIONS_DIR="/Applications"
DEST_APP="${APPLICATIONS_DIR}/skStats.app"

# Terminal ANSI colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

INSTALL_TO_APPS=true
OPEN_WHEN_DONE=false
RUN_WHEN_DONE=false
VERBOSE=false

show_help() {
    cat << EOF
Usage: ./package.sh [options]

Builds skStats in Release configuration (Universal binary: arm64 & x86_64),
packages it into a distributable ZIP, and copies it to /Applications.

Options:
  -n, --no-install   Skip copying skStats.app to /Applications
  -o, --open         Open the build/Release directory in Finder upon completion
  -r, --run          Launch skStats.app upon completion
  -v, --verbose      Show verbose xcodebuild output
  -h, --help         Show this help message

Output:
  build/Release/skStats.app
  build/Release/skStats.app.zip
  build/Release/skStats.zip
  /Applications/skStats.app (unless --no-install is specified)
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--no-install)
            INSTALL_TO_APPS=false
            shift
            ;;
        -i|--install)
            INSTALL_TO_APPS=true
            shift
            ;;
        -o|--open)
            OPEN_WHEN_DONE=true
            shift
            ;;
        -r|--run)
            RUN_WHEN_DONE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Read app version from Info.plist
VERSION="1.0"
BUILD_NUM="1"
if [[ -f "$INFO_PLIST" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0")
    BUILD_NUM=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "1")
fi

echo -e "${BLUE}${BOLD}==============================================${NC}"
echo -e "${BLUE}${BOLD}  skStats Release Packager & Installer       ${NC}"
echo -e "${BLUE}${BOLD}  Version: v${VERSION} (Build ${BUILD_NUM})              ${NC}"
echo -e "${BLUE}${BOLD}==============================================${NC}"

# Clean existing Release build directory
echo -e "${YELLOW}🧹 Cleaning ${BUILD_DIR}...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xattr -w com.apple.xcode.CreatedByBuildSystem true "$BUILD_DIR" 2>/dev/null || true

# Build project with xcodebuild
echo -e "${YELLOW}🔨 Compiling skStats (Release, Universal arm64+x86_64)...${NC}"
XCODEBUILD_ARGS=(
    build
    -project "$XCODEPROJ"
    -scheme skStats
    -configuration Release
    -destination "generic/platform=macOS"
    CONFIGURATION_BUILD_DIR="$BUILD_DIR"
)

if [[ "$VERBOSE" == false ]]; then
    XCODEBUILD_ARGS+=(-quiet)
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="${BUILD_DIR}/skStats.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo -e "${RED}❌ Build failed: ${APP_PATH} was not found.${NC}"
    exit 1
fi

# Package into ZIP archives (preserves macOS metadata, symlinks, codesign)
echo -e "${YELLOW}📦 Packaging application into zip archives...${NC}"
ZIP_PATH="${BUILD_DIR}/skStats.app.zip"
ZIP_COMPAT_PATH="${BUILD_DIR}/skStats.zip"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
cp "$ZIP_PATH" "$ZIP_COMPAT_PATH"

# Calculate checksum and file size
FILE_SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

# Copy to /Applications
INSTALLED_PATH=""
if [[ "$INSTALL_TO_APPS" == true ]]; then
    echo -e "${YELLOW}📂 Copying to ${DEST_APP}...${NC}"
    if rm -rf "$DEST_APP" 2>/dev/null && ditto "$APP_PATH" "$DEST_APP" 2>/dev/null; then
        INSTALLED_PATH="$DEST_APP"
        echo -e "${GREEN}✓ Successfully copied to ${DEST_APP}${NC}"
    elif sudo rm -rf "$DEST_APP" 2>/dev/null && sudo ditto "$APP_PATH" "$DEST_APP" 2>/dev/null; then
        INSTALLED_PATH="$DEST_APP"
        echo -e "${GREEN}✓ Successfully copied to ${DEST_APP} (via sudo)${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not copy to ${DEST_APP} directly. Please check permissions or run with sudo.${NC}"
    fi
fi

echo -e "${GREEN}${BOLD}==============================================${NC}"
echo -e "${GREEN}${BOLD}  Release Package Complete! 🎉                ${NC}"
echo -e "${GREEN}${BOLD}==============================================${NC}"
echo -e "  ${BOLD}App Bundle:${NC}   ${APP_PATH}"
echo -e "  ${BOLD}Zip Archive:${NC}  ${ZIP_PATH} (${FILE_SIZE})"
echo -e "  ${BOLD}SHA-256:${NC}      ${SHA256}"
if [[ -n "$INSTALLED_PATH" ]]; then
    echo -e "  ${BOLD}Installed:${NC}    ${INSTALLED_PATH}"
fi
echo ""

if [[ "$OPEN_WHEN_DONE" == true ]]; then
    open "$BUILD_DIR"
fi

if [[ "$RUN_WHEN_DONE" == true ]]; then
    TARGET_LAUNCH="${INSTALLED_PATH:-$APP_PATH}"
    echo -e "${BLUE}🚀 Launching ${TARGET_LAUNCH}...${NC}"
    open "$TARGET_LAUNCH"
fi
