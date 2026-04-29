#!/usr/bin/env bash
# build.sh — builds SecurityMiscPlugin.so against LLVM/Clang 21
# Tested on Arch Linux with the llvm21 + clang21 packages.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LLVM21="/usr/lib/llvm21"
CLANG21="$LLVM21/bin/clang"
CLANGXX21="$LLVM21/bin/clang++"
CLANG_TIDY21="$LLVM21/bin/clang-tidy"

if [[ ! -x "$CLANG21" ]]; then
  echo "[ERROR] LLVM 21 not found at $LLVM21"
  echo "        Install with: sudo pacman -S llvm21 clang21"
  exit 1
fi

echo "=== Building thesis checker plugin ==="
echo "    LLVM:  $("$LLVM21/bin/llvm-config" --version)"
echo "    Clang: $("$CLANG21" --version | head -1)"

if [[ ! -f "$ROOT/build/build.ninja" ]]; then
  echo "--- Configuring with CMake ---"
  cmake -S "$ROOT/src" -B "$ROOT/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_C_COMPILER="$CLANG21" \
    -DCMAKE_CXX_COMPILER="$CLANGXX21" \
    -DLLVM_DIR="$LLVM21/lib/cmake/llvm" \
    -DClang_DIR="$LLVM21/lib/cmake/clang" \
    -DCMAKE_PREFIX_PATH="$LLVM21"
fi

echo "--- Building ---"
ninja -C "$ROOT/build"

echo ""
echo "=== Build complete ==="
echo "    Plugin: $ROOT/build/SecurityMiscPlugin.so"
echo ""
echo "To verify the plugin loads:"
echo "    $CLANG_TIDY21 -load $ROOT/build/SecurityMiscPlugin.so -checks='*' -list-checks 2>/dev/null | grep security-misc"
