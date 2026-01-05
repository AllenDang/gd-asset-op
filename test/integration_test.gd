extends SceneTree
## Integration tests for gd-asset-op GDExtension
##
## Run with: godot --headless --script test/integration_test.gd
##
## Before running, ensure test assets exist in test/assets/:
##   - test.png (64x64 RGBA PNG)
##   - test.jpg (8x8 JPEG)
##   - test.wav (2 second mono 44100Hz WAV)
##   - test.mp3 (2 second mono 44100Hz 192kbps MP3)
##   - test.glb (triangle mesh with 1 PNG texture)

# Preload test modules
const TestProbeGlb = preload("res://test/test_probe_glb.gd")
const TestProbeKtx2 = preload("res://test/test_probe_ktx2.gd")
const TestProbeAudio = preload("res://test/test_probe_audio.gd")
const TestConvertImage = preload("res://test/test_convert_image.gd")
const TestConvertAudio = preload("res://test/test_convert_audio.gd")
const TestConvertGlb = preload("res://test/test_convert_glb.gd")

const TEST_ASSETS_DIR = "res://test/assets"
const TEST_OUTPUT_DIR = "res://test/output"


func _init():
	print("\n" + "=".repeat(60))
	print("gd-asset-op Detailed Test Suite")
	print("=".repeat(60))

	# Clean output directory
	_clean_output_dir()

	# Check for test assets
	if not _check_test_assets():
		print("\nERROR: Missing test assets. Please add test files to test/assets/")
		print("Required files: test.png, test.jpg, test.wav, test.mp3, test.glb")
		quit(1)
		return

	# Run tests
	call_deferred("_run_all_tests")


func _run_all_tests():
	var total_passed := 0
	var total_failed := 0
	var module_results: Array[Dictionary] = []

	# Run probe modules (synchronous)
	print("\n" + "-".repeat(60))
	print("PROBE MODULES")
	print("-".repeat(60))

	var probe_glb = TestProbeGlb.new()
	var glb_result = probe_glb.run_all()
	module_results.append({"name": "probe_glb", "result": glb_result})
	total_passed += glb_result.passed
	total_failed += glb_result.failed

	var probe_audio = TestProbeAudio.new()
	var audio_result = probe_audio.run_all()
	module_results.append({"name": "probe_audio", "result": audio_result})
	total_passed += audio_result.passed
	total_failed += audio_result.failed

	# Run conversion modules (async)
	print("\n" + "-".repeat(60))
	print("CONVERSION MODULES")
	print("-".repeat(60))

	# image_to_ktx2 tests
	var convert_image = TestConvertImage.new()
	var img_result = await convert_image.run_all()
	module_results.append({"name": "image_to_ktx2", "result": img_result})
	total_passed += img_result.passed
	total_failed += img_result.failed

	# probe_ktx2 tests (depends on image conversion creating KTX2 files)
	var probe_ktx2 = TestProbeKtx2.new()
	var ktx2_result = await probe_ktx2.run_all()
	module_results.append({"name": "probe_ktx2", "result": ktx2_result})
	total_passed += ktx2_result.passed
	total_failed += ktx2_result.failed

	# audio conversion tests
	var convert_audio = TestConvertAudio.new()
	var audio_conv_result = await convert_audio.run_all()
	module_results.append({"name": "audio_conversion", "result": audio_conv_result})
	total_passed += audio_conv_result.passed
	total_failed += audio_conv_result.failed

	# GLB texture conversion tests
	var convert_glb = TestConvertGlb.new()
	var glb_conv_result = await convert_glb.run_all()
	module_results.append({"name": "glb_textures_to_ktx2", "result": glb_conv_result})
	total_passed += glb_conv_result.passed
	total_failed += glb_conv_result.failed

	# Print detailed summary
	_print_summary(module_results, total_passed, total_failed)

	# Exit with appropriate code
	quit(0 if total_failed == 0 else 1)


func _check_test_assets() -> bool:
	var required_files = ["test.png", "test.jpg", "test.wav", "test.mp3", "test.glb"]
	var missing: Array[String] = []

	for filename in required_files:
		var path = TEST_ASSETS_DIR + "/" + filename
		if not FileAccess.file_exists(path):
			missing.append(filename)

	if missing.size() > 0:
		print("Missing test assets: " + ", ".join(missing))
		return false

	return true


func _clean_output_dir():
	# Ensure output directory exists
	var output_path = ProjectSettings.globalize_path(TEST_OUTPUT_DIR)
	if not DirAccess.dir_exists_absolute(output_path):
		DirAccess.make_dir_recursive_absolute(output_path)
		return

	var dir = DirAccess.open(TEST_OUTPUT_DIR)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if not dir.current_is_dir():
				dir.remove(filename)
			filename = dir.get_next()
		dir.list_dir_end()


func _print_summary(module_results: Array[Dictionary], total_passed: int, total_failed: int):
	print("\n" + "=".repeat(60))
	print("TEST SUMMARY")
	print("=".repeat(60))

	print("\nModule Results:")
	print("-".repeat(40))

	for module in module_results:
		var result = module.result
		var status = "PASS" if result.failed == 0 else "FAIL"
		var icon = "[OK]" if result.failed == 0 else "[XX]"
		print("  %s %-25s %d/%d" % [icon, module.name, result.passed, result.passed + result.failed])

		# Print failed test names if any
		if result.failed > 0:
			for test in result.tests:
				if not test.passed:
					print("      - %s" % test.name)

	print("-".repeat(40))
	print("\nTotal: %d tests" % (total_passed + total_failed))
	print("Passed: %d" % total_passed)
	print("Failed: %d" % total_failed)
	print("=".repeat(60))

	if total_failed == 0:
		print("\n  ALL TESTS PASSED!\n")
	else:
		print("\n  SOME TESTS FAILED!\n")
