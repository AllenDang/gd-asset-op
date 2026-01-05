class_name TestConvertAudio
extends "res://test/test_base.gd"
## Detailed tests for AssetConverter.audio_to_mp3() and normalize_audio()

var _converter: AssetConverter
var _completed_tasks: Dictionary = {}
var _progress_updates: Dictionary = {}


func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] audio conversion")

	# Initialize converter
	_converter = AssetConverter.new()
	_converter.conversion_started.connect(_on_started)
	_converter.conversion_progress.connect(_on_progress)
	_converter.conversion_completed.connect(_on_completed)

	var tests = [
		# audio_to_mp3 tests
		"test_wav_to_mp3_basic",
		"test_wav_to_mp3_validates_output",
		"test_wav_to_mp3_duration_preserved",
		"test_wav_to_mp3_bitrate_affects_size",
		"test_wav_to_mp3_progress_signals",
		"test_wav_to_mp3_missing_file",
		"test_wav_to_mp3_wrong_format",
		# normalize_audio tests
		"test_normalize_basic",
		"test_normalize_validates_output",
		"test_normalize_duration_preserved",
		"test_normalize_missing_file",
		"test_normalize_wrong_format",
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
# audio_to_mp3 Tests
# ============================================================

func test_wav_to_mp3_basic():
	begin_test("WAV to MP3 basic conversion")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_basic.mp3")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.audio_to_mp3(source, output, 192)

	assert_gte(task_id, 0, "task_id should be >= 0")

	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")
	assert_file_exists(output, "output file should exist")

	# Validate MP3 header
	assert_true(validate_mp3_header(output), "output should have valid MP3 header")

	# File should have meaningful size
	var file_size = get_file_size(output)
	assert_gt(file_size, 1000, "MP3 file should have significant content")

	_clear_task(task_id)


func test_wav_to_mp3_validates_output():
	begin_test("WAV to MP3 produces valid MP3")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_validate.mp3")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.audio_to_mp3(source, output, 192)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Read and validate MP3 header bytes
	var header = read_file_bytes(output, 10)
	assert_gt(header.size(), 0, "file should have content")

	# Check for MP3 frame sync or ID3 tag
	var is_mp3_sync = (header[0] == 0xFF and (header[1] & 0xE0) == 0xE0)
	var is_id3 = (header[0] == 0x49 and header[1] == 0x44 and header[2] == 0x33)
	assert_true(is_mp3_sync or is_id3, "should have MP3 sync or ID3 header")

	# Validate file size is reasonable for 3s at 192kbps
	# 3 seconds * 192 kbps / 8 = ~72 KB
	var file_size = get_file_size(output)
	assert_between(file_size, 50000, 100000, "file size should be ~72KB for 3s at 192kbps")

	_clear_task(task_id)


func test_wav_to_mp3_duration_preserved():
	begin_test("WAV to MP3 preserves duration")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_duration.mp3")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.audio_to_mp3(source, output, 192)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	# Copy to assets dir temporarily to probe (probe only works on res:// paths)
	var probe_path = get_asset_path("test_duration_probe.mp3")
	DirAccess.copy_absolute(output, probe_path)

	var probe = AssetProbe.probe_audio(probe_path, false)

	# Clean up
	DirAccess.remove_absolute(probe_path)

	assert_no_error(probe, "probe should succeed")

	# Source WAV is ~3 seconds - verify duration matches
	assert_between(probe.duration, 2.8, 3.2, "duration should be ~3 seconds")

	# Verify format is correct
	assert_eq(probe.format, "mp3", "format should be mp3")

	# Verify sample rate is preserved (44100 Hz)
	assert_eq(probe.sample_rate, 44100, "sample rate should be 44100 Hz")

	# Verify channel count is preserved (mono)
	assert_eq(probe.channels, 1, "channels should be 1 (mono)")

	_clear_task(task_id)


func test_wav_to_mp3_bitrate_affects_size():
	begin_test("WAV to MP3 bitrate affects file size")

	var source = get_asset_path("test.wav")
	var output_low = get_output_path("test_bitrate_low.mp3")
	var output_high = get_output_path("test_bitrate_high.mp3")

	if FileAccess.file_exists(output_low):
		DirAccess.remove_absolute(output_low)
	if FileAccess.file_exists(output_high):
		DirAccess.remove_absolute(output_high)

	# Convert at 128 kbps
	var task_id_low = _converter.audio_to_mp3(source, output_low, 128)
	var result_low = await _wait_for_task(task_id_low)
	assert_eq(result_low.error, OK, "128kbps conversion should succeed")

	# Convert at 320 kbps
	var task_id_high = _converter.audio_to_mp3(source, output_high, 320)
	var result_high = await _wait_for_task(task_id_high)
	assert_eq(result_high.error, OK, "320kbps conversion should succeed")

	var size_low = get_file_size(output_low)
	var size_high = get_file_size(output_high)

	# 3s at 128kbps = ~48KB, 3s at 320kbps = ~120KB
	assert_between(size_low, 35000, 70000, "128kbps file should be ~48KB")
	assert_between(size_high, 100000, 160000, "320kbps file should be ~120KB")

	# Higher bitrate should produce larger file
	assert_gt(size_high, size_low, "320kbps should be larger than 128kbps")

	# Size ratio should roughly match bitrate ratio (320/128 = 2.5)
	var ratio = float(size_high) / float(size_low)
	assert_between(ratio, 1.5, 3.5, "size ratio should reflect bitrate ratio")

	print("        128kbps: %d bytes, 320kbps: %d bytes, ratio: %.2f" % [size_low, size_high, ratio])

	_clear_task(task_id_low)
	_clear_task(task_id_high)


func test_wav_to_mp3_progress_signals():
	begin_test("WAV to MP3 emits progress signals")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_progress.mp3")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.audio_to_mp3(source, output, 192)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "conversion should succeed")

	assert_true(_progress_updates.has(task_id), "should have progress updates")

	if _progress_updates.has(task_id):
		var updates = _progress_updates[task_id]
		assert_gt(updates.size(), 0, "should have progress updates")

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


func test_wav_to_mp3_missing_file():
	begin_test("WAV to MP3 fails for missing file")

	var source = "/nonexistent/audio.wav"
	var output = get_output_path("missing.mp3")

	var task_id = _converter.audio_to_mp3(source, output, 192)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail")
	assert_string_contains(result.error_message, "not found", "error should mention 'not found'")
	assert_false(FileAccess.file_exists(output), "output should not be created")

	_clear_task(task_id)


func test_wav_to_mp3_wrong_format():
	begin_test("WAV to MP3 fails for non-WAV input")

	var source = get_asset_path("test.mp3")  # MP3 input, not WAV
	var output = get_output_path("wrong_format.mp3")

	var task_id = _converter.audio_to_mp3(source, output, 192)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail for non-WAV input")
	assert_string_contains(result.error_message, "WAV", "error should mention WAV")

	_clear_task(task_id)


# ============================================================
# normalize_audio Tests
# ============================================================

func test_normalize_basic():
	begin_test("normalize_audio basic conversion")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_norm_basic.wav")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.normalize_audio(source, output, -14.0, -1.0)

	assert_gte(task_id, 0, "task_id should be >= 0")

	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "normalization should succeed")
	assert_file_exists(output, "output file should exist")

	# Validate WAV header
	assert_true(validate_wav_header(output), "output should have valid WAV header")

	_clear_task(task_id)


func test_normalize_validates_output():
	begin_test("normalize_audio produces valid WAV")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_norm_validate.wav")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.normalize_audio(source, output, -14.0, -1.0)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "normalization should succeed")

	# Validate WAV header bytes: RIFF....WAVE
	var header = read_file_bytes(output, 12)
	assert_eq(header[0], 0x52, "WAV byte 0 should be 'R'")
	assert_eq(header[1], 0x49, "WAV byte 1 should be 'I'")
	assert_eq(header[2], 0x46, "WAV byte 2 should be 'F'")
	assert_eq(header[3], 0x46, "WAV byte 3 should be 'F'")
	assert_eq(header[8], 0x57, "WAV byte 8 should be 'W'")
	assert_eq(header[9], 0x41, "WAV byte 9 should be 'A'")
	assert_eq(header[10], 0x56, "WAV byte 10 should be 'V'")
	assert_eq(header[11], 0x45, "WAV byte 11 should be 'E'")

	# Output size should be similar to input (same duration, same format)
	var input_size = get_file_size(source)
	var output_size = get_file_size(output)

	# Should be within 10% (header differences only)
	var ratio = float(output_size) / float(input_size)
	assert_between(ratio, 0.9, 1.1, "output size should be similar to input")

	_clear_task(task_id)


func test_normalize_duration_preserved():
	begin_test("normalize_audio preserves duration")

	var source = get_asset_path("test.wav")
	var output = get_output_path("test_norm_duration.wav")

	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)

	var task_id = _converter.normalize_audio(source, output, -14.0, -1.0)
	var result = await _wait_for_task(task_id)

	assert_eq(result.error, OK, "normalization should succeed")

	# For uncompressed WAV, file size directly indicates duration
	# Same format = same size = same duration
	var input_size = get_file_size(source)
	var output_size = get_file_size(output)

	# WAV with same format should have same size (±512 bytes for header/format variations)
	var size_diff = abs(output_size - input_size)
	assert_lt(size_diff, 512, "size difference should be minimal (same duration)")

	_clear_task(task_id)


func test_normalize_missing_file():
	begin_test("normalize_audio fails for missing file")

	var source = "/nonexistent/audio.wav"
	var output = get_output_path("norm_missing.wav")

	var task_id = _converter.normalize_audio(source, output, -14.0, -1.0)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail")
	assert_string_contains(result.error_message, "not found", "error should mention 'not found'")
	assert_false(FileAccess.file_exists(output), "output should not be created")

	_clear_task(task_id)


func test_normalize_wrong_format():
	begin_test("normalize_audio fails for non-WAV input")

	var source = get_asset_path("test.mp3")  # MP3 input, not WAV
	var output = get_output_path("norm_wrong.wav")

	var task_id = _converter.normalize_audio(source, output, -14.0, -1.0)
	var result = await _wait_for_task(task_id)

	assert_ne(result.error, OK, "should fail for non-WAV input")
	assert_string_contains(result.error_message, "WAV", "error should mention WAV")

	_clear_task(task_id)
