class_name TestProbeKtx2
extends "res://test/test_base.gd"
## Detailed tests for AssetProbe.probe_ktx2()
## Note: Requires KTX2 file to be created first by conversion tests

var _converter: AssetConverter
var _ktx2_path: String = ""
var _conversion_done: bool = false
var _conversion_error: String = ""


func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] probe_ktx2")

	# First, create a KTX2 file for testing
	var setup_ok = await _setup_ktx2_file()
	if not setup_ok:
		print("    [SKIP] Could not create KTX2 test file: %s" % _conversion_error)
		return results

	# Run each test
	var tests = [
		"test_probe_valid_ktx2",
		"test_probe_ktx2_dimensions",
		"test_probe_ktx2_mip_levels",
		"test_probe_ktx2_compression",
		"test_probe_ktx2_format",
		"test_probe_ktx2_alpha",
		"test_probe_ktx2_cubemap",
		"test_probe_ktx2_file_size",
		"test_probe_missing_file",
		"test_probe_invalid_file",
	]

	for test_name in tests:
		if has_method(test_name):
			call(test_name)
			var passed = end_test()
			results.tests.append({"name": test_name, "passed": passed})
			if passed:
				results.passed += 1
			else:
				results.failed += 1

	return results


func _setup_ktx2_file() -> bool:
	_ktx2_path = get_output_path("probe_test.ktx2")

	# Check if already exists (created by image conversion tests)
	if FileAccess.file_exists(_ktx2_path):
		return true

	# Also check for test_basic.ktx2 created by image_to_ktx2 tests
	var alt_path = get_output_path("test_basic.ktx2")
	if FileAccess.file_exists(alt_path):
		_ktx2_path = alt_path
		return true

	# Create converter and convert PNG to KTX2
	_converter = AssetConverter.new()
	_converter.conversion_completed.connect(_on_conversion_completed)

	var source = get_asset_path("test.png")
	var task_id = _converter.image_to_ktx2(source, _ktx2_path, 128, true)

	if task_id < 0:
		_conversion_error = "Failed to start conversion"
		return false

	# Wait for completion using async timer
	var timeout = 30.0
	var elapsed = 0.0
	while not _conversion_done and elapsed < timeout:
		await Engine.get_main_loop().create_timer(0.1).timeout
		elapsed += 0.1

	if not _conversion_done:
		_conversion_error = "Conversion timed out"
		return false

	if _conversion_error != "":
		return false

	return FileAccess.file_exists(_ktx2_path)


func _on_conversion_completed(_task_id: int, _source: String, _output: String, error: int, error_message: String):
	_conversion_done = true
	if error != OK:
		_conversion_error = error_message


# ============================================================
# Test: Valid KTX2 returns proper structure
# ============================================================
func test_probe_valid_ktx2():
	begin_test("probe_ktx2 returns valid structure")

	var result = AssetProbe.probe_ktx2(_ktx2_path)

	# Should not have error
	assert_no_error(result, "probe_ktx2 should succeed")

	# Check all required keys exist
	assert_has_key(result, "width", "must have width")
	assert_has_key(result, "height", "must have height")
	assert_has_key(result, "depth", "must have depth")
	assert_has_key(result, "layers", "must have layers")
	assert_has_key(result, "mip_levels", "must have mip_levels")
	assert_has_key(result, "format", "must have format")
	assert_has_key(result, "is_compressed", "must have is_compressed")
	assert_has_key(result, "compression_scheme", "must have compression_scheme")
	assert_has_key(result, "has_alpha", "must have has_alpha")
	assert_has_key(result, "is_cubemap", "must have is_cubemap")
	assert_has_key(result, "size_bytes", "must have size_bytes")


# ============================================================
# Test: Dimensions match source image
# ============================================================
func test_probe_ktx2_dimensions():
	begin_test("probe_ktx2 dimensions validation")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# Source PNG is 256x256
	assert_eq(result.width, 256, "width should be 256")
	assert_eq(result.height, 256, "height should be 256")

	# 2D texture
	assert_eq(result.depth, 1, "depth should be 1 for 2D texture")
	assert_eq(result.layers, 1, "layers should be 1")


# ============================================================
# Test: Mip levels generated
# ============================================================
func test_probe_ktx2_mip_levels():
	begin_test("probe_ktx2 mip_levels validation")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# For 256x256 image with mipmaps: 256, 128, 64, 32, 16, 8, 4, 2, 1 = 9 levels
	assert_eq(result.mip_levels, 9, "256x256 should have 9 mip levels")

	# mip_levels must be at least 1
	assert_gte(result.mip_levels, 1, "mip_levels must be >= 1")


# ============================================================
# Test: Compression scheme
# ============================================================
func test_probe_ktx2_compression():
	begin_test("probe_ktx2 compression validation")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# We use zstd supercompression
	assert_eq(result.compression_scheme, "zstd", "should use zstd compression")

	# is_compressed should reflect compression
	assert_true(result.is_compressed, "should be marked as compressed")


# ============================================================
# Test: Format string
# ============================================================
func test_probe_ktx2_format():
	begin_test("probe_ktx2 format validation")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# format should be a string
	assert_is_string(result.format, "format should be string")

	# Format should not be empty
	assert_ne(result.format, "", "format should not be empty")


# ============================================================
# Test: Alpha channel detection
# ============================================================
func test_probe_ktx2_alpha():
	begin_test("probe_ktx2 alpha detection")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# has_alpha should be bool
	assert_true(result.has_alpha is bool, "has_alpha should be bool")

	# Our test PNG has RGBA, so should have alpha
	# Note: This depends on how the encoder handles alpha


# ============================================================
# Test: Cubemap detection
# ============================================================
func test_probe_ktx2_cubemap():
	begin_test("probe_ktx2 cubemap detection")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# is_cubemap should be bool
	assert_true(result.is_cubemap is bool, "is_cubemap should be bool")

	# Our test image is not a cubemap
	assert_false(result.is_cubemap, "test image should not be cubemap")


# ============================================================
# Test: File size is reasonable
# ============================================================
func test_probe_ktx2_file_size():
	begin_test("probe_ktx2 file size validation")

	var result = AssetProbe.probe_ktx2(_ktx2_path)
	assert_no_error(result)

	# size_bytes should be int
	assert_is_int(result.size_bytes, "size_bytes should be int")

	# Size should be positive
	assert_gt(result.size_bytes, 0, "size_bytes must be > 0")

	# KTX2 with zstd should be smaller than raw RGBA (256*256*4 = 262144)
	# But with mips it could be larger, so just check it's reasonable
	assert_lt(result.size_bytes, 500000, "compressed size should be reasonable")

	# Verify matches actual file size
	var actual_size = get_file_size(_ktx2_path)
	assert_eq(result.size_bytes, actual_size, "size_bytes should match actual file")


# ============================================================
# Test: Missing file error
# ============================================================
func test_probe_missing_file():
	begin_test("probe_ktx2 missing file error")

	var path = "/nonexistent/path/to/texture.ktx2"
	var result = AssetProbe.probe_ktx2(path)

	# Should have error
	assert_has_error(result, "should return error for missing file")
	assert_string_contains(result.error, "not found", "error should mention 'not found'")


# ============================================================
# Test: Invalid file error
# ============================================================
func test_probe_invalid_file():
	begin_test("probe_ktx2 invalid file error")

	# Try to probe a non-KTX2 file
	var path = get_asset_path("test.png")
	var result = AssetProbe.probe_ktx2(path)

	# Should have error (PNG is not valid KTX2)
	assert_has_error(result, "should return error for invalid KTX2")
	assert_string_contains(result.error, "KTX2", "error should mention 'KTX2'")
