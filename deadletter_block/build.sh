#!/bin/bash
# Build BlockDeadLetter.dylib for iOS arm64 (requires Xcode on macOS)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/BlockDeadLetter.dylib"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MIN_IOS="${MIN_IOS:-14.0}"

xcrun -sdk iphoneos clang -dynamiclib \
  -arch arm64 \
  -miphoneos-version-min="$MIN_IOS" \
  -isysroot "$SDK" \
  -fobjc-arc \
  -O2 \
  -framework Foundation \
  -install_name "@rpath/BlockDeadLetter.dylib" \
  -o "$OUT" \
  "$ROOT/BlockDeadLetter.m"

echo "Built: $OUT"
echo
echo "Next (on a re-sign / jailbreak workflow you already use):"
echo "  1. Copy BlockDeadLetter.dylib into FomoPeek.app/Frameworks/"
echo "  2. insert_dylib '@rpath/BlockDeadLetter.dylib' FomoPeek.app/FomoPeek"
echo "  3. Re-sign the app bundle"
echo "  4. Console: filter 'BlockDeadLetter' to confirm rewrite logs"
