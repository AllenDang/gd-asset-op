class_name TestConvertGlb
extends "res://test/test_base.gd"
## Detailed tests for AssetConverter.glb_textures_to_ktx2()

var _converter: AssetConverter
var _completed_tasks: Dictionary = {}
var _progress_updates: Dictionary = {}


func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] glb_textures_to_ktx2")

	# Initialize converter
	_converter = AssetConverter.new()
	_converter.conversion_started.connect(_on_started)
	_converter.conversion_progress.connect(_on_progress)
	_converter.conversion_completed.connect(_on_completed)

	var tests = [
		"test_glb_convert_basic",
		"test_glb_convert_output_valid",
		"test_glb_convert_textures_are_ktx2",
		"test_glb_convert_mesh_data_preserved",
		"test_glb_convert_materials_preserved",
		"test_glb_convert_texture_count_preserved",
		"test_glb_convert_progress_signals",
		"test_glb_convert_missing_file",
		"test_glb_convert_invalid_file",
	]

	for test_name in tests:
		if has_method(test_name):
			await call(test_name)
			var passed = end_test()
			results.tests.append({"name": test_name, "passed": passed})
			if passed:
				results.passed += 1
			else:
				results.failed += 1

	return results


func _on_started(task_id: int, _source_path: String):
	_progress_updates[task_id] = []


func _on_progress(task_id: int, _source_path: String, progress: float):
	if _progress_updates.has(task_id):
		_progress_updates[task_id].append(progress)


func _on_completed(task_id: int, _source_path: String, output_path: String, error: int, error_message: String):
	_completed_tasks[task_id] = {
		"error": error,
		"error_message": error_message,
		"output_path": output_path
	}


func _wait_for_task(task_id: int, timeout: float = 60.0) -> Dictionary:
	var elapsed = 0.0
	while not _completed_tasks.has(task_id) and elapsed < timeout:
		await Engine.get_main_loop().create_timer(0.1).timeout
		elapsed += 0.1

	if _completed_tasks.has(task_id):
		return _completed_tasks[task_id]
	return {"error": ERR_TIMEOUT, "error_message": "Timeout", "output_path": ""}


func _clear_task(task_id: int):
	_completed_tasks.erase(task_id)
	_progress_updates.erase(task_id)


# ============================================================
# Test: Basic GLB texture conversion
# ============================================================
func test_glb_convert_basic():
	begin_test("GLB texture to KTX2 basic conversion")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_basic.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)

	assert_gte(task_id, 0, "task_id should be >= 0")

	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")
	assert_file_exists(output, "output file should exist")

	# Validate GLB magic bytes
	assert_true(validate_glb_header(output), "output should have GLB magic")

	# File should have meaningful size
	var file_size = get_file_size(output)
	assert_gt(file_size, 500, "GLB should have meaningful content")

	_clear_task(task_id)


# ============================================================
# Test: Output is valid GLB
# ============================================================
func test_glb_convert_output_valid():
	begin_test("GLB conversion produces valid GLB")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_valid.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Validate GLB header bytes: glTF (0x46546C67 in little-endian)
	var header = read_file_bytes(output, 12)
	assert_eq(header[0], 0x67, "GLB magic byte 0 should be 'g'")
	assert_eq(header[1], 0x6C, "GLB magic byte 1 should be 'l'")
	assert_eq(header[2], 0x54, "GLB magic byte 2 should be 'T'")
	assert_eq(header[3], 0x46, "GLB magic byte 3 should be 'F'")

	# Version should be 2 (bytes 4-7)
	assert_eq(header[4], 0x02, "GLB version should be 2")
	assert_eq(header[5], 0x00, "GLB version high byte")

	# Should be probeable
	var probe = AssetProbe.probe_glb(output)
	assert_no_error(probe, "output GLB should be probeable")

	_clear_task(task_id)


# ============================================================
# Test: Textures are converted to KTX2
# ============================================================
func test_glb_convert_textures_are_ktx2():
	begin_test("GLB embedded textures are KTX2")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_ktx2.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	# Probe source to see original texture format
	var source_probe = AssetProbe.probe_glb(source)
	assert_no_error(source_probe)
	assert_gt(source_probe.textures.size(), 0, "source should have textures")

	# Source textures should be PNG
	if source_probe.textures.size() > 0:
		assert_eq(source_probe.textures[0].mime_type, "image/png", "source texture should be PNG")

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Probe output GLB
	var probe = AssetProbe.probe_glb(output)
	assert_no_error(probe)

	# Check all textures are now KTX2
	assert_gt(probe.textures.size(), 0, "output should have textures")

	for i in range(probe.textures.size()):
		var tex = probe.textures[i]
		assert_eq(tex.mime_type, "image/ktx2", "texture %d should be KTX2 format" % i)

	_clear_task(task_id)


# ============================================================
# Test: Mesh data preserved exactly
# ============================================================
func test_glb_convert_mesh_data_preserved():
	begin_test("GLB mesh data preserved after conversion")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_mesh.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	# Probe source
	var source_probe = AssetProbe.probe_glb(source)
	assert_no_error(source_probe)

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Probe output
	var output_probe = AssetProbe.probe_glb(output)
	assert_no_error(output_probe)

	# Mesh counts must be exactly identical
	assert_eq(output_probe.face_count, source_probe.face_count, "face_count must match exactly")
	assert_eq(output_probe.vertex_count, source_probe.vertex_count, "vertex_count must match exactly")
	assert_eq(output_probe.meshes.size(), source_probe.meshes.size(), "mesh count must match")

	# AABB must be exactly identical (mesh geometry unchanged)
	var src_aabb = source_probe.aabb
	var out_aabb = output_probe.aabb

	assert_approx(out_aabb.position.x, src_aabb.position.x, 0.0001, "AABB position.x must match")
	assert_approx(out_aabb.position.y, src_aabb.position.y, 0.0001, "AABB position.y must match")
	assert_approx(out_aabb.position.z, src_aabb.position.z, 0.0001, "AABB position.z must match")
	assert_approx(out_aabb.size.x, src_aabb.size.x, 0.0001, "AABB size.x must match")
	assert_approx(out_aabb.size.y, src_aabb.size.y, 0.0001, "AABB size.y must match")
	assert_approx(out_aabb.size.z, src_aabb.size.z, 0.0001, "AABB size.z must match")

	# Validate individual mesh data
	for i in range(source_probe.meshes.size()):
		var src_mesh = source_probe.meshes[i]
		var out_mesh = output_probe.meshes[i]

		assert_eq(out_mesh.face_count, src_mesh.face_count, "mesh %d face_count must match" % i)
		assert_eq(out_mesh.vertex_count, src_mesh.vertex_count, "mesh %d vertex_count must match" % i)
		assert_eq(out_mesh.primitive_count, src_mesh.primitive_count, "mesh %d primitive_count must match" % i)

	_clear_task(task_id)


# ============================================================
# Test: Materials preserved exactly
# ============================================================
func test_glb_convert_materials_preserved():
	begin_test("GLB materials preserved after conversion")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_materials.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	# Probe source
	var source_probe = AssetProbe.probe_glb(source)
	assert_no_error(source_probe)

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Probe output
	var output_probe = AssetProbe.probe_glb(output)
	assert_no_error(output_probe)

	# Material count must be identical
	assert_eq(output_probe.materials.size(), source_probe.materials.size(), "material count must match")

	# Material names must be identical
	for i in range(source_probe.materials.size()):
		assert_eq(output_probe.materials[i], source_probe.materials[i], "material %d name must match" % i)

	# Skeleton and animation info must be preserved
	assert_eq(output_probe.has_skeleton, source_probe.has_skeleton, "has_skeleton must match")
	assert_eq(output_probe.animations.size(), source_probe.animations.size(), "animation count must match")

	_clear_task(task_id)


# ============================================================
# Test: Texture count preserved
# ============================================================
func test_glb_convert_texture_count_preserved():
	begin_test("GLB texture count preserved")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_texcount.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	# Probe source
	var source_probe = AssetProbe.probe_glb(source)
	assert_no_error(source_probe)
	var source_tex_count = source_probe.textures.size()

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Probe output
	var output_probe = AssetProbe.probe_glb(output)
	assert_no_error(output_probe)

	# Texture count must be identical
	assert_eq(output_probe.textures.size(), source_tex_count, "texture count must match exactly")

	# Each texture should have same name (if named)
	for i in range(source_probe.textures.size()):
		var src_tex = source_probe.textures[i]
		var out_tex = output_probe.textures[i]

		if src_tex.has("name") and src_tex.name != "":
			assert_eq(out_tex.name, src_tex.name, "texture %d name must match" % i)

	_clear_task(task_id)


# ============================================================
# Test: Progress signals emitted correctly
# ============================================================
func test_glb_convert_progress_signals():
	begin_test("GLB conversion emits progress signals")

	var source = get_asset_path("test.glb")
	var output = get_output_path("test_glb_progress.glb")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	assert_true(_progress_updates.has(task_id), "should have progress updates")

	if _progress_updates.has(task_id):
		var updates = _progress_updates[task_id]
		assert_gt(updates.size(), 0, "should have at least 1 progress update")

		# All progress values must be in [0, 1]
		for i in range(updates.size()):
			assert_gte(updates[i], 0.0, "progress[%d] must be >= 0" % i)
			assert_lte(updates[i], 1.0, "progress[%d] must be <= 1" % i)

		# Final progress must be exactly 1.0
		if updates.size() > 0:
			assert_eq(updates[-1], 1.0, "final progress must be 1.0")

		# Progress should be monotonically increasing
		for i in range(1, updates.size()):
			assert_gte(updates[i], updates[i-1], "progress should be monotonic")

	_clear_task(task_id)


# ============================================================
# Test: Missing file error
# ============================================================
func test_glb_convert_missing_file():
	begin_test("GLB conversion fails for missing file")

	var source = "/nonexistent/model.glb"
	var output = get_output_path("missing.glb")

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail")
	assert_string_contains(result.error_message, "not found", "error should mention 'not found'")
	assert_false(FileAccess.file_exists(output), "output should not be created")

	_clear_task(task_id)


# ============================================================
# Test: Invalid file error
# ============================================================
func test_glb_convert_invalid_file():
	begin_test("GLB conversion fails for invalid file")

	var source = get_asset_path("test.png")  # PNG is not GLB
	var output = get_output_path("invalid.glb")

	var task_id = _converter.glb_textures_to_ktx2(source, output, 128)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail for non-GLB input")
	assert_false(FileAccess.file_exists(output), "output should not be created")

	_clear_task(task_id)
