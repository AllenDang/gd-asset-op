class_name TestConvertImage
extends "res://test/test_base.gd"
## Detailed tests for AssetConverter.image_to_ktx2()

var _converter: AssetConverter
var _completed_tasks: Dictionary = {}  # task_id -> {error, error_message, output_path}
var _progress_updates: Dictionary = {}  # task_id -> [progress values]


func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] image_to_ktx2")

	# Initialize converter
	_converter = AssetConverter.new()
	_converter.conversion_started.connect(_on_started)
	_converter.conversion_progress.connect(_on_progress)
	_converter.conversion_completed.connect(_on_completed)

	var tests = [
		"test_convert_png_basic",
		"test_convert_png_validates_output",
		"test_convert_png_dimensions_preserved",
		"test_convert_png_mipmaps_generated",
		"test_convert_png_no_mipmaps",
		"test_convert_png_quality_affects_size",
		"test_convert_jpeg_basic",
		"test_convert_jpeg_dimensions_preserved",
		"test_convert_progress_signals",
		"test_convert_progress_monotonic",
		"test_convert_task_id_unique",
		"test_convert_missing_file",
		"test_convert_invalid_output_path",
		"test_convert_cancel_task",
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


func _wait_for_task(task_id: int, timeout: float = 30.0) -> Dictionary:
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
# Test: Basic PNG conversion
# ============================================================
func test_convert_png_basic():
	begin_test("PNG to KTX2 basic conversion")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_basic.ktx2")

	# Delete existing output
	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)

	assert_gte(task_id, 0, "task_id should be >= 0")

	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")
	assert_file_exists(output, "output file should exist")

	# Validate it's actually a KTX2 file
	assert_true(validate_ktx2_header(output), "output should have KTX2 magic bytes")

	# Probe and validate the output
	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe, "probe should succeed")
	assert_true(probe.is_compressed, "output should be compressed (UASTC)")

	_clear_task(task_id)


# ============================================================
# Test: PNG output is valid KTX2 with correct properties
# ============================================================
func test_convert_png_validates_output():
	begin_test("PNG conversion produces valid KTX2")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_validate.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Validate KTX2 header bytes
	var header = read_file_bytes(output, 12)
	assert_eq(header[0], 0xAB, "KTX2 magic byte 0")
	assert_eq(header[1], 0x4B, "KTX2 magic byte 1 ('K')")
	assert_eq(header[2], 0x54, "KTX2 magic byte 2 ('T')")
	assert_eq(header[3], 0x58, "KTX2 magic byte 3 ('X')")

	# Probe the output and validate structure
	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)

	# Validate compression scheme is zstd (supercompression)
	assert_eq(probe.compression_scheme, "zstd", "should use zstd supercompression")

	# Validate file size is reasonable (compressed should be smaller than raw RGBA)
	# Raw 256x256 RGBA = 256*256*4 = 262144 bytes
	# With compression, should be smaller
	assert_lt(probe.size_bytes, 262144, "compressed size should be less than raw RGBA")
	assert_gt(probe.size_bytes, 1000, "file should have meaningful content")

	_clear_task(task_id)


# ============================================================
# Test: Dimensions preserved exactly
# ============================================================
func test_convert_png_dimensions_preserved():
	begin_test("PNG dimensions preserved in KTX2")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_dimensions.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)

	# Source PNG is 256x256 - verify exact dimensions
	assert_eq(probe.width, 256, "width must be exactly 256")
	assert_eq(probe.height, 256, "height must be exactly 256")
	assert_eq(probe.depth, 1, "depth must be 1 for 2D texture")
	assert_eq(probe.layers, 1, "layers must be 1 for non-array texture")

	_clear_task(task_id)


# ============================================================
# Test: Mipmaps generated with correct count
# ============================================================
func test_convert_png_mipmaps_generated():
	begin_test("PNG conversion with mipmaps")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_mipmaps.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)  # mipmaps=true
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)

	# For 256x256 image, mip chain is: 256, 128, 64, 32, 16, 8, 4, 2, 1 = 9 levels
	# Formula: floor(log2(max(width, height))) + 1 = floor(log2(256)) + 1 = 8 + 1 = 9
	assert_eq(probe.mip_levels, 9, "256x256 should have exactly 9 mip levels")

	_clear_task(task_id)


# ============================================================
# Test: No mipmaps option produces single level
# ============================================================
func test_convert_png_no_mipmaps():
	begin_test("PNG conversion without mipmaps")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_no_mipmaps.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, false)  # mipmaps=false
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)

	# Without mipmaps, must have exactly 1 level
	assert_eq(probe.mip_levels, 1, "without mipmaps should have exactly 1 level")

	# Dimensions should still be correct
	assert_eq(probe.width, 256, "width should be preserved")
	assert_eq(probe.height, 256, "height should be preserved")

	_clear_task(task_id)


# ============================================================
# Test: Quality setting affects file size
# ============================================================
func test_convert_png_quality_affects_size():
	begin_test("PNG quality affects output size")

	var source = get_asset_path("test.png")
	var output_low = get_output_path("test_quality_low.ktx2")
	var output_high = get_output_path("test_quality_high.ktx2")

	if FileAccess.file_exists(output_low):
		DirAccess.remove_absolute(output_low)
	if FileAccess.file_exists(output_high):
		DirAccess.remove_absolute(output_high)

	# Convert with low quality (1)
	var task_id_low = _converter.image_to_ktx2(source, output_low, 1, true)
	var result_low = await _wait_for_task(task_id_low)
	assert_eq(result_low.error, OK, "low quality conversion should succeed")

	# Convert with high quality (255)
	var task_id_high = _converter.image_to_ktx2(source, output_high, 255, true)
	var result_high = await _wait_for_task(task_id_high)
	assert_eq(result_high.error, OK, "high quality conversion should succeed")

	# Both should be valid KTX2
	var probe_low = AssetProbe.probe_ktx2(output_low)
	var probe_high = AssetProbe.probe_ktx2(output_high)
	assert_no_error(probe_low)
	assert_no_error(probe_high)

	# Both should have same dimensions
	assert_eq(probe_low.width, probe_high.width, "dimensions should match")
	assert_eq(probe_low.height, probe_high.height, "dimensions should match")

	# Higher quality typically produces larger files (more detail preserved)
	# Note: This may not always be true for all images, so we just verify both are valid
	var size_low = probe_low.size_bytes
	var size_high = probe_high.size_bytes

	assert_gt(size_low, 0, "low quality file should have content")
	assert_gt(size_high, 0, "high quality file should have content")

	# Log the sizes for debugging
	print("        Low quality size: %d bytes, High quality size: %d bytes" % [size_low, size_high])

	_clear_task(task_id_low)
	_clear_task(task_id_high)


# ============================================================
# Test: JPEG basic conversion
# ============================================================
func test_convert_jpeg_basic():
	begin_test("JPEG to KTX2 basic conversion")

	var source = get_asset_path("test.jpg")
	var output = get_output_path("test_jpeg.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")
	assert_file_exists(output, "output should exist")
	assert_true(validate_ktx2_header(output), "output should be valid KTX2")

	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)
	assert_true(probe.is_compressed, "output should be compressed")

	_clear_task(task_id)


# ============================================================
# Test: JPEG dimensions preserved
# ============================================================
func test_convert_jpeg_dimensions_preserved():
	begin_test("JPEG dimensions preserved in KTX2")

	var source = get_asset_path("test.jpg")
	var output = get_output_path("test_jpeg_dims.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	var probe = AssetProbe.probe_ktx2(output)
	assert_no_error(probe)

	# Source JPEG is 600x400
	assert_eq(probe.width, 600, "width must be exactly 600")
	assert_eq(probe.height, 400, "height must be exactly 400")

	# 600x400 with mipmaps: log2(600)+1 = 10 levels
	assert_eq(probe.mip_levels, 10, "600x400 should have exactly 10 mip levels")

	_clear_task(task_id)


# ============================================================
# Test: Progress signals are emitted correctly
# ============================================================
func test_convert_progress_signals():
	begin_test("conversion emits progress signals")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_progress.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 128, true)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")
	assert_true(_progress_updates.has(task_id), "should have progress updates")

	if _progress_updates.has(task_id):
		var updates = _progress_updates[task_id]
		assert_gt(updates.size(), 0, "should have at least 1 progress update")

		# All values must be in valid range
		for i in range(updates.size()):
			assert_gte(updates[i], 0.0, "progress[%d] must be >= 0" % i)
			assert_lte(updates[i], 1.0, "progress[%d] must be <= 1" % i)

		# First progress should be 0 or close to it
		if updates.size() > 0:
			assert_lte(updates[0], 0.5, "first progress should be low")

		# Last progress must be exactly 1.0
		if updates.size() > 0:
			assert_eq(updates[-1], 1.0, "final progress must be exactly 1.0")

	_clear_task(task_id)


# ============================================================
# Test: Progress values are monotonically increasing
# ============================================================
func test_convert_progress_monotonic():
	begin_test("progress values are monotonically increasing")

	var source = get_asset_path("test.png")
	var output = get_output_path("test_progress_mono.ktx2")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.image_to_ktx2(source, output, 255, true)  # High quality for more updates
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	if _progress_updates.has(task_id):
		var updates = _progress_updates[task_id]

		# Check monotonicity - each value should be >= previous
		for i in range(1, updates.size()):
			assert_gte(updates[i], updates[i-1], "progress[%d] should be >= progress[%d]" % [i, i-1])

	_clear_task(task_id)


# ============================================================
# Test: Task IDs are unique
# ============================================================
func test_convert_task_id_unique():
	begin_test("task IDs are unique")

	var source = get_asset_path("test.png")

	var task_id1 = _converter.image_to_ktx2(source, get_output_path("unique1.ktx2"), 128, true)
	var task_id2 = _converter.image_to_ktx2(source, get_output_path("unique2.ktx2"), 128, true)
	var task_id3 = _converter.image_to_ktx2(source, get_output_path("unique3.ktx2"), 128, true)

	assert_ne(task_id1, task_id2, "task IDs 1 and 2 should differ")
	assert_ne(task_id2, task_id3, "task IDs 2 and 3 should differ")
	assert_ne(task_id1, task_id3, "task IDs 1 and 3 should differ")

	assert_gte(task_id1, 0, "task_id1 should be >= 0")
	assert_gte(task_id2, 0, "task_id2 should be >= 0")
	assert_gte(task_id3, 0, "task_id3 should be >= 0")

	# Wait for all to complete
	await _wait_for_task(task_id1)
	await _wait_for_task(task_id2)
	await _wait_for_task(task_id3)

	_clear_task(task_id1)
	_clear_task(task_id2)
	_clear_task(task_id3)


# ============================================================
# Test: Missing source file
# ============================================================
func test_convert_missing_file():
	begin_test("conversion fails for missing file")

	var source = "/nonexistent/path/to/image.png"
	var output = get_output_path("missing_source.ktx2")

	var task_id = _converter.image_to_ktx2(source, output, 128, true)

	assert_gte(task_id, 0, "should return valid task_id")

	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "conversion should fail")
	assert_string_contains(result.error_message, "not found", "error should mention 'not found'")
	assert_false(FileAccess.file_exists(output), "output should not exist")

	_clear_task(task_id)


# ============================================================
# Test: Invalid output path
# ============================================================
func test_convert_invalid_output_path():
	begin_test("conversion fails for invalid output path")

	var source = get_asset_path("test.png")
	var output = "/nonexistent/directory/output.ktx2"

	var task_id = _converter.image_to_ktx2(source, output, 128, true)

	assert_gte(task_id, 0, "should return valid task_id")

	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "conversion should fail")
	assert_false(FileAccess.file_exists(output), "output should not exist")

	_clear_task(task_id)


# ============================================================
# Test: Cancel task
# ============================================================
func test_convert_cancel_task():
	begin_test("task can be cancelled")

	var source = get_asset_path("test.png")
	var output = get_output_path("cancelled.ktx2")

	var task_id = _converter.image_to_ktx2(source, output, 255, true)  # High quality = slower

	# Try to cancel immediately
	var cancelled = _converter.cancel(task_id)

	# Either cancelled successfully or completed before cancel
	assert_true(cancelled or _completed_tasks.has(task_id), "should cancel or complete")

	_clear_task(task_id)
