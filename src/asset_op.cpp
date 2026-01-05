#include "asset_op.h"

using namespace godot;

AssetOP *AssetOP::singleton = nullptr;

void AssetOP::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_converter"), &AssetOP::get_converter);
    ClassDB::bind_static_method("AssetOP", D_METHOD("probe", "file_path"), &AssetOP::probe);
}

AssetOP *AssetOP::get_singleton() {
    return singleton;
}

AssetOP::AssetOP() {
    if (singleton == nullptr) {
        singleton = this;
    }
    converter.instantiate();
}

AssetOP::~AssetOP() {
    if (singleton == this) {
        singleton = nullptr;
    }
}

Ref<AssetConverter> AssetOP::get_converter() {
    return converter;
}

Dictionary AssetOP::probe(const String &file_path) {
    // Auto-detect file type by extension
    String lower_path = file_path.to_lower();

    if (lower_path.ends_with(".glb") || lower_path.ends_with(".gltf")) {
        return AssetProbe::probe_glb(file_path);
    } else if (lower_path.ends_with(".ktx2") || lower_path.ends_with(".ktx")) {
        return AssetProbe::probe_ktx2(file_path);
    } else if (lower_path.ends_with(".wav") ||
               lower_path.ends_with(".mp3") ||
               lower_path.ends_with(".ogg") ||
               lower_path.ends_with(".flac")) {
        return AssetProbe::probe_audio(file_path, false);
    } else {
        Dictionary result;
        result["error"] = "Unknown file type: " + file_path;
        return result;
    }
}
