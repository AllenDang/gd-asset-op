#ifndef ASSET_CONVERTER_H
#define ASSET_CONVERTER_H

#include "conversion_task.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/classes/semaphore.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/templates/vector.hpp>

// Forward declaration for basis job pool
namespace basisu { class job_pool; }

namespace godot {

class AssetConverter : public RefCounted {
    GDCLASS(AssetConverter, RefCounted)

private:
    // Task queue
    Vector<Ref<ConversionTask>> task_queue;
    Ref<Mutex> queue_mutex;

    // Worker thread
    Ref<Thread> worker_thread;
    Ref<Semaphore> work_semaphore;
    bool should_exit;
    bool is_batch_mode;

    // Task ID counter
    int next_task_id;

    // Batch results
    Array batch_results;

    // Basis Universal job pool for texture compression
    basisu::job_pool *basis_job_pool;

    // Internal methods
    void _worker_function();
    void _process_task(Ref<ConversionTask> task);
    void _emit_started(int task_id, const String &source_path);
    void _emit_progress(int task_id, const String &source_path, float progress);
    void _emit_completed(int task_id, const String &source_path, const String &output_path, Error error, const String &error_message);
    void _emit_batch_completed(const Array &results);

    // Conversion implementations
    void _convert_image_to_ktx2(Ref<ConversionTask> task);
    void _convert_audio_to_mp3(Ref<ConversionTask> task);
    void _convert_glb_textures_to_ktx2(Ref<ConversionTask> task);
    void _normalize_audio(Ref<ConversionTask> task);

protected:
    static void _bind_methods();

public:
    AssetConverter();
    ~AssetConverter();

    // Conversion methods (all async)
    int image_to_ktx2(const String &source_path, const String &output_path, int quality = 128, bool mipmaps = true);
    int audio_to_mp3(const String &source_path, const String &output_path, int bitrate = 192);
    int glb_textures_to_ktx2(const String &source_path, const String &output_path = "", int quality = 128, bool mipmaps = true);
    int normalize_audio(const String &source_path, const String &output_path, float target_db = -14.0f, float peak_limit_db = -1.0f);

    // Batch conversion
    void convert_batch(const TypedArray<ConversionTask> &tasks);

    // Control methods
    bool cancel(int task_id);
    void cancel_all();
    bool is_running() const;
    int get_pending_count() const;
};

} // namespace godot

#endif // ASSET_CONVERTER_H
