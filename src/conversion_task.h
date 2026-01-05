#ifndef CONVERSION_TASK_H
#define CONVERSION_TASK_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class ConversionTask : public RefCounted {
    GDCLASS(ConversionTask, RefCounted)

public:
    enum Type {
        IMAGE_TO_KTX2,
        AUDIO_TO_MP3,
        GLB_TEXTURES_TO_KTX2,
        NORMALIZE_AUDIO
    };

    enum Status {
        PENDING,
        RUNNING,
        COMPLETED,
        FAILED,
        CANCELLED
    };

private:
    int id;
    Type type;
    Status status;
    String source_path;
    String output_path;
    Dictionary options;
    float progress;
    Error error;
    String error_message;

protected:
    static void _bind_methods();

public:
    ConversionTask();
    ~ConversionTask();

    // Getters
    int get_id() const;
    Type get_type() const;
    Status get_status() const;
    String get_source_path() const;
    String get_output_path() const;
    Dictionary get_options() const;
    float get_progress() const;
    Error get_error() const;
    String get_error_message() const;

    // Setters (internal use)
    void set_id(int p_id);
    void set_type(Type p_type);
    void set_status(Status p_status);
    void set_source_path(const String &p_path);
    void set_output_path(const String &p_path);
    void set_options(const Dictionary &p_options);
    void set_progress(float p_progress);
    void set_error(Error p_error);
    void set_error_message(const String &p_message);

    // Factory methods
    static Ref<ConversionTask> create_image_to_ktx2(const String &source, const String &output, int quality = 128, bool mipmaps = true);
    static Ref<ConversionTask> create_audio_to_mp3(const String &source, const String &output, int bitrate = 192);
    static Ref<ConversionTask> create_glb_textures_to_ktx2(const String &source, const String &output, int quality = 128, bool mipmaps = true);
    static Ref<ConversionTask> create_normalize_audio(const String &source, const String &output, float target_db = -14.0f, float peak_limit_db = -1.0f);
};

} // namespace godot

VARIANT_ENUM_CAST(ConversionTask::Type);
VARIANT_ENUM_CAST(ConversionTask::Status);

#endif // CONVERSION_TASK_H
