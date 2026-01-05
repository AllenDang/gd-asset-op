#ifndef ASSET_PROBE_H
#define ASSET_PROBE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AssetProbe : public RefCounted {
    GDCLASS(AssetProbe, RefCounted)

protected:
    static void _bind_methods();

public:
    AssetProbe();
    ~AssetProbe() override;

    // Probe methods
    static Dictionary probe_glb(const String &file_path);
    static Dictionary probe_ktx2(const String &file_path);
    static Dictionary probe_audio(const String &file_path, bool analyze_volume = false);
};

} // namespace godot

#endif // ASSET_PROBE_H
