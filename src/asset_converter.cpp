#include "asset_converter.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

// Basis Universal includes
#include "basisu_transcoder.h"
#include "basisu_enc.h"
#include "basisu_comp.h"
#include "basisu_uastc_enc.h"

// Image loading (using basis universal's built-in loaders)
#include "pvpngreader.h"
#include "jpgd.h"

// Audio processing with dr_libs
#include "dr_wav.h"
#include "dr_mp3.h"

// LAME MP3 encoder
#include "lame.h"

// GLB parsing with cgltf
#include "cgltf.h"

#include <cmath>
#include <cstring>
#include <fstream>
#include <vector>

using namespace godot;

void AssetConverter::_bind_methods() {
    // Signals
    ADD_SIGNAL(MethodInfo("conversion_started",
        PropertyInfo(Variant::INT, "task_id"),
        PropertyInfo(Variant::STRING, "source_path")));

    ADD_SIGNAL(MethodInfo("conversion_progress",
        PropertyInfo(Variant::INT, "task_id"),
        PropertyInfo(Variant::STRING, "source_path"),
        PropertyInfo(Variant::FLOAT, "progress")));

    ADD_SIGNAL(MethodInfo("conversion_completed",
        PropertyInfo(Variant::INT, "task_id"),
        PropertyInfo(Variant::STRING, "source_path"),
        PropertyInfo(Variant::STRING, "output_path"),
        PropertyInfo(Variant::INT, "error"),
        PropertyInfo(Variant::STRING, "error_message")));

    ADD_SIGNAL(MethodInfo("batch_completed",
        PropertyInfo(Variant::ARRAY, "results")));

    // Conversion methods
    ClassDB::bind_method(D_METHOD("image_to_ktx2", "source_path", "output_path", "quality", "mipmaps"), &AssetConverter::image_to_ktx2, DEFVAL(128), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("audio_to_mp3", "source_path", "output_path", "bitrate"), &AssetConverter::audio_to_mp3, DEFVAL(192));
    ClassDB::bind_method(D_METHOD("glb_textures_to_ktx2", "source_path", "output_path", "quality", "mipmaps"), &AssetConverter::glb_textures_to_ktx2, DEFVAL(""), DEFVAL(128), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("normalize_audio", "source_path", "output_path", "target_db", "peak_limit_db"), &AssetConverter::normalize_audio, DEFVAL(-14.0f), DEFVAL(-1.0f));

    // Batch conversion
    ClassDB::bind_method(D_METHOD("convert_batch", "tasks"), &AssetConverter::convert_batch);

    // Control methods
    ClassDB::bind_method(D_METHOD("cancel", "task_id"), &AssetConverter::cancel);
    ClassDB::bind_method(D_METHOD("cancel_all"), &AssetConverter::cancel_all);
    ClassDB::bind_method(D_METHOD("is_running"), &AssetConverter::is_running);
    ClassDB::bind_method(D_METHOD("get_pending_count"), &AssetConverter::get_pending_count);

    // Internal methods for deferred calls
    ClassDB::bind_method(D_METHOD("_emit_started", "task_id", "source_path"), &AssetConverter::_emit_started);
    ClassDB::bind_method(D_METHOD("_emit_progress", "task_id", "source_path", "progress"), &AssetConverter::_emit_progress);
    ClassDB::bind_method(D_METHOD("_emit_completed", "task_id", "source_path", "output_path", "error", "error_message"), &AssetConverter::_emit_completed);
    ClassDB::bind_method(D_METHOD("_emit_batch_completed", "results"), &AssetConverter::_emit_batch_completed);
}

AssetConverter::AssetConverter() {
    next_task_id = 0;
    should_exit = false;
    is_batch_mode = false;

    queue_mutex.instantiate();
    work_semaphore.instantiate();

    // Initialize basis universal encoder
    basisu::basisu_encoder_init();

    // Create job pool with 4 threads (including calling thread)
    basis_job_pool = new basisu::job_pool(4);

    // Start worker thread
    worker_thread.instantiate();
    worker_thread->start(callable_mp(this, &AssetConverter::_worker_function));
}

AssetConverter::~AssetConverter() {
    // Signal worker thread to exit
    should_exit = true;
    work_semaphore->post();

    // Wait for worker thread to finish
    if (worker_thread.is_valid() && worker_thread->is_started()) {
        worker_thread->wait_to_finish();
    }

    // Clean up job pool
    if (basis_job_pool) {
        delete basis_job_pool;
        basis_job_pool = nullptr;
    }
}

void AssetConverter::_worker_function() {
    while (!should_exit) {
        // Wait for work
        work_semaphore->wait();

        if (should_exit) {
            break;
        }

        // Get next task from queue
        Ref<ConversionTask> task;
        {
            queue_mutex->lock();
            if (!task_queue.is_empty()) {
                task = task_queue[0];
                task_queue.remove_at(0);
            }
            queue_mutex->unlock();
        }

        if (task.is_valid() && task->get_status() == ConversionTask::PENDING) {
            _process_task(task);
        }

        // Check if batch is complete
        {
            queue_mutex->lock();
            if (is_batch_mode && task_queue.is_empty()) {
                is_batch_mode = false;
                Array results = batch_results.duplicate();
                batch_results.clear();
                queue_mutex->unlock();

                call_deferred("_emit_batch_completed", results);
            } else {
                queue_mutex->unlock();
            }
        }
    }
}

void AssetConverter::_process_task(Ref<ConversionTask> task) {
    task->set_status(ConversionTask::RUNNING);

    // Emit started signal on main thread
    call_deferred("_emit_started", task->get_id(), task->get_source_path());

    // Check if file exists
    if (!FileAccess::file_exists(task->get_source_path())) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_NOT_FOUND);
        task->set_error_message("Source file not found: " + task->get_source_path());

        call_deferred("_emit_completed",
            task->get_id(),
            task->get_source_path(),
            task->get_output_path(),
            (int)task->get_error(),
            task->get_error_message());

        // Add to batch results if in batch mode
        if (is_batch_mode) {
            queue_mutex->lock();
            Dictionary result;
            result["task_id"] = task->get_id();
            result["source_path"] = task->get_source_path();
            result["output_path"] = task->get_output_path();
            result["error"] = (int)task->get_error();
            result["error_message"] = task->get_error_message();
            batch_results.push_back(result);
            queue_mutex->unlock();
        }
        return;
    }

    // Process based on type
    switch (task->get_type()) {
        case ConversionTask::IMAGE_TO_KTX2:
            _convert_image_to_ktx2(task);
            break;
        case ConversionTask::AUDIO_TO_MP3:
            _convert_audio_to_mp3(task);
            break;
        case ConversionTask::GLB_TEXTURES_TO_KTX2:
            _convert_glb_textures_to_ktx2(task);
            break;
        case ConversionTask::NORMALIZE_AUDIO:
            _normalize_audio(task);
            break;
    }

    // Emit completed signal on main thread
    call_deferred("_emit_completed",
        task->get_id(),
        task->get_source_path(),
        task->get_output_path(),
        (int)task->get_error(),
        task->get_error_message());

    // Add to batch results if in batch mode
    if (is_batch_mode) {
        queue_mutex->lock();
        Dictionary result;
        result["task_id"] = task->get_id();
        result["source_path"] = task->get_source_path();
        result["output_path"] = task->get_output_path();
        result["error"] = (int)task->get_error();
        result["error_message"] = task->get_error_message();
        batch_results.push_back(result);
        queue_mutex->unlock();
    }
}

void AssetConverter::_emit_started(int task_id, const String &source_path) {
    emit_signal("conversion_started", task_id, source_path);
}

void AssetConverter::_emit_progress(int task_id, const String &source_path, float progress) {
    emit_signal("conversion_progress", task_id, source_path, progress);
}

void AssetConverter::_emit_completed(int task_id, const String &source_path, const String &output_path, Error error, const String &error_message) {
    emit_signal("conversion_completed", task_id, source_path, output_path, (int)error, error_message);
}

void AssetConverter::_emit_batch_completed(const Array &results) {
    emit_signal("batch_completed", results);
}

// Helper to read file into vector
static bool read_file_to_vector(const char *path, std::vector<uint8_t> &data) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        return false;
    }

    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);

    data.resize(size);
    if (!file.read(reinterpret_cast<char*>(data.data()), size)) {
        return false;
    }

    return true;
}

// Helper to write vector to file
static bool write_vector_to_file(const char *path, const std::vector<uint8_t> &data) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    file.write(reinterpret_cast<const char*>(data.data()), data.size());
    return file.good();
}

void AssetConverter::_convert_image_to_ktx2(Ref<ConversionTask> task) {
    CharString source_utf8 = task->get_source_path().utf8();
    CharString output_utf8 = task->get_output_path().utf8();
    const char *source_path = source_utf8.get_data();
    const char *output_path = output_utf8.get_data();

    Dictionary options = task->get_options();
    int quality = options.get("quality", 128);
    bool mipmaps = options.get("mipmaps", true);

    // Report progress
    task->set_progress(0.1f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Read source image
    std::vector<uint8_t> file_data;
    if (!read_file_to_vector(source_path, file_data)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_OPEN);
        task->set_error_message("Failed to read source file");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        return;
    }

    task->set_progress(0.2f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Load image using basis universal's image loader
    basisu::image img;
    String lower_path = task->get_source_path().to_lower();

    if (lower_path.ends_with(".png")) {
        // Load PNG using basisu::load_png
        if (!basisu::load_png(file_data.data(), file_data.size(), img, nullptr)) {
            task->set_status(ConversionTask::FAILED);
            task->set_error(ERR_INVALID_DATA);
            task->set_error_message("Failed to decode PNG image");
            return;
        }
    } else if (lower_path.ends_with(".jpg") || lower_path.ends_with(".jpeg")) {
        // Load JPEG
        int width, height, actual_comps;
        uint8_t *jpeg_data = jpgd::decompress_jpeg_image_from_memory(
            file_data.data(), (int)file_data.size(),
            &width, &height, &actual_comps, 4);

        if (!jpeg_data) {
            task->set_status(ConversionTask::FAILED);
            task->set_error(ERR_INVALID_DATA);
            task->set_error_message("Failed to decode JPEG image");
            return;
        }

        img.resize(width, height);
        memcpy(img.get_ptr(), jpeg_data, width * height * 4);
        ::free(jpeg_data);
    } else {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Unsupported image format (only PNG and JPEG supported)");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        return;
    }

    task->set_progress(0.4f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Map quality (1-255) to UASTC pack level
    uint32_t uastc_level;
    if (quality <= 50) {
        uastc_level = basisu::cPackUASTCLevelFastest;
    } else if (quality <= 100) {
        uastc_level = basisu::cPackUASTCLevelFaster;
    } else if (quality <= 150) {
        uastc_level = basisu::cPackUASTCLevelDefault;
    } else if (quality <= 200) {
        uastc_level = basisu::cPackUASTCLevelSlower;
    } else {
        uastc_level = basisu::cPackUASTCLevelVerySlow;
    }

    // Setup basis encoder parameters
    basisu::basis_compressor_params params;
    params.m_pJob_pool = basis_job_pool;
    params.m_source_images.push_back(img);

    // Use UASTC mode for better quality
    params.m_uastc = true;
    params.m_pack_uastc_ldr_4x4_flags = uastc_level;

    // KTX2 output settings
    params.m_create_ktx2_file = true;
    params.m_ktx2_uastc_supercompression = basist::KTX2_SS_ZSTANDARD;
    params.m_ktx2_zstd_supercompression_level = 6;  // Moderate compression

    // Mipmap settings
    if (mipmaps) {
        params.m_mip_gen = true;
        params.m_mip_filter = "kaiser";
    } else {
        params.m_mip_gen = false;
    }

    // Disable status output for library use
    params.m_status_output = false;

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        return;
    }

    task->set_progress(0.5f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Create and run the compressor
    basisu::basis_compressor compressor;
    if (!compressor.init(params)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("Failed to initialize basis compressor");
        return;
    }

    task->set_progress(0.6f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Compress
    basisu::basis_compressor::error_code result = compressor.process();
    if (result != basisu::basis_compressor::cECSuccess) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("Basis compression failed with error code: " + String::num_int64((int)result));
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        return;
    }

    task->set_progress(0.9f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Get the output data
    const basisu::uint8_vec &output_data = compressor.get_output_ktx2_file();

    // Write to file
    std::vector<uint8_t> output_vec(output_data.begin(), output_data.end());
    if (!write_vector_to_file(output_path, output_vec)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to write output file");
        return;
    }

    // Success
    task->set_status(ConversionTask::COMPLETED);
    task->set_error(OK);
    task->set_progress(1.0f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
}

void AssetConverter::_convert_audio_to_mp3(Ref<ConversionTask> task) {
    CharString source_utf8 = task->get_source_path().utf8();
    CharString output_utf8 = task->get_output_path().utf8();
    const char *source_path = source_utf8.get_data();
    const char *output_path = output_utf8.get_data();

    Dictionary options = task->get_options();
    int bitrate = options.get("bitrate", 192);

    task->set_progress(0.1f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Only WAV input is supported
    String lower_path = task->get_source_path().to_lower();
    if (!lower_path.ends_with(".wav")) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Only WAV input format is supported for MP3 conversion");
        return;
    }

    // Open WAV file
    drwav wav;
    if (!drwav_init_file(&wav, source_path, nullptr)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_OPEN);
        task->set_error_message("Failed to open WAV file");
        return;
    }

    unsigned int channels = wav.channels;
    unsigned int sample_rate = wav.sampleRate;
    drwav_uint64 total_frame_count = wav.totalPCMFrameCount;

    // Read all samples as 16-bit PCM
    int16_t *pcm_samples = (int16_t *)malloc(sizeof(int16_t) * total_frame_count * channels);
    if (!pcm_samples) {
        drwav_uninit(&wav);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_OUT_OF_MEMORY);
        task->set_error_message("Failed to allocate memory for audio samples");
        return;
    }

    drwav_uint64 frames_read = drwav_read_pcm_frames_s16(&wav, total_frame_count, pcm_samples);
    drwav_uninit(&wav);

    if (frames_read != total_frame_count) {
        ::free(pcm_samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CORRUPT);
        task->set_error_message("Failed to read all audio frames");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        ::free(pcm_samples);
        return;
    }

    task->set_progress(0.3f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Initialize LAME encoder
    lame_t lame = lame_init();
    if (!lame) {
        ::free(pcm_samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("Failed to initialize LAME encoder");
        return;
    }

    lame_set_num_channels(lame, channels);
    lame_set_in_samplerate(lame, sample_rate);
    lame_set_brate(lame, bitrate);
    lame_set_mode(lame, channels == 1 ? MONO : JOINT_STEREO);
    lame_set_quality(lame, 2); // 2 = high quality, slower

    if (lame_init_params(lame) < 0) {
        lame_close(lame);
        ::free(pcm_samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("Failed to configure LAME encoder");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        lame_close(lame);
        ::free(pcm_samples);
        return;
    }

    task->set_progress(0.4f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Allocate MP3 buffer (worst case: 1.25 * samples + 7200)
    size_t mp3_buffer_size = (size_t)(1.25 * total_frame_count * channels) + 7200;
    unsigned char *mp3_buffer = (unsigned char *)malloc(mp3_buffer_size);
    if (!mp3_buffer) {
        lame_close(lame);
        ::free(pcm_samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_OUT_OF_MEMORY);
        task->set_error_message("Failed to allocate MP3 buffer");
        return;
    }

    // Encode
    int mp3_size;
    if (channels == 1) {
        // Mono
        mp3_size = lame_encode_buffer(lame, pcm_samples, nullptr, (int)total_frame_count, mp3_buffer, (int)mp3_buffer_size);
    } else {
        // Stereo - interleaved
        mp3_size = lame_encode_buffer_interleaved(lame, pcm_samples, (int)total_frame_count, mp3_buffer, (int)mp3_buffer_size);
    }

    ::free(pcm_samples);

    if (mp3_size < 0) {
        lame_close(lame);
        ::free(mp3_buffer);
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("LAME encoding failed with error: " + String::num_int64(mp3_size));
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        lame_close(lame);
        ::free(mp3_buffer);
        return;
    }

    task->set_progress(0.8f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Flush encoder
    int flush_size = lame_encode_flush(lame, mp3_buffer + mp3_size, (int)(mp3_buffer_size - mp3_size));
    if (flush_size > 0) {
        mp3_size += flush_size;
    }

    lame_close(lame);

    // Write MP3 file
    std::ofstream outfile(output_path, std::ios::binary);
    if (!outfile.is_open()) {
        ::free(mp3_buffer);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to create output MP3 file");
        return;
    }

    outfile.write(reinterpret_cast<const char*>(mp3_buffer), mp3_size);
    outfile.close();
    ::free(mp3_buffer);

    if (!outfile.good()) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to write MP3 data");
        return;
    }

    // Success
    task->set_status(ConversionTask::COMPLETED);
    task->set_error(OK);
    task->set_progress(1.0f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
}

// Helper structure to hold converted texture data
struct ConvertedTexture {
    std::vector<uint8_t> ktx2_data;
    size_t original_buffer_view_index;
    bool converted;
};

void AssetConverter::_convert_glb_textures_to_ktx2(Ref<ConversionTask> task) {
    CharString source_utf8 = task->get_source_path().utf8();
    const char *source_path = source_utf8.get_data();

    Dictionary options = task->get_options();
    int quality = options.get("quality", 128);
    bool mipmaps = options.get("mipmaps", true);
    String output_path = task->get_output_path();

    // If no output path specified, create one based on source
    if (output_path.is_empty()) {
        output_path = task->get_source_path().get_basename() + "_ktx2.glb";
        task->set_output_path(output_path);
    }

    task->set_progress(0.1f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Read entire GLB file
    std::vector<uint8_t> glb_data;
    if (!read_file_to_vector(source_path, glb_data)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_OPEN);
        task->set_error_message("Failed to read GLB file");
        return;
    }

    // Validate GLB header
    if (glb_data.size() < 12) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Invalid GLB file: too small");
        return;
    }

    uint32_t magic = *(uint32_t*)&glb_data[0];
    uint32_t version = *(uint32_t*)&glb_data[4];
    // uint32_t total_length = *(uint32_t*)&glb_data[8];

    if (magic != 0x46546C67) { // "glTF"
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Invalid GLB file: bad magic number");
        return;
    }

    if (version != 2) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Only GLB version 2 is supported");
        return;
    }

    // Parse chunks
    size_t offset = 12;

    // JSON chunk
    if (offset + 8 > glb_data.size()) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Invalid GLB: missing JSON chunk");
        return;
    }

    uint32_t json_chunk_length = *(uint32_t*)&glb_data[offset];
    uint32_t json_chunk_type = *(uint32_t*)&glb_data[offset + 4];

    if (json_chunk_type != 0x4E4F534A) { // "JSON"
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Invalid GLB: first chunk is not JSON");
        return;
    }

    offset += 8;
    std::string json_str((char*)&glb_data[offset], json_chunk_length);
    offset += json_chunk_length;

    // BIN chunk (optional)
    std::vector<uint8_t> bin_data;
    if (offset + 8 <= glb_data.size()) {
        uint32_t bin_chunk_length = *(uint32_t*)&glb_data[offset];
        uint32_t bin_chunk_type = *(uint32_t*)&glb_data[offset + 4];

        if (bin_chunk_type == 0x004E4942) { // "BIN\0"
            offset += 8;
            bin_data.assign(glb_data.begin() + offset, glb_data.begin() + offset + bin_chunk_length);
        }
    }

    task->set_progress(0.15f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Parse with cgltf to get structure info
    cgltf_options cgltf_opts = {};
    cgltf_data *data = nullptr;
    cgltf_result parse_result = cgltf_parse(&cgltf_opts, glb_data.data(), glb_data.size(), &data);

    if (parse_result != cgltf_result_success) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Failed to parse GLB file");
        return;
    }

    cgltf_result load_result = cgltf_load_buffers(&cgltf_opts, data, source_path);
    if (load_result != cgltf_result_success) {
        cgltf_free(data);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_READ);
        task->set_error_message("Failed to load GLB buffers");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        cgltf_free(data);
        return;
    }

    task->set_progress(0.2f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    int total_images = (int)data->images_count;
    if (total_images == 0) {
        cgltf_free(data);
        task->set_status(ConversionTask::COMPLETED);
        task->set_error(OK);
        task->set_progress(1.0f);
        task->set_error_message("No textures found in GLB file");
        call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
        return;
    }

    // Map quality to UASTC level
    uint32_t uastc_level;
    if (quality <= 50) {
        uastc_level = basisu::cPackUASTCLevelFastest;
    } else if (quality <= 100) {
        uastc_level = basisu::cPackUASTCLevelFaster;
    } else if (quality <= 150) {
        uastc_level = basisu::cPackUASTCLevelDefault;
    } else if (quality <= 200) {
        uastc_level = basisu::cPackUASTCLevelSlower;
    } else {
        uastc_level = basisu::cPackUASTCLevelVerySlow;
    }

    // Convert each image and store the KTX2 data
    std::vector<ConvertedTexture> converted_textures(data->images_count);
    int textures_converted = 0;

    for (size_t i = 0; i < data->images_count; i++) {
        converted_textures[i].converted = false;

        // Check for cancellation
        if (task->get_status() == ConversionTask::CANCELLED) {
            cgltf_free(data);
            return;
        }

        cgltf_image *image = &data->images[i];

        // Get image data
        const uint8_t *image_data = nullptr;
        size_t image_size = 0;

        if (image->buffer_view) {
            image_data = (const uint8_t *)image->buffer_view->buffer->data + image->buffer_view->offset;
            image_size = image->buffer_view->size;
            converted_textures[i].original_buffer_view_index = image->buffer_view - data->buffer_views;
        } else if (image->uri) {
            // External image - skip
            continue;
        } else {
            continue;
        }

        // Determine image format and load
        basisu::image img;
        bool loaded = false;

        // PNG magic: 89 50 4E 47
        if (image_size >= 4 && image_data[0] == 0x89 && image_data[1] == 0x50 &&
            image_data[2] == 0x4E && image_data[3] == 0x47) {
            loaded = basisu::load_png(image_data, image_size, img, nullptr);
        }
        // JPEG magic: FF D8 FF
        else if (image_size >= 3 && image_data[0] == 0xFF && image_data[1] == 0xD8 && image_data[2] == 0xFF) {
            int width, height, actual_comps;
            uint8_t *jpeg_data = jpgd::decompress_jpeg_image_from_memory(
                image_data, (int)image_size,
                &width, &height, &actual_comps, 4);

            if (jpeg_data) {
                img.resize(width, height);
                memcpy(img.get_ptr(), jpeg_data, width * height * 4);
                ::free(jpeg_data);
                loaded = true;
            }
        }

        if (!loaded) {
            continue;
        }

        // Setup basis encoder
        basisu::basis_compressor_params params;
        params.m_pJob_pool = basis_job_pool;
        params.m_source_images.push_back(img);
        params.m_uastc = true;
        params.m_pack_uastc_ldr_4x4_flags = uastc_level;
        params.m_create_ktx2_file = true;
        params.m_ktx2_uastc_supercompression = basist::KTX2_SS_ZSTANDARD;
        params.m_ktx2_zstd_supercompression_level = 6;
        params.m_mip_gen = mipmaps;
        if (mipmaps) {
            params.m_mip_filter = "kaiser";
        }
        params.m_status_output = false;

        basisu::basis_compressor compressor;
        if (!compressor.init(params)) {
            continue;
        }

        basisu::basis_compressor::error_code result = compressor.process();
        if (result != basisu::basis_compressor::cECSuccess) {
            continue;
        }

        // Store converted data
        const basisu::uint8_vec &ktx2_output = compressor.get_output_ktx2_file();
        converted_textures[i].ktx2_data.assign(ktx2_output.begin(), ktx2_output.end());
        converted_textures[i].converted = true;
        textures_converted++;

        // Update progress
        float progress = 0.2f + (0.5f * ((float)(i + 1) / (float)total_images));
        task->set_progress(progress);
        call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
    }

    if (textures_converted == 0) {
        cgltf_free(data);
        task->set_status(ConversionTask::FAILED);
        task->set_error(FAILED);
        task->set_error_message("No textures were converted");
        return;
    }

    task->set_progress(0.75f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Build new binary buffer with converted textures
    // First, copy non-image data from original buffer
    std::vector<uint8_t> new_bin_data;

    // Track which buffer view ranges are used by images
    std::vector<bool> is_image_buffer_view(data->buffer_views_count, false);
    for (size_t i = 0; i < data->images_count; i++) {
        if (data->images[i].buffer_view) {
            size_t bv_idx = data->images[i].buffer_view - data->buffer_views;
            is_image_buffer_view[bv_idx] = true;
        }
    }

    // Build mapping of old buffer view offsets to new offsets
    std::vector<size_t> new_buffer_view_offsets(data->buffer_views_count);
    std::vector<size_t> new_buffer_view_sizes(data->buffer_views_count);

    // Copy non-image buffer views first
    for (size_t i = 0; i < data->buffer_views_count; i++) {
        if (!is_image_buffer_view[i]) {
            cgltf_buffer_view *bv = &data->buffer_views[i];
            // Align to 4 bytes
            while (new_bin_data.size() % 4 != 0) {
                new_bin_data.push_back(0);
            }
            new_buffer_view_offsets[i] = new_bin_data.size();
            new_buffer_view_sizes[i] = bv->size;

            const uint8_t *src = (const uint8_t*)bv->buffer->data + bv->offset;
            new_bin_data.insert(new_bin_data.end(), src, src + bv->size);
        }
    }

    // Now add converted texture data
    for (size_t i = 0; i < data->images_count; i++) {
        if (converted_textures[i].converted && data->images[i].buffer_view) {
            size_t bv_idx = data->images[i].buffer_view - data->buffer_views;

            // Align to 4 bytes
            while (new_bin_data.size() % 4 != 0) {
                new_bin_data.push_back(0);
            }

            new_buffer_view_offsets[bv_idx] = new_bin_data.size();
            new_buffer_view_sizes[bv_idx] = converted_textures[i].ktx2_data.size();

            new_bin_data.insert(new_bin_data.end(),
                converted_textures[i].ktx2_data.begin(),
                converted_textures[i].ktx2_data.end());
        } else if (data->images[i].buffer_view) {
            // Keep original data for non-converted images
            size_t bv_idx = data->images[i].buffer_view - data->buffer_views;
            cgltf_buffer_view *bv = &data->buffer_views[bv_idx];

            while (new_bin_data.size() % 4 != 0) {
                new_bin_data.push_back(0);
            }

            new_buffer_view_offsets[bv_idx] = new_bin_data.size();
            new_buffer_view_sizes[bv_idx] = bv->size;

            const uint8_t *src = (const uint8_t*)bv->buffer->data + bv->offset;
            new_bin_data.insert(new_bin_data.end(), src, src + bv->size);
        }
    }

    // Pad to 4-byte alignment
    while (new_bin_data.size() % 4 != 0) {
        new_bin_data.push_back(0);
    }

    task->set_progress(0.85f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Modify JSON to update buffer views and mime types
    // We'll do simple string replacements for the buffer view sizes/offsets and mime types
    std::string new_json = json_str;

    // Update mime types for converted images
    for (size_t i = 0; i < data->images_count; i++) {
        if (converted_textures[i].converted) {
            cgltf_image *image = &data->images[i];
            if (image->mime_type) {
                // Replace old mime type with KTX2
                std::string old_mime = image->mime_type;
                // Find and replace in context of this image
                size_t pos = 0;
                while ((pos = new_json.find(old_mime, pos)) != std::string::npos) {
                    // Check if this is likely within an image definition
                    size_t context_start = (pos > 50) ? pos - 50 : 0;
                    std::string context = new_json.substr(context_start, pos - context_start);
                    if (context.find("\"mimeType\"") != std::string::npos ||
                        context.find("\"uri\"") != std::string::npos ||
                        context.find("\"bufferView\"") != std::string::npos) {
                        new_json.replace(pos, old_mime.length(), "image/ktx2");
                        pos += 10; // length of "image/ktx2"
                    } else {
                        pos += old_mime.length();
                    }
                }
            }
        }
    }

    // Update buffer view byte lengths
    for (size_t i = 0; i < data->buffer_views_count; i++) {
        cgltf_buffer_view *bv = &data->buffer_views[i];
        if (new_buffer_view_sizes[i] != bv->size) {
            // Find this buffer view in JSON and update byteLength
            char old_len[64], new_len[64];
            snprintf(old_len, sizeof(old_len), "\"byteLength\":%zu", (size_t)bv->size);
            snprintf(new_len, sizeof(new_len), "\"byteLength\":%zu", new_buffer_view_sizes[i]);

            size_t pos = new_json.find(old_len);
            if (pos != std::string::npos) {
                new_json.replace(pos, strlen(old_len), new_len);
            }

            // Also try with space after colon
            snprintf(old_len, sizeof(old_len), "\"byteLength\": %zu", (size_t)bv->size);
            pos = new_json.find(old_len);
            if (pos != std::string::npos) {
                snprintf(new_len, sizeof(new_len), "\"byteLength\": %zu", new_buffer_view_sizes[i]);
                new_json.replace(pos, strlen(old_len), new_len);
            }
        }

        if (new_buffer_view_offsets[i] != bv->offset) {
            char old_off[64], new_off[64];
            snprintf(old_off, sizeof(old_off), "\"byteOffset\":%zu", (size_t)bv->offset);
            snprintf(new_off, sizeof(new_off), "\"byteOffset\":%zu", new_buffer_view_offsets[i]);

            size_t pos = new_json.find(old_off);
            if (pos != std::string::npos) {
                new_json.replace(pos, strlen(old_off), new_off);
            }

            snprintf(old_off, sizeof(old_off), "\"byteOffset\": %zu", (size_t)bv->offset);
            pos = new_json.find(old_off);
            if (pos != std::string::npos) {
                snprintf(new_off, sizeof(new_off), "\"byteOffset\": %zu", new_buffer_view_offsets[i]);
                new_json.replace(pos, strlen(old_off), new_off);
            }
        }
    }

    // Update main buffer byteLength
    if (data->buffers_count > 0) {
        char old_buf_len[64], new_buf_len[64];
        snprintf(old_buf_len, sizeof(old_buf_len), "\"byteLength\":%zu", (size_t)data->buffers[0].size);
        snprintf(new_buf_len, sizeof(new_buf_len), "\"byteLength\":%zu", new_bin_data.size());

        // This is tricky - we need to find the buffer's byteLength, not a bufferView's
        // Look for it in the "buffers" array context
        size_t buffers_pos = new_json.find("\"buffers\"");
        if (buffers_pos != std::string::npos) {
            size_t search_start = buffers_pos;
            size_t pos = new_json.find(old_buf_len, search_start);
            if (pos != std::string::npos && pos < buffers_pos + 200) {
                new_json.replace(pos, strlen(old_buf_len), new_buf_len);
            } else {
                snprintf(old_buf_len, sizeof(old_buf_len), "\"byteLength\": %zu", (size_t)data->buffers[0].size);
                pos = new_json.find(old_buf_len, search_start);
                if (pos != std::string::npos && pos < buffers_pos + 200) {
                    snprintf(new_buf_len, sizeof(new_buf_len), "\"byteLength\": %zu", new_bin_data.size());
                    new_json.replace(pos, strlen(old_buf_len), new_buf_len);
                }
            }
        }
    }

    cgltf_free(data);

    // Pad JSON to 4-byte alignment
    while (new_json.size() % 4 != 0) {
        new_json.push_back(' ');
    }

    task->set_progress(0.9f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Write new GLB file
    CharString output_utf8 = output_path.utf8();
    std::ofstream outfile(output_utf8.get_data(), std::ios::binary);
    if (!outfile.is_open()) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to create output GLB file");
        return;
    }

    // Calculate total length
    uint32_t json_chunk_len = (uint32_t)new_json.size();
    uint32_t bin_chunk_len = (uint32_t)new_bin_data.size();
    uint32_t total_len = 12 + 8 + json_chunk_len + 8 + bin_chunk_len;

    // Write header
    uint32_t glb_magic = 0x46546C67; // "glTF"
    uint32_t glb_version = 2;
    outfile.write((char*)&glb_magic, 4);
    outfile.write((char*)&glb_version, 4);
    outfile.write((char*)&total_len, 4);

    // Write JSON chunk
    uint32_t json_type = 0x4E4F534A; // "JSON"
    outfile.write((char*)&json_chunk_len, 4);
    outfile.write((char*)&json_type, 4);
    outfile.write(new_json.data(), json_chunk_len);

    // Write BIN chunk
    uint32_t bin_type = 0x004E4942; // "BIN\0"
    outfile.write((char*)&bin_chunk_len, 4);
    outfile.write((char*)&bin_type, 4);
    outfile.write((char*)new_bin_data.data(), bin_chunk_len);

    outfile.close();

    if (!outfile.good()) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to write GLB file");
        return;
    }

    // Success
    task->set_status(ConversionTask::COMPLETED);
    task->set_error(OK);
    task->set_error_message("Converted " + String::num_int64(textures_converted) + " textures to KTX2 in GLB");
    task->set_progress(1.0f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
}

void AssetConverter::_normalize_audio(Ref<ConversionTask> task) {
    CharString source_utf8 = task->get_source_path().utf8();
    CharString output_utf8 = task->get_output_path().utf8();
    const char *source_path = source_utf8.get_data();
    const char *output_path = output_utf8.get_data();

    Dictionary options = task->get_options();
    float target_db = options.get("target_db", -14.0f);
    float peak_limit_db = options.get("peak_limit_db", -1.0f);

    task->set_progress(0.1f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Only WAV input is supported
    String lower_path = task->get_source_path().to_lower();
    if (!lower_path.ends_with(".wav")) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_INVALID_DATA);
        task->set_error_message("Only WAV input format is supported for audio normalization");
        return;
    }

    // Open WAV file
    drwav wav;
    if (!drwav_init_file(&wav, source_path, nullptr)) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_OPEN);
        task->set_error_message("Failed to open WAV file");
        return;
    }

    unsigned int channels = wav.channels;
    unsigned int sample_rate = wav.sampleRate;
    drwav_uint64 total_frame_count = wav.totalPCMFrameCount;

    float *samples = (float *)malloc(sizeof(float) * total_frame_count * channels);
    if (!samples) {
        drwav_uninit(&wav);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_OUT_OF_MEMORY);
        task->set_error_message("Failed to allocate memory for audio samples");
        return;
    }

    drwav_uint64 frames_read = drwav_read_pcm_frames_f32(&wav, total_frame_count, samples);
    drwav_uninit(&wav);

    if (frames_read != total_frame_count) {
        ::free(samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CORRUPT);
        task->set_error_message("Failed to read all audio frames");
        return;
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        ::free(samples);
        return;
    }

    task->set_progress(0.3f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Calculate current peak
    size_t total_samples = total_frame_count * channels;
    float current_peak = 0.0f;
    for (size_t i = 0; i < total_samples; i++) {
        float abs_sample = std::fabs(samples[i]);
        if (abs_sample > current_peak) {
            current_peak = abs_sample;
        }
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        ::free(samples);
        return;
    }

    task->set_progress(0.5f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Calculate gain needed for normalization
    // target_db is the target peak level in dB (e.g., -14 dB)
    // peak_limit_db is the absolute limit (e.g., -1 dB to avoid clipping)
    float target_linear = std::pow(10.0f, target_db / 20.0f);
    float peak_limit_linear = std::pow(10.0f, peak_limit_db / 20.0f);

    float gain = 1.0f;
    if (current_peak > 0.0f) {
        gain = target_linear / current_peak;
        // Limit gain to avoid exceeding peak limit
        float max_gain = peak_limit_linear / current_peak;
        if (gain > max_gain) {
            gain = max_gain;
        }
    }

    // Apply gain with soft limiting
    for (size_t i = 0; i < total_samples; i++) {
        samples[i] *= gain;
        // Hard clip at peak limit
        if (samples[i] > peak_limit_linear) {
            samples[i] = peak_limit_linear;
        } else if (samples[i] < -peak_limit_linear) {
            samples[i] = -peak_limit_linear;
        }
    }

    // Check for cancellation
    if (task->get_status() == ConversionTask::CANCELLED) {
        ::free(samples);
        return;
    }

    task->set_progress(0.7f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Convert float samples to 16-bit PCM for WAV output
    int16_t *pcm_samples = (int16_t *)malloc(sizeof(int16_t) * total_samples);
    if (!pcm_samples) {
        ::free(samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_OUT_OF_MEMORY);
        task->set_error_message("Failed to allocate memory for PCM output");
        return;
    }

    for (size_t i = 0; i < total_samples; i++) {
        float clamped = samples[i];
        if (clamped > 1.0f) clamped = 1.0f;
        if (clamped < -1.0f) clamped = -1.0f;
        pcm_samples[i] = (int16_t)(clamped * 32767.0f);
    }

    ::free(samples);

    task->set_progress(0.8f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());

    // Write output WAV file
    drwav_data_format format;
    format.container = drwav_container_riff;
    format.format = DR_WAVE_FORMAT_PCM;
    format.channels = channels;
    format.sampleRate = sample_rate;
    format.bitsPerSample = 16;

    drwav wav_out;
    if (!drwav_init_file_write(&wav_out, output_path, &format, nullptr)) {
        ::free(pcm_samples);
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to create output WAV file");
        return;
    }

    drwav_uint64 frames_written = drwav_write_pcm_frames(&wav_out, total_frame_count, pcm_samples);
    drwav_uninit(&wav_out);
    ::free(pcm_samples);

    if (frames_written != total_frame_count) {
        task->set_status(ConversionTask::FAILED);
        task->set_error(ERR_FILE_CANT_WRITE);
        task->set_error_message("Failed to write all audio frames");
        return;
    }

    // Success
    task->set_status(ConversionTask::COMPLETED);
    task->set_error(OK);
    task->set_progress(1.0f);
    call_deferred("_emit_progress", task->get_id(), task->get_source_path(), task->get_progress());
}

// Public async methods

int AssetConverter::image_to_ktx2(const String &source_path, const String &output_path, int quality, bool mipmaps) {
    Ref<ConversionTask> task = ConversionTask::create_image_to_ktx2(source_path, output_path, quality, mipmaps);

    queue_mutex->lock();
    task->set_id(next_task_id++);
    task_queue.push_back(task);
    queue_mutex->unlock();

    work_semaphore->post();

    return task->get_id();
}

int AssetConverter::audio_to_mp3(const String &source_path, const String &output_path, int bitrate) {
    Ref<ConversionTask> task = ConversionTask::create_audio_to_mp3(source_path, output_path, bitrate);

    queue_mutex->lock();
    task->set_id(next_task_id++);
    task_queue.push_back(task);
    queue_mutex->unlock();

    work_semaphore->post();

    return task->get_id();
}

int AssetConverter::glb_textures_to_ktx2(const String &source_path, const String &output_path, int quality, bool mipmaps) {
    Ref<ConversionTask> task = ConversionTask::create_glb_textures_to_ktx2(source_path, output_path, quality, mipmaps);

    queue_mutex->lock();
    task->set_id(next_task_id++);
    task_queue.push_back(task);
    queue_mutex->unlock();

    work_semaphore->post();

    return task->get_id();
}

int AssetConverter::normalize_audio(const String &source_path, const String &output_path, float target_db, float peak_limit_db) {
    Ref<ConversionTask> task = ConversionTask::create_normalize_audio(source_path, output_path, target_db, peak_limit_db);

    queue_mutex->lock();
    task->set_id(next_task_id++);
    task_queue.push_back(task);
    queue_mutex->unlock();

    work_semaphore->post();

    return task->get_id();
}

void AssetConverter::convert_batch(const TypedArray<ConversionTask> &tasks) {
    queue_mutex->lock();
    is_batch_mode = true;
    batch_results.clear();

    for (const auto &variant : tasks) {
        Ref<ConversionTask> task = variant;
        if (task.is_valid()) {
            task->set_id(next_task_id++);
            task_queue.push_back(task);
        }
    }
    queue_mutex->unlock();

    // Signal for each task
    for (int i = 0; i < tasks.size(); i++) {
        work_semaphore->post();
    }
}

bool AssetConverter::cancel(int task_id) {
    queue_mutex->lock();
    for (auto &task : task_queue) {
        if (task->get_id() == task_id) {
            task->set_status(ConversionTask::CANCELLED);
            task->set_error(ERR_SKIP);
            task->set_error_message("Task cancelled");
            queue_mutex->unlock();
            return true;
        }
    }
    queue_mutex->unlock();
    return false;
}

void AssetConverter::cancel_all() {
    queue_mutex->lock();
    for (auto &task : task_queue) {
        task->set_status(ConversionTask::CANCELLED);
        task->set_error(ERR_SKIP);
        task->set_error_message("Task cancelled");
    }
    queue_mutex->unlock();
}

bool AssetConverter::is_running() const {
    queue_mutex->lock();
    bool running = !task_queue.is_empty();
    queue_mutex->unlock();
    return running;
}

int AssetConverter::get_pending_count() const {
    queue_mutex->lock();
    int count = task_queue.size();
    queue_mutex->unlock();
    return count;
}
