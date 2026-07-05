#!/bin/bash
# Build script for ESurfing Daemon Magisk module
#
# Prerequisites:
#   - Android NDK r27+ installed (set ANDROID_NDK_HOME, or download automatically)
#   - CMake 3.18+
#   - Basic build tools (make, git, etc.)
#
# Usage:
#   ./build.sh                    # Build for arm64-v8a (default)
#   ./build.sh --abi arm64        # Explicitly set ABI
#   ./build.sh --module-only      # Repackage module from existing binary
#   ./build.sh --clean            # Clean build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_DIR="$SCRIPT_DIR/module"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Default ABI
ABI="arm64-v8a"
### Variables:
# - ANDROID_HOME / ANDROID_SDK_ROOT: path to Android SDK (needed for APK build)
# - ANDROID_NDK_HOME: path to Android NDK (auto-downloaded if not set)
NDK_VERSION="r27c"
CMAKE_VERSION="3.22.1"

# Parse args
CLEAN=0
MODULE_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --abi) ABI="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --module-only) MODULE_ONLY=1; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Map ABI to NDK target
case "$ABI" in
  arm64-v8a|arm64) NDK_ABI="arm64-v8a"; NDK_TARGET="aarch64-linux-android"; ARCH="arm64" ;;
  armeabi-v7a|arm)  NDK_ABI="armeabi-v7a"; NDK_TARGET="armv7a-linux-androideabi"; ARCH="arm" ;;
  x86_64)          NDK_ABI="x86_64"; NDK_TARGET="x86_64-linux-android"; ARCH="x86_64" ;;
  x86)             NDK_ABI="x86"; NDK_TARGET="i686-linux-android"; ARCH="x86" ;;
  *) echo "Unsupported ABI: $ABI"; exit 1 ;;
esac

echo "=== ESurfing Daemon Magisk Module Build ==="
echo "ABI:        $ABI"
echo "Target:     $NDK_TARGET"
echo "Build dir:  $BUILD_DIR"
echo "Output dir: $OUTPUT_DIR"

# Download NDK if not present
if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  NDK_DIR="$SCRIPT_DIR/.ndk/android-ndk-$NDK_VERSION"
  if [ ! -d "$NDK_DIR" ]; then
    echo "ANDROID_NDK_HOME not set, downloading NDK $NDK_VERSION..."
    mkdir -p "$SCRIPT_DIR/.ndk"
    pushd "$SCRIPT_DIR/.ndk"
    NDK_ZIP="android-ndk-${NDK_VERSION}-linux.zip"
    if [ ! -f "$NDK_ZIP" ]; then
      curl -L -o "$NDK_ZIP" "https://dl.google.com/android/repository/${NDK_ZIP}"
    fi
    unzip -q "$NDK_ZIP"
    popd
  fi
  export ANDROID_NDK_HOME="$NDK_DIR"
  echo "Using NDK at: $ANDROID_NDK_HOME"
fi

# Build binary
if [ "$MODULE_ONLY" -eq 0 ]; then
  if [ "$CLEAN" -eq 1 ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
  fi

  TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
  if [ ! -f "$TOOLCHAIN_FILE" ]; then
    echo "ERROR: NDK toolchain file not found at $TOOLCHAIN_FILE"
    exit 1
  fi

  echo "Configuring CMake..."
  cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
    -DANDROID_ABI="$NDK_ABI" \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_STL=none \
    -DCMAKE_BUILD_TYPE=MinSizeRel

  echo "Building..."
  cmake --build "$BUILD_DIR" --target esurfingd -j$(nproc)

  BINARY="$BUILD_DIR/esurfingd"
  if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed, binary not found"
    exit 1
  fi

  echo "Stripping symbols..."
  "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" "$BINARY"

  file "$BINARY"
  echo "Binary size: $(stat -c%s "$BINARY" 2>/dev/null || stat -f%z "$BINARY" 2>/dev/null) bytes"
fi

# Package module
echo ""
echo "Packaging Magisk module..."

# 自动生成版本号（本地构建用日期，CI 会用 github.run_number）
LOCAL_VERSION="v1.0.$(date +%Y%m%d)"
LOCAL_VERSION_CODE="$(date +%Y%m%d)"
sed -i "s/^version=.*/version=$LOCAL_VERSION/" "$MODULE_DIR/module.prop"
sed -i "s/^versionCode=.*/versionCode=$LOCAL_VERSION_CODE/" "$MODULE_DIR/module.prop"
echo "Module version set to $LOCAL_VERSION (code $LOCAL_VERSION_CODE)"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$MODULE_DIR/portal"
mkdir -p "$MODULE_DIR/system/app/ESurfingUI"

# Copy binary
BINARY_SRC="${BUILD_DIR}/esurfingd"
if [ -f "$BINARY_SRC" ]; then
  cp "$BINARY_SRC" "$MODULE_DIR/esurfingd"
elif [ "$MODULE_ONLY" -eq 0 ]; then
  echo "ERROR: binary not found at $BINARY_SRC"
  exit 1
else
  echo "WARNING: no binary found at $BINARY_SRC, skipping binary copy"
fi

# Copy portal files
cp "$SCRIPT_DIR/portal/index.html" "$MODULE_DIR/portal/"

# Copy WebView APK if built
if [ -f "$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk" ]; then
  cp "$SCRIPT_DIR/app/build/outputs/apk/debug/app-debug.apk" "$MODULE_DIR/system/app/ESurfingUI/"
  echo "WebView APK included"
fi

# Set permissions
chmod 755 "$MODULE_DIR/service.sh" "$MODULE_DIR/uninstall.sh" "$MODULE_DIR/customize.sh" 2>/dev/null || true
chmod 755 "$MODULE_DIR/esurfingd" 2>/dev/null || true

# Create module zip
MODULE_ZIP="$OUTPUT_DIR/esurfing-daemon-${ABI}.zip"
rm -f "$MODULE_ZIP"

pushd "$MODULE_DIR" > /dev/null
zip -r9 "$MODULE_ZIP" . \
  -x ".*" -x "*/.*" -x "*.md"
popd > /dev/null

echo ""
echo "=== Build Complete ==="
echo "Module: $MODULE_ZIP"
echo ""
echo "Install:"
echo "  1. Push to device: adb push $MODULE_ZIP /sdcard/"
echo "  2. Open Magisk Manager → Modules → Install from storage"
echo "  3. Reboot"
echo ""
echo "Configure:"
echo "  After install, edit /data/adb/esurfing/ESurfingClient.json"
echo "  Or access Web UI at http://192.168.100.1:8888/"
