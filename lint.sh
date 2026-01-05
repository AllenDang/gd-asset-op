#!/bin/bash
# Run clang-tidy on project source files
# Usage: ./lint.sh [--fix]

set -e

cd "$(dirname "$0")"

FIX_FLAG=""
if [ "$1" = "--fix" ]; then
    FIX_FLAG="--fix"
    echo "Running clang-tidy with auto-fix enabled..."
else
    echo "Running clang-tidy (use --fix to auto-fix issues)..."
fi

# Only lint our own source files, not third-party code
SOURCE_FILES=$(find src -name "*.cpp" -o -name "*.h" | grep -v "_impl\.cpp$")

# Find clang-tidy (check common Homebrew locations)
CLANG_TIDY=""
if command -v clang-tidy &> /dev/null; then
    CLANG_TIDY="clang-tidy"
elif [ -x "/opt/homebrew/opt/llvm/bin/clang-tidy" ]; then
    CLANG_TIDY="/opt/homebrew/opt/llvm/bin/clang-tidy"
elif [ -x "/usr/local/opt/llvm/bin/clang-tidy" ]; then
    CLANG_TIDY="/usr/local/opt/llvm/bin/clang-tidy"
else
    echo "Error: clang-tidy not found. Install with:"
    echo "  macOS:  brew install llvm"
    echo "  Ubuntu: sudo apt install clang-tidy"
    exit 1
fi

echo "Using: $CLANG_TIDY"

echo "Linting files:"
echo "$SOURCE_FILES" | tr ' ' '\n' | sed 's/^/  /'
echo ""

# Run clang-tidy
$CLANG_TIDY $FIX_FLAG $SOURCE_FILES

echo ""
echo "Lint complete."
