#include "asset_probe.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/aabb.hpp>

#include <cmath>
#include <cstring>

// dr_libs header for MP3 decoding (implementation in dr_libs_impl.cpp)
#include "dr_mp3.h"

// cgltf header (implementation in cgltf_impl.cpp)
#include "cgltf.h"

using namespace godot;

void AssetProbe::_bind_methods() {
    ClassDB::bind_static_method("AssetProbe", D_METHOD("probe_glb", "file_path"), &AssetProbe::probe_glb);
    ClassDB::bind_static_method("AssetProbe", D_METHOD("probe_ktx2", "file_path"), &AssetProbe::probe_ktx2);
    ClassDB::bind_static_method("AssetProbe", D_METHOD("probe_audio", "file_path", "analyze_volume"), &AssetProbe::probe_audio, DEFVAL(false));
}

AssetProbe::AssetProbe() {
}

AssetProbe::~AssetProbe() {
}

// Helper function to compute volume statistics
static void compute_volume_stats(const float *samples, size_t sample_count, int channels, float &peak_db, float &rms_db) {
    if (sample_count == 0 || samples == nullptr) {
        peak_db = -100.0f;
        rms_db = -100.0f;
        return;
    }

    float peak = 0.0f;
    double sum_squares = 0.0;

    for (size_t i = 0; i < sample_count * channels; i++) {
        float abs_sample = std::fabs(samples[i]);
        if (abs_sample > peak) {
            peak = abs_sample;
        }
        sum_squares += samples[i] * samples[i];
    }

    // Calculate peak dB
    if (peak > 0.0f) {
        peak_db = 20.0f * std::log10(peak);
    } else {
        peak_db = -100.0f;
    }

    // Calculate RMS dB
    double rms = std::sqrt(sum_squares / (sample_count * channels));
    if (rms > 0.0) {
        rms_db = 20.0f * std::log10(rms);
    } else {
        rms_db = -100.0f;
    }
}

Dictionary AssetProbe::probe_glb(const String &file_path) {
    Dictionary result;

    // Check if file exists
    if (!FileAccess::file_exists(file_path)) {
        result["error"] = "File not found: " + file_path;
        return result;
    }

    // Convert Godot String to C string
    CharString path_utf8 = file_path.utf8();
    const char *path_cstr = path_utf8.get_data();

    // Parse GLB/GLTF
    cgltf_options options = {};
    cgltf_data *data = nullptr;
    cgltf_result parse_result = cgltf_parse_file(&options, path_cstr, &data);

    if (parse_result != cgltf_result_success) {
        result["error"] = "Failed to parse GLB/GLTF file";
        return result;
    }

    // Load buffers for mesh data access
    cgltf_result load_result = cgltf_load_buffers(&options, data, path_cstr);
    if (load_result != cgltf_result_success) {
        cgltf_free(data);
        result["error"] = "Failed to load GLB/GLTF buffers";
        return result;
    }

    // Count faces and vertices
    int64_t total_face_count = 0;
    int64_t total_vertex_count = 0;
    Array meshes_array;

    // AABB calculation
    float min_x = 1e30f, min_y = 1e30f, min_z = 1e30f;
    float max_x = -1e30f, max_y = -1e30f, max_z = -1e30f;
    bool has_positions = false;

    for (size_t i = 0; i < data->meshes_count; i++) {
        cgltf_mesh *mesh = &data->meshes[i];
        Dictionary mesh_info;
        mesh_info["name"] = mesh->name ? String(mesh->name) : String("mesh_") + String::num_int64(i);
        mesh_info["primitive_count"] = (int64_t)mesh->primitives_count;

        int64_t mesh_face_count = 0;
        int64_t mesh_vertex_count = 0;

        for (size_t j = 0; j < mesh->primitives_count; j++) {
            cgltf_primitive *prim = &mesh->primitives[j];

            // Count vertices
            for (size_t k = 0; k < prim->attributes_count; k++) {
                if (prim->attributes[k].type == cgltf_attribute_type_position) {
                    cgltf_accessor *accessor = prim->attributes[k].data;
                    mesh_vertex_count += accessor->count;

                    // Calculate AABB from positions
                    if (accessor->has_min && accessor->has_max) {
                        if (accessor->min[0] < min_x) min_x = accessor->min[0];
                        if (accessor->min[1] < min_y) min_y = accessor->min[1];
                        if (accessor->min[2] < min_z) min_z = accessor->min[2];
                        if (accessor->max[0] > max_x) max_x = accessor->max[0];
                        if (accessor->max[1] > max_y) max_y = accessor->max[1];
                        if (accessor->max[2] > max_z) max_z = accessor->max[2];
                        has_positions = true;
                    }
                    break;
                }
            }

            // Count faces (indices / 3 for triangles)
            if (prim->indices) {
                if (prim->type == cgltf_primitive_type_triangles) {
                    mesh_face_count += prim->indices->count / 3;
                }
            } else {
                // No indices, count vertices / 3
                for (size_t k = 0; k < prim->attributes_count; k++) {
                    if (prim->attributes[k].type == cgltf_attribute_type_position) {
                        if (prim->type == cgltf_primitive_type_triangles) {
                            mesh_face_count += prim->attributes[k].data->count / 3;
                        }
                        break;
                    }
                }
            }
        }

        mesh_info["face_count"] = mesh_face_count;
        mesh_info["vertex_count"] = mesh_vertex_count;
        mesh_info["material_index"] = mesh->primitives_count > 0 && mesh->primitives[0].material ?
            (int64_t)(mesh->primitives[0].material - data->materials) : -1;

        meshes_array.push_back(mesh_info);
        total_face_count += mesh_face_count;
        total_vertex_count += mesh_vertex_count;
    }

    result["face_count"] = total_face_count;
    result["vertex_count"] = total_vertex_count;

    // Set AABB
    if (has_positions) {
        AABB aabb(Vector3(min_x, min_y, min_z), Vector3(max_x - min_x, max_y - min_y, max_z - min_z));
        result["aabb"] = aabb;
    } else {
        result["aabb"] = AABB();
    }

    // Check for skeleton
    bool has_skeleton = data->skins_count > 0;
    result["has_skeleton"] = has_skeleton;

    Dictionary skeleton_info;
    if (has_skeleton && data->skins_count > 0) {
        cgltf_skin *skin = &data->skins[0];
        skeleton_info["bone_count"] = (int64_t)skin->joints_count;

        PackedStringArray bone_names;
        for (size_t i = 0; i < skin->joints_count; i++) {
            if (skin->joints[i]->name) {
                bone_names.push_back(String(skin->joints[i]->name));
            } else {
                bone_names.push_back(String("bone_") + String::num_int64(i));
            }
        }
        skeleton_info["bone_names"] = bone_names;
    } else {
        skeleton_info["bone_count"] = 0;
        skeleton_info["bone_names"] = PackedStringArray();
    }
    result["skeleton_info"] = skeleton_info;

    // Animations
    Array animations_array;
    for (size_t i = 0; i < data->animations_count; i++) {
        cgltf_animation *anim = &data->animations[i];
        Dictionary anim_info;
        anim_info["name"] = anim->name ? String(anim->name) : String("animation_") + String::num_int64(i);

        // Calculate duration from samplers
        float max_time = 0.0f;
        for (size_t j = 0; j < anim->samplers_count; j++) {
            cgltf_accessor *input = anim->samplers[j].input;
            if (input && input->has_max) {
                if (input->max[0] > max_time) {
                    max_time = input->max[0];
                }
            }
        }
        anim_info["duration"] = max_time;
        anim_info["channels"] = (int64_t)anim->channels_count;

        animations_array.push_back(anim_info);
    }
    result["animations"] = animations_array;
    result["meshes"] = meshes_array;

    // Materials
    PackedStringArray materials;
    for (size_t i = 0; i < data->materials_count; i++) {
        if (data->materials[i].name) {
            materials.push_back(String(data->materials[i].name));
        } else {
            materials.push_back(String("material_") + String::num_int64(i));
        }
    }
    result["materials"] = materials;

    // Textures
    Array textures_array;
    for (size_t i = 0; i < data->textures_count; i++) {
        cgltf_texture *tex = &data->textures[i];
        Dictionary tex_info;
        tex_info["name"] = tex->name ? String(tex->name) : String("texture_") + String::num_int64(i);

        if (tex->image) {
            tex_info["uri"] = tex->image->uri ? String(tex->image->uri) : String("");
            tex_info["mime_type"] = tex->image->mime_type ? String(tex->image->mime_type) : String("");
        }

        textures_array.push_back(tex_info);
    }
    result["textures"] = textures_array;

    cgltf_free(data);
    return result;
}

Dictionary AssetProbe::probe_ktx2(const String &file_path) {
    Dictionary result;

    // Check if file exists
    if (!FileAccess::file_exists(file_path)) {
        result["error"] = "File not found: " + file_path;
        return result;
    }

    // Read file to get KTX2 header
    Ref<FileAccess> file = FileAccess::open(file_path, FileAccess::READ);
    if (!file.is_valid()) {
        result["error"] = "Failed to open file: " + file_path;
        return result;
    }

    // KTX2 header structure (first 80 bytes)
    // https://registry.khronos.org/KTX/specs/2.0/ktxspec.v2.html
    uint8_t identifier[12];
    file->get_buffer(identifier, 12);

    // Check KTX2 identifier
    const uint8_t ktx2_identifier[12] = {
        0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A
    };

    if (memcmp(identifier, ktx2_identifier, 12) != 0) {
        result["error"] = "Not a valid KTX2 file";
        return result;
    }

    // Read header fields
    uint32_t vk_format = file->get_32();
    uint32_t type_size = file->get_32();
    uint32_t pixel_width = file->get_32();
    uint32_t pixel_height = file->get_32();
    uint32_t pixel_depth = file->get_32();
    uint32_t layer_count = file->get_32();
    uint32_t face_count = file->get_32();
    uint32_t level_count = file->get_32();
    uint32_t supercompression_scheme = file->get_32();

    result["width"] = (int64_t)pixel_width;
    result["height"] = (int64_t)pixel_height;
    result["depth"] = (int64_t)(pixel_depth > 0 ? pixel_depth : 1);
    result["layers"] = (int64_t)(layer_count > 0 ? layer_count : 1);
    result["mip_levels"] = (int64_t)(level_count > 0 ? level_count : 1);
    result["is_cubemap"] = face_count == 6;

    // Determine format string and compression
    String format_str;
    bool is_compressed = false;
    String compression_scheme = "none";

    // Check supercompression
    switch (supercompression_scheme) {
        case 0: compression_scheme = "none"; break;
        case 1: compression_scheme = "basis_lz"; is_compressed = true; break;
        case 2: compression_scheme = "zstd"; is_compressed = true; break;
        case 3: compression_scheme = "zlib"; is_compressed = true; break;
        default: compression_scheme = "unknown"; break;
    }

    // Common VkFormat values
    switch (vk_format) {
        case 0: format_str = "UNDEFINED"; break;
        case 37: format_str = "R8G8B8A8_UNORM"; break;
        case 43: format_str = "R8G8B8A8_SRGB"; break;
        case 23: format_str = "R8G8B8_UNORM"; break;
        case 29: format_str = "R8G8B8_SRGB"; break;
        case 131: format_str = "BC1_RGB_UNORM"; is_compressed = true; break;
        case 132: format_str = "BC1_RGB_SRGB"; is_compressed = true; break;
        case 133: format_str = "BC1_RGBA_UNORM"; is_compressed = true; break;
        case 134: format_str = "BC1_RGBA_SRGB"; is_compressed = true; break;
        case 135: format_str = "BC2_UNORM"; is_compressed = true; break;
        case 136: format_str = "BC2_SRGB"; is_compressed = true; break;
        case 137: format_str = "BC3_UNORM"; is_compressed = true; break;
        case 138: format_str = "BC3_SRGB"; is_compressed = true; break;
        case 139: format_str = "BC4_UNORM"; is_compressed = true; break;
        case 140: format_str = "BC4_SNORM"; is_compressed = true; break;
        case 141: format_str = "BC5_UNORM"; is_compressed = true; break;
        case 142: format_str = "BC5_SNORM"; is_compressed = true; break;
        case 143: format_str = "BC6H_UFLOAT"; is_compressed = true; break;
        case 144: format_str = "BC6H_SFLOAT"; is_compressed = true; break;
        case 145: format_str = "BC7_UNORM"; is_compressed = true; break;
        case 146: format_str = "BC7_SRGB"; is_compressed = true; break;
        case 147: format_str = "ETC2_R8G8B8_UNORM"; is_compressed = true; break;
        case 148: format_str = "ETC2_R8G8B8_SRGB"; is_compressed = true; break;
        case 149: format_str = "ETC2_R8G8B8A1_UNORM"; is_compressed = true; break;
        case 150: format_str = "ETC2_R8G8B8A1_SRGB"; is_compressed = true; break;
        case 151: format_str = "ETC2_R8G8B8A8_UNORM"; is_compressed = true; break;
        case 152: format_str = "ETC2_R8G8B8A8_SRGB"; is_compressed = true; break;
        case 157: format_str = "ASTC_4x4_UNORM"; is_compressed = true; break;
        case 158: format_str = "ASTC_4x4_SRGB"; is_compressed = true; break;
        default: format_str = "VK_FORMAT_" + String::num_int64(vk_format); break;
    }

    result["format"] = format_str;
    result["is_compressed"] = is_compressed;
    result["compression_scheme"] = compression_scheme;

    // Check for alpha based on format
    bool has_alpha = format_str.contains("RGBA") || format_str.contains("A8") ||
                     format_str.contains("BC2") || format_str.contains("BC3") ||
                     format_str.contains("BC7") || format_str.contains("A1");
    result["has_alpha"] = has_alpha;

    // Get file size
    result["size_bytes"] = (int64_t)file->get_length();

    return result;
}

Dictionary AssetProbe::probe_audio(const String &file_path, bool analyze_volume) {
    Dictionary result;

    // Check if file exists
    if (!FileAccess::file_exists(file_path)) {
        result["error"] = "File not found: " + file_path;
        return result;
    }

    // Only MP3 format is supported
    String lower_path = file_path.to_lower();
    if (!lower_path.ends_with(".mp3")) {
        result["error"] = "Only MP3 format is supported";
        return result;
    }

    // Convert Godot String to C string
    CharString path_utf8 = file_path.utf8();
    const char *path_cstr = path_utf8.get_data();

    drmp3 mp3;
    if (!drmp3_init_file(&mp3, path_cstr, nullptr)) {
        result["error"] = "Failed to open MP3 file";
        return result;
    }

    unsigned int channels = mp3.channels;
    unsigned int sample_rate = mp3.sampleRate;
    drmp3_uint64 total_frame_count = drmp3_get_pcm_frame_count(&mp3);

    float *samples = nullptr;
    size_t sample_count = 0;

    if (analyze_volume && total_frame_count > 0) {
        samples = (float *)malloc(sizeof(float) * total_frame_count * channels);
        if (samples) {
            sample_count = drmp3_read_pcm_frames_f32(&mp3, total_frame_count, samples);
        }
    }

    drmp3_uninit(&mp3);

    // Calculate duration
    double duration = 0.0;
    if (sample_rate > 0) {
        duration = (double)total_frame_count / (double)sample_rate;
    }

    // Get file size
    Ref<FileAccess> file = FileAccess::open(file_path, FileAccess::READ);
    int64_t file_size = file.is_valid() ? file->get_length() : 0;

    // Calculate bitrate
    int bitrate = 0;
    if (duration > 0) {
        bitrate = (int)((file_size * 8) / duration / 1000); // kbps
    }

    // Fill result
    result["duration"] = duration;
    result["sample_rate"] = (int64_t)sample_rate;
    result["channels"] = (int64_t)channels;
    result["bit_depth"] = (int64_t)16; // MP3 decoded as 16-bit
    result["format"] = "mp3";
    result["bitrate"] = (int64_t)bitrate;
    result["size_bytes"] = file_size;

    // Volume analysis
    if (analyze_volume) {
        if (samples && sample_count > 0) {
            float peak_db, rms_db;
            compute_volume_stats(samples, sample_count, channels, peak_db, rms_db);

            result["peak_db"] = peak_db;
            result["rms_db"] = rms_db;
            // Simplified LUFS approximation (proper LUFS requires K-weighting filter)
            result["lufs"] = rms_db - 0.691f; // Rough approximation
        } else {
            result["peak_db"] = -100.0f;
            result["rms_db"] = -100.0f;
            result["lufs"] = -100.0f;
        }
    }

    if (samples) {
        ::free(samples);
    }

    return result;
}
