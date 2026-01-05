# gd-asset-op

A Godot 4.x GDExtension for asset conversion and metadata probing.

## Features

### Asset Conversion (Async)

- **Image to KTX2** - Convert PNG/JPEG to GPU-compressed KTX2 (UASTC + zstd)
- **Audio to MP3** - Convert WAV to MP3 with configurable bitrate
- **GLB Texture Optimization** - Convert embedded textures in GLB files to KTX2
- **Audio Normalization** - Normalize audio volume to target LUFS

### Asset Probing

- **GLB/GLTF** - Extract mesh info, AABB, skeleton, animations, materials, textures
- **KTX2** - Read dimensions, mip levels, compression format
- **Audio** - Get duration, sample rate, channels, bitrate, volume levels

## Requirements

- Godot 4.2+
- [just](https://github.com/casey/just) command runner
- C++17 compiler
- SCons

## Building

```bash
# Clone with submodules
git clone --recursive https://github.com/user/gd-asset-op.git
cd gd-asset-op

# Build debug
just build

# Build release
just release

# Clean build artifacts
just clean
```

## Usage

### GDScript API

```gdscript
# Get the converter singleton
var converter = AssetOP.get_converter()

# Connect signals
converter.conversion_completed.connect(_on_completed)
converter.conversion_progress.connect(_on_progress)

# Convert image to KTX2 (async)
var task_id = converter.image_to_ktx2("res://texture.png", "res://texture.ktx2", 128, true)

# Convert WAV to MP3 (async)
var task_id = converter.audio_to_mp3("res://sound.wav", "res://sound.mp3", 192)

# Convert GLB textures to KTX2 (async)
var task_id = converter.glb_textures_to_ktx2("res://model.glb", "res://model_optimized.glb")

# Normalize audio volume (async)
var task_id = converter.normalize_audio("res://sound.wav", "res://sound_normalized.wav", -14.0, -1.0)

# Signal handlers
func _on_completed(task_id: int, source: String, output: String, error: int, message: String):
    if error == OK:
        print("Converted: ", output)
    else:
        print("Error: ", message)

func _on_progress(task_id: int, source: String, progress: float):
    print("Progress: ", progress * 100, "%")
```

### Probing Assets

```gdscript
# Probe GLB file
var glb_info = AssetProbe.probe_glb("res://model.glb")
print("Faces: ", glb_info.face_count)
print("Vertices: ", glb_info.vertex_count)
print("AABB: ", glb_info.aabb)
print("Animations: ", glb_info.animations)

# Probe KTX2 file
var ktx2_info = AssetProbe.probe_ktx2("res://texture.ktx2")
print("Size: ", ktx2_info.width, "x", ktx2_info.height)
print("Mip levels: ", ktx2_info.mip_levels)
print("Compressed: ", ktx2_info.is_compressed)

# Probe audio file (MP3 only)
var audio_info = AssetProbe.probe_audio("res://sound.mp3", true)
print("Duration: ", audio_info.duration, "s")
print("Sample rate: ", audio_info.sample_rate)
print("Peak dB: ", audio_info.peak_db)
print("LUFS: ", audio_info.lufs)
```

### API Reference

#### AssetConverter

| Method | Description |
|--------|-------------|
| `image_to_ktx2(source, output, quality=128, mipmaps=true)` | Convert PNG/JPEG to KTX2 |
| `audio_to_mp3(source, output, bitrate=192)` | Convert WAV to MP3 |
| `glb_textures_to_ktx2(source, output="", quality=128, mipmaps=true)` | Optimize GLB textures |
| `normalize_audio(source, output, target_db=-14.0, peak_limit_db=-1.0)` | Normalize audio |
| `cancel(task_id)` | Cancel a pending task |
| `cancel_all()` | Cancel all pending tasks |
| `is_running()` | Check if tasks are running |
| `get_pending_count()` | Get number of pending tasks |

#### Signals

| Signal | Parameters |
|--------|------------|
| `conversion_started` | `task_id: int, source_path: String` |
| `conversion_progress` | `task_id: int, source_path: String, progress: float` |
| `conversion_completed` | `task_id: int, source_path: String, output_path: String, error: int, error_message: String` |

#### AssetProbe

| Method | Returns |
|--------|---------|
| `probe_glb(path)` | `{face_count, vertex_count, aabb, has_skeleton, bone_count, animations, materials, textures, ...}` |
| `probe_ktx2(path)` | `{width, height, depth, layers, mip_levels, format, is_compressed, compression_scheme, has_alpha, ...}` |
| `probe_audio(path, analyze_volume)` | `{duration, sample_rate, channels, bit_depth, format, bitrate, size_bytes, peak_db, rms_db, lufs}` |

## Development

```bash
# Run linter
just lint

# Auto-fix lint issues
just lint --fix

# Run tests
just test

# Show all commands
just
```

## Third-Party Libraries

- [godot-cpp](https://github.com/godotengine/godot-cpp) - Godot C++ bindings
- [basis_universal](https://github.com/BinomialLLC/basis_universal) - KTX2/UASTC texture compression
- [LAME](https://lame.sourceforge.io/) - MP3 encoding
- [dr_libs](https://github.com/mackron/dr_libs) - Audio decoding (WAV, MP3)
- [cgltf](https://github.com/jkuhlmann/cgltf) - GLB/GLTF parsing

## License

MIT
