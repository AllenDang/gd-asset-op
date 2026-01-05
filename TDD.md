# Technical Design Document - Godot Asset OP

## Overview

Godot Asset OP is a GDExtension that provides asset conversion and metadata probing capabilities for Godot 4.x projects.

---

## Dependencies Analysis

### Features with Godot-cpp Built-in Support

| Feature | Godot-cpp Capability |
|---------|---------------------|
| Image loading (PNG, JPG, etc.) | `Image` class can load common formats |
| Basic audio properties | `AudioStream` classes provide duration info |
| AABB calculation | `AABB` class available, mesh data accessible |

### Features Requiring Third-Party Libraries

| Feature | Required Library | Reason |
|---------|-----------------|--------|
| **1.1** Image → KTX2 | `libktx` or `basis_universal` | KTX2 encoding not in Godot |
| **1.2** Audio → MP3 | `lame` (encoder) + decoders | MP3 encoding not in Godot |
| **1.3** GLB texture → KTX2 | `tinygltf` + `libktx`/`basis_universal` | GLB parsing + KTX2 encoding |
| **1.4** Audio volume balance | Audio decoder libs + DSP analysis | Volume analysis/normalization |
| **2.1** GLB metadata probe | `tinygltf` or `cgltf` | Direct GLB/GLTF parsing |
| **2.2** KTX2 size probe | `libktx` | KTX2 header parsing |
| **2.3** Audio length/volume | Format-specific decoders | Audio analysis |

### Recommended Third-Party Libraries

| Library | Purpose | License |
|---------|---------|---------|
| `basis_universal` | KTX2/Basis texture encoding | MIT |
| `tinygltf` | GLB/GLTF parsing (header-only) | MIT |
| `cgltf` | Alternative GLB/GLTF parsing (single header) | MIT |
| `lame` | MP3 encoding | LGPL |
| `dr_libs` | Audio decoding (WAV/MP3/FLAC, single-header) | Public Domain |
| `miniaudio` | Alternative audio decoding | Public Domain |

---

## Path Requirements

All file paths (`source_path`, `output_path`, `file_path`) must be **absolute file system paths**. Godot internal paths like `res://` or `user://` are **not supported**.

```gdscript
# Correct
converter.image_to_ktx2("/home/user/project/textures/hero.png", "/home/user/project/textures/hero.ktx2")

# Incorrect - will fail
converter.image_to_ktx2("res://textures/hero.png", "res://textures/hero.ktx2")
```

Use `ProjectSettings.globalize_path()` to convert Godot paths if needed:
```gdscript
var abs_source = ProjectSettings.globalize_path("res://textures/hero.png")
var abs_output = ProjectSettings.globalize_path("res://textures/hero.ktx2")
converter.image_to_ktx2(abs_source, abs_output)
```

---

## GDExtension Interface Design

### Class Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         AssetOP                             │
│                   (Singleton / Autoload)                    │
├─────────────────────────────────────────────────────────────┤
│ + get_converter() -> AssetConverter                         │
│ + get_probe() -> AssetProbe                                 │
│ + to_ktx2(source, output) -> Error                          │
│ + to_mp3(source, output) -> Error                           │
│ + probe(file_path) -> Dictionary                            │
└─────────────────────────────────────────────────────────────┘
                │                       │
                ▼                       ▼
┌───────────────────────────────────┐  ┌───────────────────────────┐
│        AssetConverter             │  │       AssetProbe          │
│         (RefCounted)              │  │      (RefCounted)         │
├───────────────────────────────────┤  ├───────────────────────────┤
│ Signals:                          │  │ + probe_glb() -> Dict     │
│  - conversion_started             │  │ + probe_ktx2() -> Dict    │
│  - conversion_progress            │  │ + probe_audio() -> Dict   │
│  - conversion_completed           │  └───────────────────────────┘
│  - batch_completed                │
├───────────────────────────────────┤
│ Conversion Methods (async):       │
│  + image_to_ktx2()                │
│  + audio_to_mp3()                 │
│  + glb_textures_to_ktx2()         │
│  + normalize_audio()              │
│  + convert_batch()                │
├───────────────────────────────────┤
│ Control Methods:                  │
│  + cancel()                       │
│  + cancel_all()                   │
│  + is_running() -> bool           │
│  + get_pending_count() -> int     │
└───────────────────────────────────┘
                │
                ▼
┌───────────────────────────┐
│    ConversionTask         │
│      (RefCounted)         │
├───────────────────────────┤
│ + id: int                 │
│ + type: Type              │
│ + source_path: String     │
│ + output_path: String     │
│ + options: Dictionary     │
├───────────────────────────┤
│ + create_image_to_ktx2()  │
│ + create_audio_to_mp3()   │
│ + create_glb_to_ktx2()    │
│ + create_normalize_audio()│
└───────────────────────────┘
```

---

## Class Specifications

### AssetConverter

Handles all conversion operations asynchronously with signal-based progress and completion notifications.

```gdscript
class_name AssetConverter extends RefCounted

# ============================================================
# Signals
# ============================================================

## Emitted when a conversion task starts
## task_id: unique identifier for this conversion
signal conversion_started(task_id: int, source_path: String)

## Emitted periodically during conversion with progress updates
## progress: 0.0 to 1.0
signal conversion_progress(task_id: int, source_path: String, progress: float)

## Emitted when a single conversion completes (success or failure)
## error: Error.OK on success, error code on failure
## error_message: empty on success, description on failure
signal conversion_completed(task_id: int, source_path: String, output_path: String, error: Error, error_message: String)

## Emitted when all tasks in a batch are completed
## results: Array of { task_id, source_path, output_path, error, error_message }
signal batch_completed(results: Array[Dictionary])

# ============================================================
# Conversion Methods (all async, non-blocking)
# ============================================================

## Image to KTX2 conversion
## quality: 0-255 (basis universal quality)
## mipmaps: generate mipmaps
## Returns: task_id for tracking, or -1 on immediate failure
func image_to_ktx2(
    source_path: String,
    output_path: String,
    quality: int = 128,
    mipmaps: bool = true
) -> int

## Audio to MP3 conversion
## bitrate: target bitrate in kbps (128, 192, 256, 320)
## Returns: task_id for tracking, or -1 on immediate failure
func audio_to_mp3(
    source_path: String,
    output_path: String,
    bitrate: int = 192
) -> int

## Convert textures embedded in GLB to KTX2 (in-place)
## Creates a new GLB file with textures converted to KTX2 format
## output_path: path for the new GLB file (defaults to source_ktx2.glb)
## Returns: task_id for tracking, or -1 on immediate failure
func glb_textures_to_ktx2(
    source_path: String,
    output_path: String = "",
    quality: int = 128,
    mipmaps: bool = true
) -> int

## Normalize/balance audio volume
## target_db: target loudness in dB (e.g., -14.0 for streaming standard)
## peak_limit_db: maximum peak level to prevent clipping
## Returns: task_id for tracking, or -1 on immediate failure
func normalize_audio(
    source_path: String,
    output_path: String,
    target_db: float = -14.0,
    peak_limit_db: float = -1.0
) -> int

## Batch conversion with progress reporting
## Processes multiple tasks, emits signals for each, then batch_completed at end
func convert_batch(tasks: Array[ConversionTask]) -> void

# ============================================================
# Control Methods
# ============================================================

## Cancel a specific task by task_id
## Returns true if task was found and cancelled
func cancel(task_id: int) -> bool

## Cancel all running tasks
func cancel_all() -> void

## Check if any conversion is currently running
func is_running() -> bool

## Get number of pending/running tasks
func get_pending_count() -> int
```

---

### ConversionTask

Describes a single conversion job for batch processing.

```gdscript
class_name ConversionTask extends RefCounted

enum Type {
    IMAGE_TO_KTX2,
    AUDIO_TO_MP3,
    GLB_TEXTURES_TO_KTX2,
    NORMALIZE_AUDIO
}

enum Status {
    PENDING,      # Waiting to start
    RUNNING,      # Currently processing
    COMPLETED,    # Finished successfully
    FAILED,       # Finished with error
    CANCELLED     # Cancelled by user
}

## Unique identifier assigned when task is queued
var id: int

## Type of conversion
var type: Type

## Current status of the task
var status: Status

## Source file path
var source_path: String

## Output file path
var output_path: String

## Type-specific options dictionary
var options: Dictionary

## Current progress (0.0 to 1.0)
var progress: float

## Error code if failed
var error: Error

## Error message if failed
var error_message: String

# ============================================================
# Factory Methods
# ============================================================

static func create_image_to_ktx2(
    source: String,
    output: String,
    quality: int = 128,
    mipmaps: bool = true
) -> ConversionTask

static func create_audio_to_mp3(
    source: String,
    output: String,
    bitrate: int = 192
) -> ConversionTask

static func create_glb_textures_to_ktx2(
    source: String,
    output: String,
    quality: int = 128,
    mipmaps: bool = true
) -> ConversionTask

static func create_normalize_audio(
    source: String,
    output: String,
    target_db: float = -14.0,
    peak_limit_db: float = -1.0
) -> ConversionTask
```

---

### AssetProbe

Handles all metadata probing operations.

```gdscript
class_name AssetProbe extends RefCounted

## Probe GLB/GLTF file metadata
static func probe_glb(file_path: String) -> Dictionary

## Probe KTX2 texture metadata
static func probe_ktx2(file_path: String) -> Dictionary

## Probe audio file metadata (MP3 only)
## analyze_volume: if true, decode entire audio to compute peak_db/rms_db/lufs (slower)
static func probe_audio(file_path: String, analyze_volume: bool = false) -> Dictionary
```

#### probe_glb() Return Dictionary

```gdscript
{
    "face_count": int,
    "vertex_count": int,
    "aabb": AABB,
    "has_skeleton": bool,
    "skeleton_info": {
        "bone_count": int,
        "bone_names": PackedStringArray
    },
    "animations": [
        {
            "name": String,
            "duration": float,
            "channels": int
        }
    ],
    "meshes": [
        {
            "name": String,
            "primitive_count": int,
            "face_count": int,
            "material_index": int
        }
    ],
    "materials": PackedStringArray,
    "textures": [
        {
            "name": String,
            "width": int,
            "height": int,
            "format": String
        }
    ]
}
```

#### probe_ktx2() Return Dictionary

```gdscript
{
    "width": int,
    "height": int,
    "depth": int,
    "layers": int,
    "mip_levels": int,
    "format": String,
    "is_compressed": bool,
    "compression_scheme": String,  # "basis", "uastc", "etc1s", "none"
    "has_alpha": bool,
    "is_cubemap": bool,
    "size_bytes": int
}
```

#### probe_audio() Return Dictionary

```gdscript
{
    # Always present (header info only, fast)
    "duration": float,          # in seconds
    "sample_rate": int,         # e.g., 44100, 48000
    "channels": int,            # 1=mono, 2=stereo
    "bit_depth": int,           # 16 (MP3 decoded as 16-bit)
    "format": String,           # "mp3"
    "bitrate": int,             # in kbps
    "size_bytes": int,

    # Only present when analyze_volume=true (requires full decode)
    "peak_db": float,           # maximum peak level in dB
    "rms_db": float,            # average loudness in dB
    "lufs": float               # integrated loudness (approximate)
}
```

---

### AssetOP

Main singleton for convenience access.

```gdscript
class_name AssetOP extends Object

## Access converter instance (singleton)
static func get_converter() -> AssetConverter

## Auto-detect file type and probe
## Determines file type by extension and calls appropriate probe function
static func probe(file_path: String) -> Dictionary
```

---

## Usage Examples

### Single Conversion

```gdscript
var converter: AssetConverter

func _ready():
    converter = AssetConverter.new()
    converter.conversion_started.connect(_on_started)
    converter.conversion_progress.connect(_on_progress)
    converter.conversion_completed.connect(_on_completed)

    # Start conversion, returns task_id
    var task_id = converter.image_to_ktx2(
        "/home/user/project/textures/large_texture.png",
        "/home/user/project/textures/large_texture.ktx2",
        200,
        true
    )
    print("Started conversion with task_id: ", task_id)

func _on_started(task_id: int, source_path: String):
    print("[%d] Started: %s" % [task_id, source_path])

func _on_progress(task_id: int, source_path: String, progress: float):
    print("[%d] %s: %.1f%%" % [task_id, source_path, progress * 100])

func _on_completed(task_id: int, source_path: String, output_path: String, error: Error, error_message: String):
    if error == OK:
        print("[%d] Completed: %s -> %s" % [task_id, source_path, output_path])
    else:
        print("[%d] Failed: %s - %s" % [task_id, source_path, error_message])
```

### Batch Conversion with Progress

```gdscript
var converter: AssetConverter

func _ready():
    converter = AssetConverter.new()
    converter.conversion_started.connect(_on_started)
    converter.conversion_progress.connect(_on_progress)
    converter.conversion_completed.connect(_on_completed)
    converter.batch_completed.connect(_on_batch_completed)

    var base_path = "/home/user/project/assets"
    var tasks: Array[ConversionTask] = [
        ConversionTask.create_image_to_ktx2(base_path + "/a.png", base_path + "/a.ktx2"),
        ConversionTask.create_image_to_ktx2(base_path + "/b.png", base_path + "/b.ktx2"),
        ConversionTask.create_audio_to_mp3(base_path + "/c.wav", base_path + "/c.mp3"),
        ConversionTask.create_normalize_audio(base_path + "/d.wav", base_path + "/d_norm.wav", -14.0),
    ]
    converter.convert_batch(tasks)

func _on_started(task_id: int, source_path: String):
    print("[%d] Started: %s" % [task_id, source_path])

func _on_progress(task_id: int, source_path: String, progress: float):
    # Update UI progress bar, etc.
    progress_bar.value = progress * 100
    status_label.text = "Converting %s..." % source_path

func _on_completed(task_id: int, source_path: String, output_path: String, error: Error, error_message: String):
    if error == OK:
        print("[%d] Completed: %s -> %s" % [task_id, source_path, output_path])
    else:
        push_error("[%d] Failed: %s - %s" % [task_id, source_path, error_message])

func _on_batch_completed(results: Array[Dictionary]):
    var success_count = 0
    var fail_count = 0
    for result in results:
        if result.error == OK:
            success_count += 1
        else:
            fail_count += 1
    print("Batch complete: %d succeeded, %d failed" % [success_count, fail_count])
```

### Cancellation

```gdscript
var converter: AssetConverter
var current_task_id: int = -1

func start_conversion():
    converter = AssetConverter.new()
    converter.conversion_completed.connect(_on_completed)

    current_task_id = converter.image_to_ktx2(
        "/home/user/project/textures/huge_texture.png",
        "/home/user/project/textures/huge_texture.ktx2"
    )

func cancel_conversion():
    if current_task_id >= 0 and converter.is_running():
        converter.cancel(current_task_id)
        print("Cancelled task: ", current_task_id)

func cancel_all_conversions():
    converter.cancel_all()
    print("Cancelled all tasks")

func _on_completed(task_id: int, source_path: String, output_path: String, error: Error, error_message: String):
    if error == ERR_SKIP:  # Cancelled
        print("Task %d was cancelled" % task_id)
```

### Probing Assets

```gdscript
# Probe GLB file
var glb_info = AssetProbe.probe_glb("/home/user/project/models/character.glb")
print("Faces: ", glb_info.face_count)
print("Animations: ", glb_info.animations.size())
for anim in glb_info.animations:
    print("  - ", anim.name, ": ", anim.duration, "s")

# Probe KTX2 texture
var ktx2_info = AssetProbe.probe_ktx2("/home/user/project/textures/hero.ktx2")
print("Size: %dx%d" % [ktx2_info.width, ktx2_info.height])
print("Format: ", ktx2_info.format)

# Probe audio file (fast, header only)
var audio_info = AssetProbe.probe_audio("/home/user/project/sfx/explosion.wav")
print("Duration: ", audio_info.duration, "s")
print("Channels: ", audio_info.channels)

# Probe audio with volume analysis (slower, decodes entire file)
var audio_full = AssetProbe.probe_audio("/home/user/project/sfx/explosion.wav", true)
print("Duration: ", audio_full.duration, "s")
print("Peak: ", audio_full.peak_db, " dB")
print("Loudness: ", audio_full.lufs, " LUFS")

# Auto-detect file type and probe
var info = AssetOP.probe("/home/user/project/assets/model.glb")
```

---

## Threading Model

### Async Operations Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Main Thread                               │
│  ┌─────────────────┐                    ┌──────────────────┐    │
│  │  GDScript Code  │───call async───▶   │  AssetConverter  │    │
│  └─────────────────┘                    └────────┬─────────┘    │
│          ▲                                       │              │
│          │ signals                               │ queue task   │
│          │                                       ▼              │
│  ┌───────┴─────────────────────────────────────────────────┐    │
│  │                    Signal Dispatcher                     │    │
│  │         (deferred_call_thread_safe / call_deferred)     │    │
│  └───────▲─────────────────────────────────────────────────┘    │
│          │                                                      │
└──────────┼──────────────────────────────────────────────────────┘
           │ emit signals
           │
┌──────────┴──────────────────────────────────────────────────────┐
│                       Worker Thread Pool                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Worker 1  │  │   Worker 2  │  │   Worker N  │              │
│  │  (ktx2 enc) │  │  (mp3 enc)  │  │   (idle)    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
```

### Key Points

1. **Non-blocking**: All `*_async()` methods return immediately with a task_id
2. **Thread-safe signals**: Signals are emitted on the main thread via `call_deferred`
3. **Worker pool**: Conversion tasks run on background threads (configurable pool size)
4. **Progress updates**: Periodic progress signals during long operations
5. **Cancellation**: Tasks check cancellation flag at safe points during processing

### Thread Safety

- `AssetConverter` instance must be created and used from the main thread
- Signals are always delivered on the main thread
- Static sync methods can be called from any thread
- Internal state is protected by mutexes

---

## Project Structure

```
gd-asset-op/
├── src/
│   ├── register_types.cpp
│   ├── register_types.h
│   ├── asset_converter.cpp
│   ├── asset_converter.h
│   ├── asset_probe.cpp
│   ├── asset_probe.h
│   ├── conversion_task.cpp
│   ├── conversion_task.h
│   ├── cgltf_impl.cpp        # cgltf implementation
│   └── dr_libs_impl.cpp      # dr_wav/dr_mp3 implementation
├── thirdparty/
│   ├── basis_universal/      # KTX2/UASTC encoding
│   ├── cgltf/                # GLB/GLTF parsing
│   ├── dr_libs/              # Audio decoding
│   └── lame/                 # MP3 encoding
├── godot-cpp/                # git submodule
├── bin/                      # Build output
├── SConstruct
├── gd-asset-op.gdextension
├── PRD.md
└── TDD.md
```

---

## Error Handling

### Conversion Errors

Conversion methods return `task_id` immediately. Errors are reported via the `conversion_completed` signal:

| Error Code | Meaning |
|------------|---------|
| `OK` | Operation completed successfully |
| `ERR_FILE_NOT_FOUND` | Source file does not exist |
| `ERR_FILE_CANT_OPEN` | Cannot open source file |
| `ERR_FILE_CANT_WRITE` | Cannot write to output path |
| `ERR_INVALID_DATA` | Source file is corrupted or invalid format |
| `ERR_INVALID_PARAMETER` | Invalid parameter value |
| `ERR_SKIP` | Task was cancelled |
| `FAILED` | Generic failure |

```gdscript
func _on_completed(task_id: int, source_path: String, output_path: String, error: Error, error_message: String):
    match error:
        OK:
            print("Success: ", output_path)
        ERR_FILE_NOT_FOUND:
            print("File not found: ", source_path)
        ERR_SKIP:
            print("Cancelled: ", source_path)
        _:
            print("Error: ", error_message)
```

### Probe Errors

Probe methods return an empty `Dictionary` on failure, with an `"error"` key containing the error message:

```gdscript
var info = AssetProbe.probe_glb("/path/to/invalid.glb")
if info.has("error"):
    print("Error: ", info.error)
```

---

## Implementation Status

### Completed Features

| Feature | Status | Library Used |
|---------|--------|--------------|
| **Probing** | | |
| `probe_glb()` | ✅ Complete | cgltf |
| `probe_ktx2()` | ✅ Complete | Native header parsing |
| `probe_audio()` | ✅ Complete | dr_mp3 (MP3 only) |
| **Conversion** | | |
| `image_to_ktx2()` | ✅ Complete | basis_universal (PNG, JPEG → KTX2 UASTC) |
| `glb_textures_to_ktx2()` | ✅ Complete | cgltf + basis_universal (in-place GLB conversion) |
| `normalize_audio()` | ✅ Complete | dr_wav (WAV input/output) |
| `audio_to_mp3()` | ✅ Complete | dr_wav + LAME (WAV → MP3) |

### Libraries Integrated

| Library | Version | Purpose |
|---------|---------|---------|
| `basis_universal` | 1.60 | KTX2/UASTC texture compression |
| `cgltf` | Latest | GLB/GLTF parsing |
| `dr_libs` | Latest | Audio decoding (dr_wav, dr_mp3) |
| `zstd` | (bundled with basis_universal) | KTX2 supercompression |
| `lame` | 3.100 | MP3 encoding (LGPL) |

### Supported Formats

| Operation | Input Formats | Output Format |
|-----------|---------------|---------------|
| `image_to_ktx2()` | PNG, JPEG | KTX2 (UASTC) |
| `glb_textures_to_ktx2()` | GLB (embedded PNG/JPEG) | GLB (embedded KTX2) |
| `audio_to_mp3()` | WAV | MP3 |
| `normalize_audio()` | WAV | WAV |
| `probe_audio()` | MP3 | — |
| `probe_glb()` | GLB/GLTF | — |
| `probe_ktx2()` | KTX2 | — |
