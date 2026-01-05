class_name TestProbeAudio
extends "res://test/test_base.gd"
## Detailed tests for AssetProbe.probe_audio()
## Note: Only MP3 format is supported

func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] probe_audio")

	var tests = [
		"test_probe_valid_mp3",
		"test_probe_audio_duration",
		"test_probe_audio_sample_rate",
		"test_probe_audio_channels",
		"test_probe_audio_bit_depth",
		"test_probe_audio_format",
		"test_probe_audio_bitrate",
		"test_probe_audio_file_size",
		"test_probe_audio_with_volume_analysis",
		"test_probe_audio_peak_db",
		"test_probe_audio_rms_db",
		"test_probe_audio_lufs",
		"test_probe_wav_rejected",
		"test_probe_missing_file",
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


# ============================================================
# Test: Valid MP3 returns proper structure
# ============================================================
func test_probe_valid_mp3():
	begin_test("probe_audio returns valid structure")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	# Should not have error
	assert_no_error(result, "probe_audio should succeed")

	# Check all required keys exist
	assert_has_key(result, "duration", "must have duration")
	assert_has_key(result, "sample_rate", "must have sample_rate")
	assert_has_key(result, "channels", "must have channels")
	assert_has_key(result, "bit_depth", "must have bit_depth")
	assert_has_key(result, "format", "must have format")
	assert_has_key(result, "bitrate", "must have bitrate")
	assert_has_key(result, "size_bytes", "must have size_bytes")


# ============================================================
# Test: Duration is correct
# ============================================================
func test_probe_audio_duration():
	begin_test("probe_audio duration validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# duration should be float
	assert_is_float(result.duration, "duration should be float")

	# Test audio is ~3 seconds (BBC sound effect)
	assert_between(result.duration, 2.9, 3.1, "test.mp3 should be ~3 seconds")

	# Duration must be positive
	assert_gt(result.duration, 0.0, "duration must be > 0")


# ============================================================
# Test: Sample rate is correct
# ============================================================
func test_probe_audio_sample_rate():
	begin_test("probe_audio sample_rate validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# sample_rate should be int
	assert_is_int(result.sample_rate, "sample_rate should be int")

	# Test audio is 44100 Hz
	assert_eq(result.sample_rate, 44100, "test.mp3 should be 44100 Hz")

	# Sample rate must be positive
	assert_gt(result.sample_rate, 0, "sample_rate must be > 0")

	# Common sample rates: 8000, 11025, 22050, 44100, 48000, 96000
	var valid_rates = [8000, 11025, 22050, 32000, 44100, 48000, 88200, 96000]
	assert_true(result.sample_rate in valid_rates, "sample_rate should be standard")


# ============================================================
# Test: Channels is correct
# ============================================================
func test_probe_audio_channels():
	begin_test("probe_audio channels validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# channels should be int
	assert_is_int(result.channels, "channels should be int")

	# Test audio is mono
	assert_eq(result.channels, 1, "test.mp3 should be mono (1 channel)")

	# Channels must be 1 (mono) or 2 (stereo)
	assert_true(result.channels in [1, 2], "channels should be 1 or 2")


# ============================================================
# Test: Bit depth
# ============================================================
func test_probe_audio_bit_depth():
	begin_test("probe_audio bit_depth validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# bit_depth should be int
	assert_is_int(result.bit_depth, "bit_depth should be int")

	# MP3 decoded as 16-bit
	assert_eq(result.bit_depth, 16, "MP3 decoded as 16-bit")


# ============================================================
# Test: Format string
# ============================================================
func test_probe_audio_format():
	begin_test("probe_audio format validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# format should be string
	assert_is_string(result.format, "format should be string")

	# Should be "mp3"
	assert_eq(result.format, "mp3", "format should be 'mp3'")


# ============================================================
# Test: Bitrate
# ============================================================
func test_probe_audio_bitrate():
	begin_test("probe_audio bitrate validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# bitrate should be int
	assert_is_int(result.bitrate, "bitrate should be int")

	# Test audio encoded at ~196 kbps (may vary slightly due to VBR)
	assert_between(result.bitrate, 180, 220, "bitrate should be ~196 kbps")

	# Bitrate must be positive
	assert_gt(result.bitrate, 0, "bitrate must be > 0")


# ============================================================
# Test: File size
# ============================================================
func test_probe_audio_file_size():
	begin_test("probe_audio file size validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, false)

	assert_no_error(result)

	# size_bytes should be int
	assert_is_int(result.size_bytes, "size_bytes should be int")

	# Size should be positive
	assert_gt(result.size_bytes, 0, "size_bytes must be > 0")

	# 3 seconds at ~196 kbps = ~73 KB
	assert_between(result.size_bytes, 60000, 90000, "file size should be ~73 KB")

	# Verify matches actual file size
	var actual_size = get_file_size(path)
	assert_eq(result.size_bytes, actual_size, "size_bytes should match actual file")


# ============================================================
# Test: Volume analysis enabled
# ============================================================
func test_probe_audio_with_volume_analysis():
	begin_test("probe_audio with volume analysis")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, true)

	assert_no_error(result)

	# Should have volume analysis keys
	assert_has_key(result, "peak_db", "must have peak_db when analyze_volume=true")
	assert_has_key(result, "rms_db", "must have rms_db when analyze_volume=true")
	assert_has_key(result, "lufs", "must have lufs when analyze_volume=true")


# ============================================================
# Test: Peak dB value
# ============================================================
func test_probe_audio_peak_db():
	begin_test("probe_audio peak_db validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, true)

	assert_no_error(result)

	# peak_db should be float
	assert_is_float(result.peak_db, "peak_db should be float")

	# Peak should be <= 0 dB (0 dB = full scale)
	assert_lte(result.peak_db, 0.0, "peak_db should be <= 0")

	# Peak should be > -100 dB (not silence)
	assert_gt(result.peak_db, -100.0, "peak_db should be > -100 dB")

	# Real world audio - peak typically between -20 and 0 dB
	assert_between(result.peak_db, -20.0, 0.0, "peak_db should be in reasonable range")


# ============================================================
# Test: RMS dB value
# ============================================================
func test_probe_audio_rms_db():
	begin_test("probe_audio rms_db validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, true)

	assert_no_error(result)

	# rms_db should be float
	assert_is_float(result.rms_db, "rms_db should be float")

	# RMS should be <= peak
	assert_lte(result.rms_db, result.peak_db + 0.1, "rms_db should be <= peak_db")

	# RMS should be > -100 dB
	assert_gt(result.rms_db, -100.0, "rms_db should be > -100 dB")

	# Real world audio - RMS typically lower than peak
	assert_between(result.rms_db, -40.0, -5.0, "rms_db should be in reasonable range")


# ============================================================
# Test: LUFS value
# ============================================================
func test_probe_audio_lufs():
	begin_test("probe_audio lufs validation")

	var path = get_asset_path("test.mp3")
	var result = AssetProbe.probe_audio(path, true)

	assert_no_error(result)

	# lufs should be float
	assert_is_float(result.lufs, "lufs should be float")

	# LUFS should be <= 0
	assert_lte(result.lufs, 0.0, "lufs should be <= 0")

	# LUFS should be > -100
	assert_gt(result.lufs, -100.0, "lufs should be > -100")

	# LUFS is approximate RMS - 0.691, so should be close to RMS
	var expected_lufs = result.rms_db - 0.691
	assert_approx(result.lufs, expected_lufs, 1.0, "lufs should be ~rms_db - 0.691")


# ============================================================
# Test: WAV format rejected
# ============================================================
func test_probe_wav_rejected():
	begin_test("probe_audio rejects WAV format")

	var path = get_asset_path("test.wav")
	var result = AssetProbe.probe_audio(path, false)

	# Should have error (only MP3 supported)
	assert_has_error(result, "should reject WAV format")
	assert_string_contains(result.error, "MP3", "error should mention MP3")


# ============================================================
# Test: Missing file error
# ============================================================
func test_probe_missing_file():
	begin_test("probe_audio missing file error")

	var path = "/nonexistent/path/to/audio.mp3"
	var result = AssetProbe.probe_audio(path, false)

	# Should have error
	assert_has_error(result, "should return error for missing file")
	assert_string_contains(result.error, "not found", "error should mention 'not found'")
