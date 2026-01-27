class_name PropGenerator
extends RefCounted

var _terrain: TerrainGenerator = null
var _assets: RefCounted = null
var _settlements: Array = []

# Optional biome service (e.g. BiomeGenerator) providing `classify(x,z)`
var _biomes: RefCounted = null

var _prop_lod_roots: Array[Node3D] = []

func set_terrain_generator(t: TerrainGenerator) -> void:
	_terrain = t

func set_assets(a: RefCounted) -> void:
	_assets = a

func set_settlements(s: Array) -> void:
	_settlements = s

func set_biome_generator(b: RefCounted) -> void:
	_biomes = b

func get_lod_roots() -> Array[Node3D]:
	return _prop_lod_roots

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	_prop_lod_roots = []
	if _terrain == null:
		push_error("PropGenerator: missing terrain generator")
		return {"prop_lod_groups": _prop_lod_roots}

	# `world_root` is already the props layer; place content directly under it.
	var props_root: Node3D = world_root

	# Forests
	var tree_target: int = int(params.get("tree_count", 8000))
	var patch_count: int = int(params.get("forest_patches", 26))

	var external_tree_variants: Array[Mesh] = []
	if _assets != null and _assets.has_method("enabled") and bool(_assets.call("enabled")):
		if _assets.has_method("get_mesh_variants"):
			var conifers: Array[Mesh] = _assets.call("get_mesh_variants", "trees_conifer")
			var broadleaf: Array[Mesh] = _assets.call("get_mesh_variants", "trees_broadleaf")
			var palms: Array[Mesh] = _assets.call("get_mesh_variants", "trees_palm")
			external_tree_variants.append_array(conifers)
			external_tree_variants.append_array(broadleaf)
			external_tree_variants.append_array(palms)

	var forest_root := Node3D.new()
	forest_root.name = "Forests"
	props_root.add_child(forest_root)

	if not external_tree_variants.is_empty():
		_build_forest_external(forest_root, rng, tree_target, patch_count, external_tree_variants)
	else:
		_build_forest_batched(forest_root, rng, tree_target, patch_count)

	# Ponds (simple water discs)
	var pond_count: int = int(params.get("pond_count", 18))
	_build_ponds(props_root, rng, pond_count)

	return {"prop_lod_groups": _prop_lod_roots}

# --- Forest helpers ---

func _build_forest_external(root: Node3D, rng: RandomNumberGenerator, tree_target: int, patch_count: int, tree_variants: Array[Mesh]) -> void:
	# Create a MultiMesh for each tree variant (efficient batching)
	var mms: Array[MultiMeshInstance3D] = []
	for i in range(tree_variants.size()):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tree_variants[i]
		mm.instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		root.add_child(inst)
		mms.append(inst)

	# Pre-allocate transforms per variant (approx equal share)
	var transforms_per_variant: Array[Array] = []
	for _i in range(tree_variants.size()):
		transforms_per_variant.append([])

	# Drop trees in patches
	var placed: int = 0
	var tries: int = 0
	var max_tries: int = tree_target * 30
	while placed < tree_target and tries < max_tries:
		tries += 1
		var center: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 4.0, 0.60, false)
		if center == Vector3.ZERO:
			continue
		if not _biome_allows_trees(center.x, center.z):
			continue
		# Patch radius scales with world size
		var patch_r: float = rng.randf_range(180.0, 520.0)
		var in_patch: int = int(float(tree_target) / float(max(1, patch_count)))
		in_patch = int(clamp(in_patch, 80, 650))
		for _t in range(in_patch):
			if placed >= tree_target:
				break
			var ang: float = rng.randf_range(0.0, TAU)
			var r: float = patch_r * sqrt(rng.randf())
			var x: float = center.x + cos(ang) * r
			var z: float = center.z + sin(ang) * r
			var h: float = _terrain.get_height_at(x, z)
			if h < Game.sea_level + 0.35:
				continue
			if _terrain.get_slope_at(x, z) > 32.0:
				continue
			if _too_close_to_settlements(Vector3(x, h, z), 250.0):
				continue
			if not _biome_allows_trees(x, z):
				continue

			var yaw: float = rng.randf_range(-PI, PI)
			var s: float = rng.randf_range(0.75, 1.55)
			var basis := Basis(Vector3.UP, yaw)
			basis = basis.scaled(Vector3(s, s, s))
			var t3 := Transform3D(basis, Vector3(x, h, z))

			var vi: int = rng.randi_range(0, tree_variants.size() - 1)
			transforms_per_variant[vi].append(t3)
			placed += 1

	# Upload transforms
	for i in range(mms.size()):
		var inst := mms[i]
		var list: Array = transforms_per_variant[i]
		inst.multimesh.instance_count = list.size()
		for j in range(list.size()):
			inst.multimesh.set_instance_transform(j, list[j])

func _build_forest_batched(root: Node3D, rng: RandomNumberGenerator, tree_target: int, patch_count: int) -> void:
	# Procedural tree mesh (fast + no external assets required)
	var tree_mesh := _make_simple_tree_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.mesh = tree_mesh
	mmi.multimesh.instance_count = tree_target
	root.add_child(mmi)

	var placed: int = 0
	var tries: int = 0
	var max_tries: int = tree_target * 40

	while placed < tree_target and tries < max_tries:
		tries += 1
		var center: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 4.0, 0.65, false)
		if center == Vector3.ZERO:
			continue
		if not _biome_allows_trees(center.x, center.z):
			continue
		var patch_r: float = rng.randf_range(160.0, 520.0)
		var in_patch: int = int(float(tree_target) / float(max(1, patch_count)))
		in_patch = int(clamp(in_patch, 90, 720))
		for _t in range(in_patch):
			if placed >= tree_target:
				break
			var ang: float = rng.randf_range(0.0, TAU)
			var r: float = patch_r * sqrt(rng.randf())
			var x: float = center.x + cos(ang) * r
			var z: float = center.z + sin(ang) * r
			var h: float = _terrain.get_height_at(x, z)
			if h < Game.sea_level + 0.35:
				continue
			if _terrain.get_slope_at(x, z) > 34.0:
				continue
			if _too_close_to_settlements(Vector3(x, h, z), 260.0):
				continue
			if not _biome_allows_trees(x, z):
				continue

			var yaw: float = rng.randf_range(-PI, PI)
			var s: float = rng.randf_range(0.80, 1.65)
			var basis := Basis(Vector3.UP, yaw)
			basis = basis.scaled(Vector3(s, s, s))
			var t3 := Transform3D(basis, Vector3(x, h, z))
			mmi.multimesh.set_instance_transform(placed, t3)
			placed += 1

	mmi.multimesh.instance_count = placed

func _make_simple_tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Trunk
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.32
	trunk.height = 3.8
	trunk.radial_segments = 8
	trunk.rings = 1
	# Leaves
	var crown := CylinderMesh.new()
	crown.top_radius = 0.02
	crown.bottom_radius = 1.8
	crown.height = 4.4
	crown.radial_segments = 10
	crown.rings = 1

	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0.0, 1.9, 0.0)))
	st.append_from(crown, 0, Transform3D(Basis(), Vector3(0.0, 5.2, 0.0)))

	st.generate_normals()
	var mesh := st.commit()
	return mesh

# --- Ponds ---

func _build_ponds(root: Node3D, rng: RandomNumberGenerator, pond_count: int) -> void:
	if pond_count <= 0:
		return

	var ponds := Node3D.new()
	ponds.name = "Ponds"
	root.add_child(ponds)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.11, 0.16, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2

	for _i in range(pond_count):
		var p: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 8.0, 0.40, false)
		if p == Vector3.ZERO:
			continue
		if not _biome_allows_ponds(p.x, p.z):
			continue
		if _too_close_to_settlements(p, 420.0):
			continue

		var r: float = rng.randf_range(45.0, 120.0)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = 0.6
		cyl.radial_segments = 32
		cyl.rings = 1
		mi.mesh = cyl
		mi.material_override = mat
		mi.position = Vector3(p.x, max(Game.sea_level + 0.3, p.y + 0.15), p.z)
		ponds.add_child(mi)


func _biome_allows_trees(x: float, z: float) -> bool:
	if _biomes == null:
		return true
	if not _biomes.has_method("classify"):
		return true
	var b: String = str(_biomes.call("classify", x, z))
	# Trees can live in forest, wetland, and grassland; allow a little in farmland too.
	return not (b in ["Ocean", "Beach", "Rock", "Snow", "Desert"])


func _biome_allows_ponds(x: float, z: float) -> bool:
	if _biomes == null or not _biomes.has_method("classify"):
		return true
	var b: String = str(_biomes.call("classify", x, z))
	# Prefer wetlands/grasslands; avoid coast + dry/harsh biomes.
	return b in ["Wetland", "Grassland", "Forest", "Farm", ""]

# --- Shared helpers ---

func _too_close_to_settlements(p: Vector3, buffer: float) -> bool:
	for s in _settlements:
		if not (s is Dictionary):
			continue
		var c: Vector3 = (s as Dictionary).get("center", Vector3.ZERO)
		var r: float = float((s as Dictionary).get("radius", 300.0))
		if p.distance_to(c) < (r + buffer):
			return true
	return false
