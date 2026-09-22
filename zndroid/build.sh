#!/bin/bash
# Zndroid build script
# Builds the Z80 binary and runs the Python toolchain test

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
TOOLS_DIR="$SCRIPT_DIR/tools"

echo "=== Zndroid Build ==="

# Build Z80 binary
echo "[1/2] Assembling Z80 binary..."
cd "$BUILD_DIR"
make clean 2>/dev/null || true
make 2>&1 | grep -v "UserWarning\|pkg_resources\|Setuptools"
echo "  -> $(ls -la bin/root/bin/zndroid-launcher 2>/dev/null | awk '{print $5, $9}')"

# Test Python toolchain
echo "[2/2] Testing TinyJ toolchain..."
cd "$TOOLS_DIR"
python3 run_example.py

echo ""
echo "Build complete."
