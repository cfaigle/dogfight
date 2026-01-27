class_name SettlementGenerator
extends RefCounted

const RoadModule = preload("res://scripts/world/modules/road_module.gd")

var _terrain: TerrainGenerator = null
var _assets: RefCounted = null
var _world_ctx: RefCounted = null

var _settlements: Array = []
var _prop_lod_groups: Array = []

func set_terrain_generator(t: TerrainGenerator) -> void:
	_terrain = t

func set_assets(a: RefCounted) -> void:
	_assets = a

func get_settlements() -> Array:
	return _settlements

func get_prop_lod_groups() -> Array:
	return _prop_lod_groups

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator, parametric_system: RefCounted = null, world_ctx: RefCounted = null) -> Dictionary:
	# world_root here is expected to be the Infrastructure layer.
	_settlements = []
	_prop_lod_groups = []
	_world_ctx = world_ctx
	if _terrain == null:
		push_error("SettlementGenerator: missing terrain generator")
		return {"settlements": _settlements, "prop_lod_groups": _prop_lod_groups}

	var infra_root: Node3D = world_root
	var props_root: Node3D = infra_root.get_parent() if infra_root.get_parent() is Node3D else infra_root
	# Prefer dedicated Props layer if it exists
	if props_root != infra_root and props_root.get_node_or_null("Props") is Node3D:
		props_root = props_root.get_node("Props")

	var sd := Node3D.new()
	sd.name = "Settlements"
	props_root.add_child(sd)

	# --- Materials / meshes (fast, no external assets required)
	var city_mesh := BoxMesh.new()
	var house_mesh := BoxMesh.new()
	var ind_mesh := BoxMesh.new()

	var mat_city := StandardMaterial3D.new()
	mat_city.albedo_color = Color(0.18, 0.18, 0.20)
	mat_city.roughness = 0.95

	var mat_house := StandardMaterial3D.new()
	mat_house.albedo_color = Color(0.20, 0.20, 0.22)
	mat_house.roughness = 0.95

	var mat_ind := StandardMaterial3D.new()
	mat_ind.albedo_color = Color(0.16, 0.17, 0.16)
	mat_ind.roughness = 0.96

	# --- City
	var city_buildings: int = int(params.get("city_buildings", 600))
	var town_count: int = int(params.get("town_count", 5))
	var hamlet_count: int = int(params.get("hamlet_count", 12))

	var city_center: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.50, true)
	if city_center == Vector3.ZERO:
		city_center = Vector3(0.0, _terrain.get_height_at(0.0, 0.0), 0.0)

	var city_radius: float = rng.randf_range(520.0, 820.0)
	if parametric_system != null:
		_build_cluster_parametric(sd, city_center, city_radius, city_buildings, "commercial", "american_art_deco", parametric_system, rng, 22.0, true, world_ctx)
	else:
		_build_cluster(sd, city_center, city_radius, city_buildings, city_mesh, mat_city, rng, 22.0, true, true)
	_settlements.append({"type": "city", "center": city_center, "radius": city_radius})

	# --- Towns
	for _i in range(town_count):
		var c: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.55, false)
		if c == Vector3.ZERO:
			continue
		if _too_close_to_settlements(c, 1200.0):
			continue
		var rad: float = rng.randf_range(300.0, 520.0)
		if parametric_system != null:
			_build_cluster_parametric(sd, c, rad, rng.randi_range(220, 420), "residential", "ww2_european", parametric_system, rng, 26.0, false, world_ctx)
		else:
			_build_cluster(sd, c, rad, rng.randi_range(220, 420), house_mesh, mat_house, rng, 26.0, false, true)
		_settlements.append({"type": "town", "center": c, "radius": rad})

	# --- Hamlets
	for _i2 in range(hamlet_count):
		var c2: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.65, false)
		if c2 == Vector3.ZERO:
			continue
		if _too_close_to_settlements(c2, 650.0):
			continue
		var rad2: float = rng.randf_range(150.0, 280.0)
		if parametric_system != null:
			_build_cluster_parametric(sd, c2, rad2, rng.randi_range(40, 110), "residential", "ww2_european", parametric_system, rng, 30.0, false, world_ctx)
		else:
			_build_cluster(sd, c2, rad2, rng.randi_range(40, 110), house_mesh, mat_house, rng, 30.0, false, false)
		_settlements.append({"type": "hamlet", "center": c2, "radius": rad2})

	# --- Small industrial sites near city
	for _j in range(int(params.get("industry_sites", 6))):
		var c3 := city_center + Vector3(rng.randf_range(-1100.0, 1100.0), 0.0, rng.randf_range(-1100.0, 1100.0))
		c3.y = _terrain.get_height_at(c3.x, c3.z)
		if c3.y < Game.sea_level + 6.0:
			continue
		if parametric_system != null:
			_build_cluster_parametric(sd, c3, rng.randf_range(180.0, 320.0), rng.randi_range(40, 90), "industrial", "industrial_modern", parametric_system, rng, 30.0, false, world_ctx)
		else:
			_build_cluster(sd, c3, rng.randf_range(180.0, 320.0), rng.randi_range(40, 90), ind_mesh, mat_ind, rng, 30.0, false, false)
		_settlements.append({"type": "industry", "center": c3, "radius": 260.0})

	return {"settlements": _settlements, "prop_lod_groups": _prop_lod_groups}

func _build_cluster(parent: Node3D, center: Vector3, radius: float, count: int, mesh: Mesh, mat: Material, rng: RandomNumberGenerator, max_slope_deg: float, tall: bool, allow_variety: bool) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cluster_%s" % str(parent.get_child_count())
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.multimesh.instance_count = 0
	# MultiMeshInstance3D doesn't have a direct `mesh` property in Godot 4;
	# the mesh is assigned on its MultiMesh resource.
	mmi.multimesh.mesh = mesh
	mmi.material_override = mat
	parent.add_child(mmi)

	var transforms: Array[Transform3D] = []
	transforms.resize(count)
	var written: int = 0

	var tries: int = 0
	var max_tries: int = count * 8
	while written < count and tries < max_tries:
		tries += 1
		var ang: float = rng.randf_range(0.0, TAU)
		var r: float = radius * sqrt(rng.randf())
		var x: float = center.x + cos(ang) * r
		var z: float = center.z + sin(ang) * r
		var h: float = _terrain.get_height_at(x, z)
		if h < Game.sea_level + 0.45:
			continue
		if _terrain.get_slope_at(x, z) > max_slope_deg:
			continue

		# Check if in lake (avoid placing buildings in lakes)
		if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
			if _world_ctx.is_in_lake(x, z, 10.0):  # 10m buffer from lake edge
				continue

		var yaw: float = rng.randf_range(-PI, PI)
		var base_w: float = rng.randf_range(8.0, 16.0)
		var base_d: float = rng.randf_range(8.0, 16.0)
		var base_h: float = rng.randf_range(10.0, 22.0)
		if tall:
			base_h = rng.randf_range(18.0, 68.0)
		if allow_variety and rng.randf() < 0.18:
			base_w *= 1.8
			base_d *= 1.4
			base_h *= 0.55

		var basis := Basis(Vector3.UP, yaw)
		basis = basis.scaled(Vector3(base_w, base_h, base_d))
		var t3 := Transform3D(basis, Vector3(x, h + base_h * 0.5, z))
		transforms[written] = t3
		written += 1

	mmi.multimesh.instance_count = written
	for i in range(written):
		mmi.multimesh.set_instance_transform(i, transforms[i])

func _build_cluster_parametric(
	parent: Node3D,
	center: Vector3,
	radius: float,
	count: int,
	building_type: String,  # "residential", "commercial", "industrial"
	style: String,  # "ww2_european", "american_art_deco", "industrial_modern"
	parametric_system: RefCounted,
	rng: RandomNumberGenerator,
	max_slope_deg: float,
	tall: bool,
	world_ctx: RefCounted = null
) -> void:
	if parametric_system == null:
		return

	var placed: int = 0
	var tries: int = 0
	var max_tries: int = count * 8
	var skipped_on_road: int = 0

	while placed < count and tries < max_tries:
		tries += 1

		# Find position (existing logic)
		var ang: float = rng.randf_range(0.0, TAU)
		var r: float = radius * sqrt(rng.randf())
		var x: float = center.x + cos(ang) * r
		var z: float = center.z + sin(ang) * r
		var h: float = _terrain.get_height_at(x, z)

		# Slope/water checks (existing)
		if h < Game.sea_level + 0.45:
			continue
		if _terrain.get_slope_at(x, z) > max_slope_deg:
			continue

		# Check if in lake (avoid placing buildings in lakes)
		if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
			if _world_ctx.is_in_lake(x, z, 10.0):  # 10m buffer from lake edge
				continue

		# Check if on road (avoid placing buildings on roads)
		if world_ctx != null and world_ctx.has_method("is_on_road"):
			if world_ctx.is_on_road(x, z, 12.0):  # 12m buffer from road
				skipped_on_road += 1
				continue

		# Building dimensions
		var width: float = rng.randf_range(8.0, 16.0)
		var depth: float = rng.randf_range(8.0, 16.0)
		var height: float = rng.randf_range(12.0, 24.0) if tall else rng.randf_range(8.0, 18.0)
		var floors: int = max(1, int(height / 4.0))  # Multi-story!

		# Generate parametric building
		var mesh: Mesh = parametric_system.create_parametric_building(
			building_type,
			style,
			width,
			depth,
			height,
			floors,
			1  # quality level (0=low, 1=medium, 2=high)
		)

		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(x, h, z)
			mi.rotation.y = rng.randf_range(-PI, PI)
			parent.add_child(mi)
			placed += 1

func _too_close_to_settlements(p: Vector3, buffer: float) -> bool:
	for s in _settlements:
		if not (s is Dictionary):
			continue
		var c: Vector3 = (s as Dictionary).get("center", Vector3.ZERO)
		var r: float = float((s as Dictionary).get("radius", 300.0))
		if p.distance_to(c) < (r + buffer):
			return true
	return false

