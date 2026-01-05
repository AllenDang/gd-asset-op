#!/bin/bash
# Run gd-asset-op integration tests
#
# Usage: ./test/run_tests.sh [godot_path]
#
# If godot_path is not provided, will try to find Godot in common locations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find Godot executable
if [ -n "$1" ]; then
    GODOT="$1"
elif command -v godot &> /dev/null; then
    GODOT="godot"
elif command -v godot4 &> /dev/null; then
    GODOT="godot4"
elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "Error: Godot not found. Please provide path as argument or add to PATH."
    exit 1
fi

echo "Using Godot: $GODOT"
echo ""

# Check if test assets exist
if [ ! -f "$SCRIPT_DIR/assets/test.png" ]; then
    echo "Test assets not found. Generating..."
    echo ""

    # Try to generate assets with Python
    if command -v python3 &> /dev/null; then
        python3 "$SCRIPT_DIR/generate_test_assets.py"
    elif command -v python &> /dev/null; then
        python "$SCRIPT_DIR/generate_test_assets.py"
    else
        echo "Error: Python not found. Please generate test assets manually."
        exit 1
    fi

    echo ""
fi

# Ensure output directory exists
mkdir -p "$SCRIPT_DIR/output"

# Create minimal project.godot if it doesn't exist
if [ ! -f "$PROJECT_DIR/project.godot" ]; then
    echo "Creating minimal project.godot..."
    cat > "$PROJECT_DIR/project.godot" << 'EOF'
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]
config/name="gd-asset-op"
config/features=PackedStringArray("4.3")
EOF
fi

# Run tests
echo "Running integration tests..."
echo ""

cd "$PROJECT_DIR"
"$GODOT" --headless --script test/integration_test.gd

echo ""
echo "Tests complete."
