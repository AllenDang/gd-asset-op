class_name TestBase
extends RefCounted
## Base class for test modules with assertion helpers

signal test_completed(test_name: String, passed: bool, message: String)

var _test_name: String = ""
var _assertions_passed: int = 0
var _assertions_failed: int = 0
var _failure_messages: Array[String] = []

const TEST_ASSETS_DIR = "res://test/assets"
const TEST_OUTPUT_DIR = "res://test/output"


func get_asset_path(filename: String) -> String:
	return ProjectSettings.globalize_path(TEST_ASSETS_DIR + "/" + filename)


func get_output_path(filename: String) -> String:
	return ProjectSettings.globalize_path(TEST_OUTPUT_DIR + "/" + filename)


func begin_test(name: String) -> void:
	_test_name = name
	_assertions_passed = 0
	_assertions_failed = 0
	_failure_messages.clear()
	print("    [TEST] %s" % name)


func end_test() -> bool:
	var passed = _assertions_failed == 0
	if passed:
		print("      [PASS] %d assertions passed" % _assertions_passed)
	else:
		print("      [FAIL] %d passed, %d failed" % [_assertions_passed, _assertions_failed])
		for msg in _failure_messages:
			print("        - %s" % msg)
	test_completed.emit(_test_name, passed, "\n".join(_failure_messages))
	return passed


# ============================================================
# Assertion Methods
# ============================================================

func assert_true(condition: bool, message: String = "") -> bool:
	if condition:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected true" + (": " + message if message else "")
		_failure_messages.append(msg)
		return false


func assert_false(condition: bool, message: String = "") -> bool:
	if not condition:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected false" + (": " + message if message else "")
		_failure_messages.append(msg)
		return false


func assert_eq(actual, expected, message: String = "") -> bool:
	if actual == expected:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected '%s' but got '%s'" % [str(expected), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_ne(actual, not_expected, message: String = "") -> bool:
	if actual != not_expected:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected not '%s'" % str(not_expected)
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_gt(actual: float, minimum: float, message: String = "") -> bool:
	if actual > minimum:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected > %s but got %s" % [str(minimum), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_gte(actual: float, minimum: float, message: String = "") -> bool:
	if actual >= minimum:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected >= %s but got %s" % [str(minimum), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_lt(actual: float, maximum: float, message: String = "") -> bool:
	if actual < maximum:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected < %s but got %s" % [str(maximum), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_lte(actual: float, maximum: float, message: String = "") -> bool:
	if actual <= maximum:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected <= %s but got %s" % [str(maximum), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_between(actual: float, min_val: float, max_val: float, message: String = "") -> bool:
	if actual >= min_val and actual <= max_val:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected between %s and %s but got %s" % [str(min_val), str(max_val), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_approx(actual: float, expected: float, tolerance: float = 0.01, message: String = "") -> bool:
	if abs(actual - expected) <= tolerance:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected ~%s (±%s) but got %s" % [str(expected), str(tolerance), str(actual)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_has_key(dict: Dictionary, key: String, message: String = "") -> bool:
	if dict.has(key):
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Dictionary missing key '%s'" % key
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_no_error(dict: Dictionary, message: String = "") -> bool:
	if not dict.has("error"):
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Unexpected error: %s" % str(dict.get("error", ""))
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_has_error(dict: Dictionary, message: String = "") -> bool:
	if dict.has("error"):
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected error but none found"
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_file_exists(path: String, message: String = "") -> bool:
	if FileAccess.file_exists(path):
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "File not found: %s" % path
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_file_size_gt(path: String, min_size: int, message: String = "") -> bool:
	if not FileAccess.file_exists(path):
		_assertions_failed += 1
		_failure_messages.append("File not found: %s" % path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	var size = file.get_length()
	file.close()

	if size > min_size:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "File size %d <= %d" % [size, min_size]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_type(value, expected_type: int, message: String = "") -> bool:
	if typeof(value) == expected_type:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected type %d but got %d" % [expected_type, typeof(value)]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_is_array(value, message: String = "") -> bool:
	return assert_type(value, TYPE_ARRAY, message)


func assert_is_dict(value, message: String = "") -> bool:
	return assert_type(value, TYPE_DICTIONARY, message)


func assert_is_string(value, message: String = "") -> bool:
	return assert_type(value, TYPE_STRING, message)


func assert_is_int(value, message: String = "") -> bool:
	return assert_type(value, TYPE_INT, message)


func assert_is_float(value, message: String = "") -> bool:
	return assert_type(value, TYPE_FLOAT, message)


func assert_array_size(arr: Array, expected_size: int, message: String = "") -> bool:
	if arr.size() == expected_size:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected array size %d but got %d" % [expected_size, arr.size()]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_array_not_empty(arr: Array, message: String = "") -> bool:
	if arr.size() > 0:
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "Expected non-empty array"
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


func assert_string_contains(haystack: String, needle: String, message: String = "") -> bool:
	if haystack.contains(needle):
		_assertions_passed += 1
		return true
	else:
		_assertions_failed += 1
		var msg = "String '%s' does not contain '%s'" % [haystack, needle]
		if message:
			msg += " (%s)" % message
		_failure_messages.append(msg)
		return false


# ============================================================
# File Validation Helpers
# ============================================================

func read_file_bytes(path: String, count: int = -1) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file = FileAccess.open(path, FileAccess.READ)
	if count < 0:
		return file.get_buffer(file.get_length())
	return file.get_buffer(count)


func validate_png_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 8)
	if bytes.size() < 8:
		return false
	# PNG magic: 89 50 4E 47 0D 0A 1A 0A
	return bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47


func validate_jpeg_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 3)
	if bytes.size() < 3:
		return false
	# JPEG magic: FF D8 FF
	return bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF


func validate_ktx2_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 12)
	if bytes.size() < 12:
		return false
	# KTX2 magic: AB 4B 54 58 20 32 30 BB 0D 0A 1A 0A
	return (bytes[0] == 0xAB and bytes[1] == 0x4B and bytes[2] == 0x54 and bytes[3] == 0x58 and
			bytes[4] == 0x20 and bytes[5] == 0x32 and bytes[6] == 0x30 and bytes[7] == 0xBB)


func validate_glb_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 12)
	if bytes.size() < 12:
		return false
	# GLB magic: 67 6C 54 46 (glTF in little-endian)
	return bytes[0] == 0x67 and bytes[1] == 0x6C and bytes[2] == 0x54 and bytes[3] == 0x46


func validate_wav_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 12)
	if bytes.size() < 12:
		return false
	# WAV: RIFF....WAVE
	return (bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46 and
			bytes[8] == 0x57 and bytes[9] == 0x41 and bytes[10] == 0x56 and bytes[11] == 0x45)


func validate_mp3_header(path: String) -> bool:
	var bytes = read_file_bytes(path, 3)
	if bytes.size() < 3:
		return false
	# MP3: FF FB or FF FA or ID3
	if bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0:
		return true
	# ID3 tag
	if bytes[0] == 0x49 and bytes[1] == 0x44 and bytes[2] == 0x33:
		return true
	return false


func get_file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file = FileAccess.open(path, FileAccess.READ)
	var size = file.get_length()
	file.close()
	return size
