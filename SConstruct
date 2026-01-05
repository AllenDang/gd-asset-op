#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# Add source files and thirdparty includes
env.Append(CPPPATH=[
    "src/",
    "thirdparty/stb/",
    "thirdparty/dr_libs/",
    "thirdparty/cgltf/",
    "thirdparty/basis_universal/transcoder/",
    "thirdparty/basis_universal/encoder/",
    "thirdparty/basis_universal/encoder/3rdparty/",
    "thirdparty/basis_universal/zstd/",
    "thirdparty/lame/",
    "thirdparty/lame/include/",
    "thirdparty/lame/libmp3lame/",
])

# Define BASISU_SUPPORT_ENCODING for encoder and enable KTX2 zstd support
env.Append(CPPDEFINES=["BASISU_SUPPORT_ENCODING=1", "BASISD_SUPPORT_KTX2=1", "BASISD_SUPPORT_KTX2_ZSTD=1", "HAVE_CONFIG_H=1"])

# Main source files
sources = Glob("src/*.cpp")

# Basis Universal transcoder
sources += Glob("thirdparty/basis_universal/transcoder/*.cpp")

# Basis Universal encoder - add all encoder files
encoder_sources = [
    "thirdparty/basis_universal/encoder/basisu_backend.cpp",
    "thirdparty/basis_universal/encoder/basisu_basis_file.cpp",
    "thirdparty/basis_universal/encoder/basisu_bc7enc.cpp",
    "thirdparty/basis_universal/encoder/basisu_comp.cpp",
    "thirdparty/basis_universal/encoder/basisu_enc.cpp",
    "thirdparty/basis_universal/encoder/basisu_etc.cpp",
    "thirdparty/basis_universal/encoder/basisu_frontend.cpp",
    "thirdparty/basis_universal/encoder/basisu_gpu_texture.cpp",
    "thirdparty/basis_universal/encoder/basisu_kernels_sse.cpp",
    "thirdparty/basis_universal/encoder/basisu_opencl.cpp",
    "thirdparty/basis_universal/encoder/basisu_pvrtc1_4.cpp",
    "thirdparty/basis_universal/encoder/basisu_resample_filters.cpp",
    "thirdparty/basis_universal/encoder/basisu_resampler.cpp",
    "thirdparty/basis_universal/encoder/basisu_ssim.cpp",
    "thirdparty/basis_universal/encoder/basisu_uastc_enc.cpp",
    "thirdparty/basis_universal/encoder/basisu_uastc_hdr_4x4_enc.cpp",
    "thirdparty/basis_universal/encoder/basisu_astc_hdr_6x6_enc.cpp",
    "thirdparty/basis_universal/encoder/basisu_astc_hdr_common.cpp",
    "thirdparty/basis_universal/encoder/jpgd.cpp",
    "thirdparty/basis_universal/encoder/pvpngreader.cpp",
    "thirdparty/basis_universal/encoder/3rdparty/android_astc_decomp.cpp",
    "thirdparty/basis_universal/encoder/3rdparty/tinyexr.cpp",
]
sources += encoder_sources

# zstd for KTX2 compression
sources += ["thirdparty/basis_universal/zstd/zstd.c"]

# stb_image for image loading
sources += ["thirdparty/stb/stb_image_impl.cpp"]

# LAME MP3 encoder
lame_sources = [
    "thirdparty/lame/libmp3lame/bitstream.c",
    "thirdparty/lame/libmp3lame/encoder.c",
    "thirdparty/lame/libmp3lame/fft.c",
    "thirdparty/lame/libmp3lame/gain_analysis.c",
    "thirdparty/lame/libmp3lame/id3tag.c",
    "thirdparty/lame/libmp3lame/lame.c",
    "thirdparty/lame/libmp3lame/mpglib_interface.c",
    "thirdparty/lame/libmp3lame/newmdct.c",
    "thirdparty/lame/libmp3lame/presets.c",
    "thirdparty/lame/libmp3lame/psymodel.c",
    "thirdparty/lame/libmp3lame/quantize.c",
    "thirdparty/lame/libmp3lame/quantize_pvt.c",
    "thirdparty/lame/libmp3lame/reservoir.c",
    "thirdparty/lame/libmp3lame/set_get.c",
    "thirdparty/lame/libmp3lame/tables.c",
    "thirdparty/lame/libmp3lame/takehiro.c",
    "thirdparty/lame/libmp3lame/util.c",
    "thirdparty/lame/libmp3lame/vbrquantize.c",
    "thirdparty/lame/libmp3lame/VbrTag.c",
    "thirdparty/lame/libmp3lame/version.c",
]
sources += lame_sources

# Platform-specific settings
if env["platform"] == "macos":
    library = env.SharedLibrary(
        "bin/libgdassetop.{}.{}.dylib".format(
            env["platform"], env["target"]
        ),
        source=sources,
    )
elif env["platform"] == "ios":
    if env["ios_simulator"]:
        library = env.StaticLibrary(
            "bin/libgdassetop.{}.{}.simulator.a".format(env["platform"], env["target"]),
            source=sources,
        )
    else:
        library = env.StaticLibrary(
            "bin/libgdassetop.{}.{}.a".format(env["platform"], env["target"]),
            source=sources,
        )
elif env["platform"] == "windows":
    library = env.SharedLibrary(
        "bin/libgdassetop.{}.{}.{}{}".format(
            env["platform"], env["target"], env["arch"], env["SHLIBSUFFIX"]
        ),
        source=sources,
    )
else:
    library = env.SharedLibrary(
        "bin/libgdassetop.{}.{}.{}{}".format(
            env["platform"], env["target"], env["arch"], env["SHLIBSUFFIX"]
        ),
        source=sources,
    )

Default(library)
