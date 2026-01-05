#!/usr/bin/env python3
"""
Generate test assets for gd-asset-op integration tests.

No external dependencies required - generates raw binary files.
"""

import os
import struct
import math
import json
import zlib

ASSETS_DIR = os.path.join(os.path.dirname(__file__), "assets")


def ensure_dir():
    os.makedirs(ASSETS_DIR, exist_ok=True)


def _png_crc(data):
    """Calculate CRC32 for PNG chunk."""
    return zlib.crc32(data) & 0xffffffff


def _png_chunk(chunk_type, data):
    """Create a PNG chunk."""
    chunk = chunk_type + data
    return struct.pack('>I', len(data)) + chunk + struct.pack('>I', _png_crc(chunk))


def generate_test_png():
    """Generate a test PNG image with a gradient pattern (no dependencies)."""
    width, height = 64, 64  # Smaller size for simplicity

    # Generate raw RGBA pixel data with filter byte per row
    raw_data = bytearray()
    for y in range(height):
        raw_data.append(0)  # Filter type: None
        for x in range(width):
            r = int(255 * x / width)
            g = int(255 * y / height)
            b = int(255 * (1 - x / width))
            a = 255
            raw_data.extend([r, g, b, a])

    # Compress with zlib
    compressed = zlib.compress(bytes(raw_data), 9)

    # Build PNG file
    png_data = bytearray()

    # PNG signature
    png_data.extend(b'\x89PNG\r\n\x1a\n')

    # IHDR chunk
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png_data.extend(_png_chunk(b'IHDR', ihdr_data))

    # IDAT chunk (compressed image data)
    png_data.extend(_png_chunk(b'IDAT', compressed))

    # IEND chunk
    png_data.extend(_png_chunk(b'IEND', b''))

    path = os.path.join(ASSETS_DIR, "test.png")
    with open(path, 'wb') as f:
        f.write(png_data)
    print(f"Generated: {path}")


def generate_test_jpg():
    """
    Generate a minimal valid JPEG image.
    Creates a simple 8x8 gray image (JPEG's minimum DCT block size).
    """
    # Minimal JPEG with 8x8 gray pixels
    # This is a hand-crafted minimal JPEG that decodes to a valid image

    width, height = 8, 8

    # Quantization table (all 1s for maximum quality)
    quant_table = bytes([1] * 64)

    # Huffman tables for DC and AC (minimal)
    dc_bits = bytes([0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0])
    dc_vals = bytes([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])

    ac_bits = bytes([0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125])
    ac_vals = bytes([
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
        0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08,
        0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16,
        0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
        0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
        0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
        0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6,
        0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
        0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4,
        0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
        0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea,
        0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
        0xf9, 0xfa
    ])

    jpeg = bytearray()

    # SOI (Start of Image)
    jpeg.extend(b'\xff\xd8')

    # APP0 (JFIF marker)
    app0 = b'JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'
    jpeg.extend(b'\xff\xe0')
    jpeg.extend(struct.pack('>H', len(app0) + 2))
    jpeg.extend(app0)

    # DQT (Quantization Table)
    jpeg.extend(b'\xff\xdb')
    jpeg.extend(struct.pack('>H', 67))  # Length
    jpeg.append(0)  # Table ID 0, 8-bit precision
    jpeg.extend(quant_table)

    # SOF0 (Start of Frame - Baseline DCT)
    jpeg.extend(b'\xff\xc0')
    jpeg.extend(struct.pack('>H', 11))  # Length
    jpeg.append(8)  # Precision
    jpeg.extend(struct.pack('>H', height))
    jpeg.extend(struct.pack('>H', width))
    jpeg.append(1)  # Number of components (grayscale)
    jpeg.extend(b'\x01\x11\x00')  # Component: ID=1, sampling=1x1, quant table=0

    # DHT (Huffman Tables) - DC
    jpeg.extend(b'\xff\xc4')
    jpeg.extend(struct.pack('>H', len(dc_bits) + len(dc_vals) + 3))
    jpeg.append(0x00)  # DC table 0
    jpeg.extend(dc_bits)
    jpeg.extend(dc_vals)

    # DHT (Huffman Tables) - AC
    jpeg.extend(b'\xff\xc4')
    jpeg.extend(struct.pack('>H', len(ac_bits) + len(ac_vals) + 3))
    jpeg.append(0x10)  # AC table 0
    jpeg.extend(ac_bits)
    jpeg.extend(ac_vals)

    # SOS (Start of Scan)
    jpeg.extend(b'\xff\xda')
    jpeg.extend(struct.pack('>H', 8))  # Length
    jpeg.append(1)  # Number of components
    jpeg.extend(b'\x01\x00')  # Component 1, DC table 0, AC table 0
    jpeg.extend(b'\x00\x3f\x00')  # Spectral selection

    # Scan data (encoded gray image - DC=128, all AC=0)
    # This encodes a uniform gray 8x8 block
    jpeg.extend(b'\xfb\xd3\x28\xa2\x80\x00')  # Minimal encoded data

    # EOI (End of Image)
    jpeg.extend(b'\xff\xd9')

    path = os.path.join(ASSETS_DIR, "test.jpg")
    with open(path, 'wb') as f:
        f.write(jpeg)
    print(f"Generated: {path}")


def generate_test_wav():
    """Generate a test WAV file with a sine wave."""
    sample_rate = 44100
    duration = 2.0  # seconds
    frequency = 440.0  # Hz (A4 note)
    amplitude = 0.5

    num_samples = int(sample_rate * duration)
    samples = []

    for i in range(num_samples):
        t = i / sample_rate
        # Sine wave with fade in/out
        envelope = 1.0
        if t < 0.1:
            envelope = t / 0.1
        elif t > duration - 0.1:
            envelope = (duration - t) / 0.1

        sample = amplitude * envelope * math.sin(2 * math.pi * frequency * t)
        # Convert to 16-bit PCM
        sample_int = int(sample * 32767)
        samples.append(sample_int)

    # Write WAV file
    path = os.path.join(ASSETS_DIR, "test.wav")
    with open(path, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        data_size = num_samples * 2  # 16-bit samples
        file_size = 36 + data_size
        f.write(struct.pack('<I', file_size))
        f.write(b'WAVE')

        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))  # chunk size
        f.write(struct.pack('<H', 1))   # audio format (PCM)
        f.write(struct.pack('<H', 1))   # num channels (mono)
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', sample_rate * 2))  # byte rate
        f.write(struct.pack('<H', 2))   # block align
        f.write(struct.pack('<H', 16))  # bits per sample

        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        for sample in samples:
            f.write(struct.pack('<h', sample))

    print(f"Generated: {path}")


def generate_test_mp3():
    """
    Generate a test MP3 file.
    This requires lame or ffmpeg to be installed.
    """
    wav_path = os.path.join(ASSETS_DIR, "test.wav")
    mp3_path = os.path.join(ASSETS_DIR, "test.mp3")

    if not os.path.exists(wav_path):
        print("WAV file not found, generating it first...")
        generate_test_wav()

    # Try using ffmpeg
    import subprocess
    try:
        result = subprocess.run(
            ['ffmpeg', '-y', '-i', wav_path, '-b:a', '192k', mp3_path],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"Generated: {mp3_path}")
            return
    except FileNotFoundError:
        pass

    # Try using lame
    try:
        result = subprocess.run(
            ['lame', '-b', '192', wav_path, mp3_path],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"Generated: {mp3_path}")
            return
    except FileNotFoundError:
        pass

    print("WARNING: Could not generate MP3 (ffmpeg or lame not found)")
    print("Please manually create test/assets/test.mp3 or install ffmpeg/lame")


def _generate_small_png():
    """Generate a small PNG image in memory (no dependencies)."""
    width, height = 16, 16

    # Generate raw RGBA pixel data with filter byte per row
    raw_data = bytearray()
    for y in range(height):
        raw_data.append(0)  # Filter type: None
        for x in range(width):
            r = int(255 * x / width)
            g = int(255 * y / height)
            b = 128
            a = 255
            raw_data.extend([r, g, b, a])

    # Compress with zlib
    compressed = zlib.compress(bytes(raw_data), 9)

    # Build PNG file
    png_data = bytearray()
    png_data.extend(b'\x89PNG\r\n\x1a\n')

    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png_data.extend(_png_chunk(b'IHDR', ihdr_data))
    png_data.extend(_png_chunk(b'IDAT', compressed))
    png_data.extend(_png_chunk(b'IEND', b''))

    return bytes(png_data)


def generate_test_glb():
    """
    Generate a minimal GLB file with an embedded PNG texture.
    Creates a simple triangle with a texture (no external dependencies).
    """
    # Generate embedded PNG texture
    png_data = _generate_small_png()

    # Create vertex data (simple triangle)
    positions = [
        0.0, 0.5, 0.0,    # top
        -0.5, -0.5, 0.0,  # bottom left
        0.5, -0.5, 0.0,   # bottom right
    ]

    uvs = [
        0.5, 0.0,  # top
        0.0, 1.0,  # bottom left
        1.0, 1.0,  # bottom right
    ]

    indices = [0, 1, 2]

    # Pack binary data
    bin_data = bytearray()

    # Indices (offset 0)
    indices_offset = len(bin_data)
    for idx in indices:
        bin_data.extend(struct.pack('<H', idx))
    while len(bin_data) % 4 != 0:
        bin_data.append(0)

    # Positions (aligned)
    positions_offset = len(bin_data)
    for val in positions:
        bin_data.extend(struct.pack('<f', val))

    # UVs (aligned)
    uvs_offset = len(bin_data)
    for val in uvs:
        bin_data.extend(struct.pack('<f', val))

    # PNG image data (aligned)
    while len(bin_data) % 4 != 0:
        bin_data.append(0)
    image_offset = len(bin_data)
    bin_data.extend(png_data)

    while len(bin_data) % 4 != 0:
        bin_data.append(0)

    # Create glTF JSON
    gltf = {
        "asset": {"version": "2.0", "generator": "gd-asset-op-test"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{
            "primitives": [{
                "attributes": {"POSITION": 1, "TEXCOORD_0": 2},
                "indices": 0,
                "material": 0
            }]
        }],
        "materials": [{
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0
            }
        }],
        "textures": [{"source": 0}],
        "images": [{
            "bufferView": 3,
            "mimeType": "image/png"
        }],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5123,
                "count": 3,
                "type": "SCALAR"
            },
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-0.5, -0.5, 0.0],
                "max": [0.5, 0.5, 0.0]
            },
            {
                "bufferView": 2,
                "componentType": 5126,
                "count": 3,
                "type": "VEC2"
            }
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": indices_offset, "byteLength": 6},
            {"buffer": 0, "byteOffset": positions_offset, "byteLength": 36},
            {"buffer": 0, "byteOffset": uvs_offset, "byteLength": 24},
            {"buffer": 0, "byteOffset": image_offset, "byteLength": len(png_data)}
        ],
        "buffers": [{"byteLength": len(bin_data)}]
    }

    json_str = json.dumps(gltf, separators=(',', ':'))
    while len(json_str) % 4 != 0:
        json_str += ' '

    json_bytes = json_str.encode('utf-8')

    # Build GLB file
    glb_data = bytearray()
    glb_data.extend(struct.pack('<I', 0x46546C67))  # magic "glTF"
    glb_data.extend(struct.pack('<I', 2))  # version
    total_length = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    glb_data.extend(struct.pack('<I', total_length))

    # JSON chunk
    glb_data.extend(struct.pack('<I', len(json_bytes)))
    glb_data.extend(struct.pack('<I', 0x4E4F534A))  # "JSON"
    glb_data.extend(json_bytes)

    # BIN chunk
    glb_data.extend(struct.pack('<I', len(bin_data)))
    glb_data.extend(struct.pack('<I', 0x004E4942))  # "BIN\0"
    glb_data.extend(bin_data)

    path = os.path.join(ASSETS_DIR, "test.glb")
    with open(path, 'wb') as f:
        f.write(glb_data)

    print(f"Generated: {path}")


def main():
    print("Generating test assets for gd-asset-op...\n")

    ensure_dir()

    generate_test_png()
    generate_test_jpg()
    generate_test_wav()
    generate_test_mp3()
    generate_test_glb()

    print("\nDone! Test assets are in:", ASSETS_DIR)
    print("\nTo run the integration tests:")
    print("  godot --headless --script test/integration_test.gd")


if __name__ == "__main__":
    main()
