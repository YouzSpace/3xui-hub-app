#!/bin/bash
set -euo pipefail

# Build script for tun2socks (Go version) with 16KB page size support
# This is required for Android 15+ compatibility

# Configuration
TUN2SOCKS_REPO="https://github.com/xjasonlyu/tun2socks"
TARGET_DIR="${TARGET_DIR:-../../../android_runtime/xray_android/src/main/jniLibs}"
NDK_PATH="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"

# Check NDK
if [ ! -d "$NDK_PATH" ]; then
    echo "Error: NDK not found at $NDK_PATH"
    echo "Please export ANDROID_NDK_HOME pointing to your NDK installation."
    exit 1
fi

echo "Using NDK at: $NDK_PATH"

case "$(uname -s)" in
    Darwin) TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/darwin-x86_64" ;;
    Linux) TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64" ;;
    *) echo "Error: unsupported host OS $(uname -s)"; exit 1 ;;
esac
if [ ! -d "$TOOLCHAIN" ]; then
    echo "Error: NDK toolchain not found at $TOOLCHAIN"
    echo "Please check ANDROID_NDK_HOME and host OS."
    exit 1
fi

# Clone tun2socks if not exists
if [ ! -d "tun2socks-go" ]; then
    echo "Cloning tun2socks (Go version)..."
    git clone "$TUN2SOCKS_REPO" tun2socks-go
else
    echo "tun2socks-go directory exists, pulling latest..."
    cd tun2socks-go && git pull && cd ..
fi

# Build Function
build_tun2socks() {
    local ARCH_NAME=$1
    local GO_ARCH=$2
    local GO_ARM=$3
    local ANDROID_TARGET=$4
    local OUTPUT_DIR="${TARGET_DIR}/${ARCH_NAME}"

    echo "Building tun2socks for ${ARCH_NAME}..."
    
    mkdir -p "$OUTPUT_DIR"

    export CGO_ENABLED=1
    export GOOS=android
    export GOARCH=$GO_ARCH
    export GOARM=$GO_ARM
    
    export CC="${TOOLCHAIN}/bin/${ANDROID_TARGET}-clang"
    export CXX="${TOOLCHAIN}/bin/${ANDROID_TARGET}-clang++"
    
    # Verify compiler exists
    if [ ! -f "$CC" ]; then
        echo "Error: Compiler not found at $CC"
        return 1
    fi

    cd tun2socks-go
    
    # Build with 16KB page alignment - same flags as xray
    go build -v -trimpath -ldflags "-s -w -buildid= -linkmode=external -extldflags '-Wl,-z,max-page-size=16384'" -buildmode=pie -o "../${OUTPUT_DIR}/libtun2socks.so" .

    echo "Success: ${OUTPUT_DIR}/libtun2socks.so created."

    # Verify 16KB alignment
    if [ -x "${TOOLCHAIN}/bin/llvm-readelf" ]; then
        echo "Verifying 16KB alignment:"
        ALIGN=$("${TOOLCHAIN}/bin/llvm-readelf" -l "../${OUTPUT_DIR}/libtun2socks.so" | grep "LOAD" | head -1 | awk '{print $NF}')
        if [ "$ALIGN" = "0x4000" ]; then
            echo "Alignment: $ALIGN (16KB) - correct"
        else
            echo "Warning: alignment is $ALIGN; expected 0x4000"
        fi
    fi

    cd ..
}

# Build for Architectures
echo "Building tun2socks (Go version) with 16KB page size support..."

# ARM64
if [ "${TUN2SOCKS_BUILD_ARM64:-1}" = "1" ]; then
    build_tun2socks "arm64-v8a" "arm64" "" "aarch64-linux-android21"
fi

# ARMv7
if [ "${TUN2SOCKS_BUILD_ARMV7:-1}" = "1" ]; then
    build_tun2socks "armeabi-v7a" "arm" "7" "armv7a-linux-androideabi21"
fi

# x86 is included in the main runtime AAR.
if [ "${TUN2SOCKS_BUILD_X86:-1}" = "1" ]; then
    build_tun2socks "x86" "386" "" "i686-linux-android21"
fi

# x86_64 is included in the main runtime AAR.
if [ "${TUN2SOCKS_BUILD_X86_64:-1}" = "1" ]; then
    build_tun2socks "x86_64" "amd64" "" "x86_64-linux-android21"
fi

echo ""
echo "========================================="
echo "Build process finished!"
echo "========================================="
echo ""
echo "Verification:"
echo "Run this command to check all libraries:"
echo ""
echo "for arch in armeabi-v7a arm64-v8a x86 x86_64; do"
echo "  echo \"=== \$arch ===\";"
echo "  ${TOOLCHAIN}/bin/llvm-readelf -l ${TARGET_DIR}/\$arch/libtun2socks.so | grep LOAD | head -1;"
echo "done"
