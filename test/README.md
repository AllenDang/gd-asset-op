# Integration Tests for gd-asset-op

This directory contains integration tests for the gd-asset-op GDExtension.

## Quick Start

```bash
# From project root
./test/run_tests.sh
```

Or specify a custom Godot path:

```bash
./test/run_tests.sh /path/to/godot
```

## Manual Setup

### 1. Generate Test Assets

```bash
# Requires Python 3 with Pillow
pip install Pillow numpy

# Generate assets
python3 test/generate_test_assets.py
```

This creates:
- `test/assets/test.png` - Gradient PNG image (256x256)
- `test/assets/test.jpg` - Checkerboard JPEG image (256x256)
- `test/assets/test.wav` - 2-second sine wave audio
- `test/assets/test.mp3` - MP3 version of the WAV (requires ffmpeg/lame)
- `test/assets/test.glb` - Simple triangle mesh with embedded PNG texture

### 2. Run Tests

```bash
godot --headless --script test/integration_test.gd
```

## Test Coverage

### Probe Tests

| Test | Description |
|------|-------------|
| `probe_glb` | Validates GLB metadata extraction (faces, vertices, animations, etc.) |
| `probe_ktx2` | Validates KTX2 texture info (dimensions, format, compression) |
| `probe_audio` | Validates MP3 metadata extraction (duration, sample rate, channels) |
| `probe_audio (volume)` | Tests volume analysis (peak_db, rms_db, lufs) |
| `probe_audio (wrong format)` | Verifies rejection of non-MP3 files |

### Conversion Tests

| Test | Description |
|------|-------------|
| `image_to_ktx2 (PNG)` | Converts PNG to KTX2 |
| `image_to_ktx2 (JPEG)` | Converts JPEG to KTX2 |
| `audio_to_mp3` | Converts WAV to MP3 |
| `normalize_audio` | Normalizes WAV volume |
| `glb_textures_to_ktx2` | Converts GLB embedded textures to KTX2 in-place |
| `cancel` | Tests task cancellation |
| `file not found` | Verifies error handling for missing files |

## Directory Structure

```
test/
├── README.md                  # This file
├── run_tests.sh              # Test runner script
├── generate_test_assets.py   # Asset generation script
├── integration_test.gd       # GDScript test suite
├── assets/                   # Test input files
│   ├── test.png
│   ├── test.jpg
│   ├── test.wav
│   ├── test.mp3
│   └── test.glb
└── output/                   # Test output files (auto-cleaned)
```

## Expected Output

```
============================================================
gd-asset-op Integration Tests
============================================================

Running Probe Tests...
----------------------------------------
  [TEST] probe_glb
    [PASS] probe_glb returned valid structure with 1 faces, 3 vertices
  [TEST] probe_ktx2 (file not found)
    [PASS] Correctly returned error for missing file
  [TEST] probe_audio
    [PASS] probe_audio: 2.00s, 44100Hz, 1 channels, 192 kbps
  [TEST] probe_audio (with volume analysis)
    [PASS] Volume: peak=-6.0 dB, rms=-9.5 dB, lufs=-10.2
  [TEST] probe_audio (wrong format)
    [PASS] Correctly rejected non-MP3 file

Running Conversion Tests...
----------------------------------------
  [TEST] image_to_ktx2 (PNG)
    [PASS] Output: test_png.ktx2 (12345 bytes)
  [TEST] image_to_ktx2 (JPEG)
    [PASS] Output: test_jpg.ktx2 (12345 bytes)
  [TEST] audio_to_mp3
    [PASS] Output: test_converted.mp3 (48234 bytes)
  [TEST] normalize_audio
    [PASS] Output: test_normalized.wav (176444 bytes)
  [TEST] glb_textures_to_ktx2
    [PASS] Output: test_ktx2.glb (5678 bytes)
    Output GLB has valid magic number
  [TEST] cancel
    [PASS] Successfully cancelled task
  [TEST] file not found error
    [PASS] Correctly failed: Source file not found: /nonexistent/file.png
  [TEST] probe_ktx2
    [PASS] KTX2: 256x256, 9 mips, format=UNDEFINED, compressed=true

============================================================
Test Summary
============================================================
Total:  12
Passed: 12
Failed: 0
============================================================
ALL TESTS PASSED!
```

## Troubleshooting

### "Missing test assets"

Run the asset generation script:
```bash
python3 test/generate_test_assets.py
```

### "Godot not found"

Specify the path to your Godot executable:
```bash
./test/run_tests.sh /path/to/godot
```

### MP3 generation fails

Install ffmpeg or lame:
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt install ffmpeg
```

Or manually provide a test MP3 file in `test/assets/test.mp3`.
