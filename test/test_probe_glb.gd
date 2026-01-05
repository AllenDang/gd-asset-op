class_name TestProbeGlb
extends "res://test/test_base.gd"
## Detailed tests for AssetProbe.probe_glb()

func run_all() -> Dictionary:
	var results = {"passed": 0, "failed": 0, "tests": []}

	print("\n  [MODULE] probe_glb")

	# Run each test
	var tests = [
		"test_probe_valid_glb",
		"test_probe_glb_face_count",
		"test_probe_glb_vertex_count",
		"test_probe_glb_aabb",
		"test_probe_glb_materials",
		"test_probe_glb_textures",
		"test_probe_glb_meshes_array",
		"test_probe_glb_skeleton_info",
		"test_probe_glb_animations",
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


# ============================================================
# Test: Valid GLB returns proper structure
# ============================================================
func test_probe_valid_glb():
	begin_test("probe_glb returns valid structure")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	# Should not have error
	assert_no_error(result, "probe_glb should succeed")

	# Check all required keys exist
	assert_has_key(result, "face_count", "must have face_count")
	assert_has_key(result, "vertex_count", "must have vertex_count")
	assert_has_key(result, "aabb", "must have aabb")
	assert_has_key(result, "has_skeleton", "must have has_skeleton")
	assert_has_key(result, "skeleton_info", "must have skeleton_info")
	assert_has_key(result, "animations", "must have animations")
	assert_has_key(result, "meshes", "must have meshes")
	assert_has_key(result, "materials", "must have materials")
	assert_has_key(result, "textures", "must have textures")


# ============================================================
# Test: Face count is correct
# ============================================================
func test_probe_glb_face_count():
	begin_test("probe_glb face_count validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# face_count should be int
	assert_is_int(result.face_count, "face_count should be int")

	# Test GLB is BoxTextured = 12 faces (cube with 6 sides × 2 triangles)
	assert_eq(result.face_count, 12, "test.glb should have 12 faces (cube)")

	# Face count must be non-negative
	assert_gte(result.face_count, 0, "face_count must be >= 0")


# ============================================================
# Test: Vertex count is correct
# ============================================================
func test_probe_glb_vertex_count():
	begin_test("probe_glb vertex_count validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# vertex_count should be int
	assert_is_int(result.vertex_count, "vertex_count should be int")

	# Test GLB is BoxTextured = 24 vertices (cube with 6 faces × 4 vertices)
	assert_eq(result.vertex_count, 24, "test.glb should have 24 vertices")

	# Vertex count must be non-negative
	assert_gte(result.vertex_count, 0, "vertex_count must be >= 0")

	# Vertex count should be >= face_count (for triangles, at least)
	assert_gte(result.vertex_count, result.face_count, "vertex_count >= face_count")


# ============================================================
# Test: AABB is valid
# ============================================================
func test_probe_glb_aabb():
	begin_test("probe_glb AABB validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# aabb should be AABB type
	assert_true(result.aabb is AABB, "aabb should be AABB type")

	var aabb: AABB = result.aabb

	# Test GLB is BoxTextured (unit cube centered at origin)
	# Position is at (-0.5, -0.5, -0.5), size is (1.0, 1.0, 1.0)
	assert_approx(aabb.position.x, -0.5, 0.01, "AABB min X")
	assert_approx(aabb.position.y, -0.5, 0.01, "AABB min Y")
	assert_approx(aabb.position.z, -0.5, 0.01, "AABB min Z")

	assert_approx(aabb.size.x, 1.0, 0.01, "AABB size X")
	assert_approx(aabb.size.y, 1.0, 0.01, "AABB size Y")
	assert_approx(aabb.size.z, 1.0, 0.01, "AABB size Z")


# ============================================================
# Test: Materials array
# ============================================================
func test_probe_glb_materials():
	begin_test("probe_glb materials validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# materials should be PackedStringArray
	assert_true(result.materials is PackedStringArray, "materials should be PackedStringArray")

	# Test GLB has 1 material
	assert_eq(result.materials.size(), 1, "test.glb should have 1 material")


# ============================================================
# Test: Textures array structure
# ============================================================
func test_probe_glb_textures():
	begin_test("probe_glb textures validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# textures should be Array
	assert_is_array(result.textures, "textures should be Array")

	# Test GLB has 1 texture
	assert_eq(result.textures.size(), 1, "test.glb should have 1 texture")

	if result.textures.size() > 0:
		var tex = result.textures[0]
		assert_is_dict(tex, "texture entry should be Dictionary")
		assert_has_key(tex, "name", "texture should have name")
		assert_has_key(tex, "mime_type", "texture should have mime_type")

		# Test GLB has PNG texture
		assert_eq(tex.mime_type, "image/png", "texture should be PNG")


# ============================================================
# Test: Meshes array structure
# ============================================================
func test_probe_glb_meshes_array():
	begin_test("probe_glb meshes array validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# meshes should be Array
	assert_is_array(result.meshes, "meshes should be Array")

	# Test GLB has 1 mesh
	assert_eq(result.meshes.size(), 1, "test.glb should have 1 mesh")

	if result.meshes.size() > 0:
		var mesh = result.meshes[0]
		assert_is_dict(mesh, "mesh entry should be Dictionary")

		# Check mesh structure
		assert_has_key(mesh, "name", "mesh should have name")
		assert_has_key(mesh, "primitive_count", "mesh should have primitive_count")
		assert_has_key(mesh, "face_count", "mesh should have face_count")
		assert_has_key(mesh, "vertex_count", "mesh should have vertex_count")
		assert_has_key(mesh, "material_index", "mesh should have material_index")

		# Validate mesh values for BoxTextured (cube)
		assert_eq(mesh.primitive_count, 1, "mesh should have 1 primitive")
		assert_eq(mesh.face_count, 12, "mesh should have 12 faces")
		assert_eq(mesh.vertex_count, 24, "mesh should have 24 vertices")
		assert_eq(mesh.material_index, 0, "mesh should use material 0")


# ============================================================
# Test: Skeleton info structure
# ============================================================
func test_probe_glb_skeleton_info():
	begin_test("probe_glb skeleton_info validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# has_skeleton should be bool
	assert_true(result.has_skeleton is bool, "has_skeleton should be bool")

	# Test GLB has no skeleton
	assert_false(result.has_skeleton, "test.glb should have no skeleton")

	# skeleton_info should be Dictionary
	assert_is_dict(result.skeleton_info, "skeleton_info should be Dictionary")

	var skel = result.skeleton_info
	assert_has_key(skel, "bone_count", "skeleton_info should have bone_count")
	assert_has_key(skel, "bone_names", "skeleton_info should have bone_names")

	# No skeleton means 0 bones
	assert_eq(skel.bone_count, 0, "bone_count should be 0")
	assert_true(skel.bone_names is PackedStringArray, "bone_names should be PackedStringArray")
	assert_eq(skel.bone_names.size(), 0, "bone_names should be empty")


# ============================================================
# Test: Animations array
# ============================================================
func test_probe_glb_animations():
	begin_test("probe_glb animations validation")

	var path = get_asset_path("test.glb")
	var result = AssetProbe.probe_glb(path)

	assert_no_error(result)

	# animations should be Array
	assert_is_array(result.animations, "animations should be Array")

	# Test GLB has no animations
	assert_eq(result.animations.size(), 0, "test.glb should have 0 animations")


# ============================================================
# Test: Missing file error
# ============================================================
func test_probe_missing_file():
	begin_test("probe_glb missing file error")

	var path = "/nonexistent/path/to/model.glb"
	var result = AssetProbe.probe_glb(path)

	# Should have error
	assert_has_error(result, "should return error for missing file")
	assert_string_contains(result.error, "not found", "error should mention 'not found'")


# ============================================================
# Test: Invalid file error
# ============================================================
func test_probe_invalid_file():
	begin_test("probe_glb invalid file error")

	# Try to probe a non-GLB file
	var path = get_asset_path("test.png")
	var result = AssetProbe.probe_glb(path)

	# Should have error (PNG is not valid GLB)
	assert_has_error(result, "should return error for invalid GLB")
