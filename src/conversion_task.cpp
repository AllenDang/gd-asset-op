#include "conversion_task.h"

using namespace godot;

void ConversionTask::_bind_methods() {
    // Enums
    BIND_ENUM_CONSTANT(IMAGE_TO_KTX2);
    BIND_ENUM_CONSTANT(AUDIO_TO_MP3);
    BIND_ENUM_CONSTANT(GLB_TEXTURES_TO_KTX2);
    BIND_ENUM_CONSTANT(NORMALIZE_AUDIO);

    BIND_ENUM_CONSTANT(PENDING);
    BIND_ENUM_CONSTANT(RUNNING);
    BIND_ENUM_CONSTANT(COMPLETED);
    BIND_ENUM_CONSTANT(FAILED);
    BIND_ENUM_CONSTANT(CANCELLED);

    // Properties
    ClassDB::bind_method(D_METHOD("get_id"), &ConversionTask::get_id);
    ClassDB::bind_method(D_METHOD("get_type"), &ConversionTask::get_type);
    ClassDB::bind_method(D_METHOD("get_status"), &ConversionTask::get_status);
    ClassDB::bind_method(D_METHOD("get_source_path"), &ConversionTask::get_source_path);
    ClassDB::bind_method(D_METHOD("get_output_path"), &ConversionTask::get_output_path);
    ClassDB::bind_method(D_METHOD("get_options"), &ConversionTask::get_options);
    ClassDB::bind_method(D_METHOD("get_progress"), &ConversionTask::get_progress);
    ClassDB::bind_method(D_METHOD("get_error"), &ConversionTask::get_error);
    ClassDB::bind_method(D_METHOD("get_error_message"), &ConversionTask::get_error_message);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "id"), "", "get_id");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "type", PROPERTY_HINT_ENUM, "IMAGE_TO_KTX2,AUDIO_TO_MP3,GLB_TEXTURES_TO_KTX2,NORMALIZE_AUDIO"), "", "get_type");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "status", PROPERTY_HINT_ENUM, "PENDING,RUNNING,COMPLETED,FAILED,CANCELLED"), "", "get_status");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "source_path"), "", "get_source_path");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "output_path"), "", "get_output_path");
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "options"), "", "get_options");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "progress"), "", "get_progress");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "error"), "", "get_error");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "error_message"), "", "get_error_message");

    // Factory methods
    ClassDB::bind_static_method("ConversionTask", D_METHOD("create_image_to_ktx2", "source", "output", "quality", "mipmaps"), &ConversionTask::create_image_to_ktx2, DEFVAL(128), DEFVAL(true));
    ClassDB::bind_static_method("ConversionTask", D_METHOD("create_audio_to_mp3", "source", "output", "bitrate"), &ConversionTask::create_audio_to_mp3, DEFVAL(192));
    ClassDB::bind_static_method("ConversionTask", D_METHOD("create_glb_textures_to_ktx2", "source", "output", "quality", "mipmaps"), &ConversionTask::create_glb_textures_to_ktx2, DEFVAL(128), DEFVAL(true));
    ClassDB::bind_static_method("ConversionTask", D_METHOD("create_normalize_audio", "source", "output", "target_db", "peak_limit_db"), &ConversionTask::create_normalize_audio, DEFVAL(-14.0f), DEFVAL(-1.0f));
}

ConversionTask::ConversionTask() {
    id = -1;
    type = IMAGE_TO_KTX2;
    status = PENDING;
    progress = 0.0f;
    error = OK;
}

ConversionTask::~ConversionTask() = default;

// Getters
int ConversionTask::get_id() const { return id; }
ConversionTask::Type ConversionTask::get_type() const { return type; }
ConversionTask::Status ConversionTask::get_status() const { return status; }
String ConversionTask::get_source_path() const { return source_path; }
String ConversionTask::get_output_path() const { return output_path; }
Dictionary ConversionTask::get_options() const { return options; }
float ConversionTask::get_progress() const { return progress; }
Error ConversionTask::get_error() const { return error; }
String ConversionTask::get_error_message() const { return error_message; }

// Setters
void ConversionTask::set_id(int p_id) { id = p_id; }
void ConversionTask::set_type(Type p_type) { type = p_type; }
void ConversionTask::set_status(Status p_status) { status = p_status; }
void ConversionTask::set_source_path(const String &p_path) { source_path = p_path; }
void ConversionTask::set_output_path(const String &p_path) { output_path = p_path; }
void ConversionTask::set_options(const Dictionary &p_options) { options = p_options; }
void ConversionTask::set_progress(float p_progress) { progress = p_progress; }
void ConversionTask::set_error(Error p_error) { error = p_error; }
void ConversionTask::set_error_message(const String &p_message) { error_message = p_message; }

// Factory methods
Ref<ConversionTask> ConversionTask::create_image_to_ktx2(const String &source, const String &output, int quality, bool mipmaps) {
    Ref<ConversionTask> task;
    task.instantiate();
    task->set_type(IMAGE_TO_KTX2);
    task->set_source_path(source);
    task->set_output_path(output);

    Dictionary opts;
    opts["quality"] = quality;
    opts["mipmaps"] = mipmaps;
    task->set_options(opts);

    return task;
}

Ref<ConversionTask> ConversionTask::create_audio_to_mp3(const String &source, const String &output, int bitrate) {
    Ref<ConversionTask> task;
    task.instantiate();
    task->set_type(AUDIO_TO_MP3);
    task->set_source_path(source);
    task->set_output_path(output);

    Dictionary opts;
    opts["bitrate"] = bitrate;
    task->set_options(opts);

    return task;
}

Ref<ConversionTask> ConversionTask::create_glb_textures_to_ktx2(const String &source, const String &output, int quality, bool mipmaps) {
    Ref<ConversionTask> task;
    task.instantiate();
    task->set_type(GLB_TEXTURES_TO_KTX2);
    task->set_source_path(source);
    task->set_output_path(output);

    Dictionary opts;
    opts["quality"] = quality;
    opts["mipmaps"] = mipmaps;
    task->set_options(opts);

    return task;
}

Ref<ConversionTask> ConversionTask::create_normalize_audio(const String &source, const String &output, float target_db, float peak_limit_db) {
    Ref<ConversionTask> task;
    task.instantiate();
    task->set_type(NORMALIZE_AUDIO);
    task->set_source_path(source);
    task->set_output_path(output);

    Dictionary opts;
    opts["target_db"] = target_db;
    opts["peak_limit_db"] = peak_limit_db;
    task->set_options(opts);

    return task;
}
