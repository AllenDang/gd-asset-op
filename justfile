# gd-asset-op build and development tasks

# Default recipe - show available commands
default:
    @just --list

# Build the GDExtension library
build target="template_debug":
    scons target={{target}}

# Build release version
release:
    scons target=template_release

# Run integration tests
test godot="":
    #!/usr/bin/env bash
    set -e

    # Find Godot executable
    if [ -n "{{godot}}" ]; then
        GODOT="{{godot}}"
    elif command -v godot &> /dev/null; then
        GODOT="godot"
    elif command -v godot4 &> /dev/null; then
        GODOT="godot4"
    elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
        GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
    else
        echo "Error: Godot not found. Usage: just test /path/to/godot"
        exit 1
    fi

    echo "Using Godot: $GODOT"
    mkdir -p test/output
    "$GODOT" --headless --script test/integration_test.gd

# Run clang-tidy linter
lint fix="":
    #!/usr/bin/env bash
    set -e

    # Find clang-tidy
    if command -v clang-tidy &> /dev/null; then
        CLANG_TIDY="clang-tidy"
    elif [ -x "/opt/homebrew/opt/llvm/bin/clang-tidy" ]; then
        CLANG_TIDY="/opt/homebrew/opt/llvm/bin/clang-tidy"
    elif [ -x "/usr/local/opt/llvm/bin/clang-tidy" ]; then
        CLANG_TIDY="/usr/local/opt/llvm/bin/clang-tidy"
    else
        echo "Error: clang-tidy not found. Install: brew install llvm"
        exit 1
    fi

    FIX_FLAG=""
    if [ "{{fix}}" = "--fix" ]; then
        FIX_FLAG="--fix"
        echo "Running clang-tidy with auto-fix..."
    else
        echo "Running clang-tidy (use 'just lint --fix' to auto-fix)..."
    fi

    SOURCE_FILES=$(find src -name "*.cpp" -o -name "*.h" | grep -v "_impl\.cpp$")
    echo "Linting: $SOURCE_FILES"
    $CLANG_TIDY $FIX_FLAG $SOURCE_FILES

# Clean build artifacts
clean:
    rm -rf bin/
    rm -f src/*.os
    rm -f thirdparty/lame/libmp3lame/*.os
    rm -f thirdparty/basis_universal/**/*.os
    rm -f .sconsign.dblite
    rm -rf test/output/
    @echo "Cleaned build artifacts"

# Clean and rebuild
rebuild: clean build

# Show project info
info:
    @echo "gd-asset-op - Godot 4.x GDExtension"
    @echo ""
    @echo "Source files:"
    @ls -la src/*.cpp src/*.h 2>/dev/null || echo "  (none)"
    @echo ""
    @echo "Build output:"
    @ls -la bin/ 2>/dev/null || echo "  (not built)"
