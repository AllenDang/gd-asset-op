#ifndef ASSET_OP_H
#define ASSET_OP_H

#include "asset_converter.h"
#include "asset_probe.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AssetOP : public Object {
    GDCLASS(AssetOP, Object)

private:
    static AssetOP *singleton;
    Ref<AssetConverter> converter;

protected:
    static void _bind_methods();

public:
    static AssetOP *get_singleton();

    AssetOP();
    ~AssetOP() override;

    // Get converter instance (singleton)
    Ref<AssetConverter> get_converter();

    // Auto-detect file type and probe
    static Dictionary probe(const String &file_path);
};

} // namespace godot

#endif // ASSET_OP_H
