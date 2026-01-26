class_name TerrainGenerator
extends RefCounted

## Handles all terrain generation: heightmap, mesh chunks, ocean, rivers, runway, landmarks
## Extracted from main.gd for modularity

# Heightmap data (shared with parent)
var _hmap: PackedFloat32Array = PackedFloat32Array()
var _hmap_res: int = 0
var _hmap_half: float = 0.0
var _hmap_step: float = 0.0

# Terrain parameters
var _terrain_size: float = 0.0
var _terrain_res: int = 0
var _terrain_render_root: Node3D = null
var _terrain_lod_enabled: bool = true
var _terrain_lod0_r: float = 800.0
var _terrain_lod1_r: float = 1600.0

# Shader and asset references
var TerrainShader: Shader = null
var _assets = null
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}

# Generated settlements (for road avoidance)
var _settlements: Array = []

func set_mesh_cache(cache: Dictionary) -> void:
	_mesh_cache = cache

func set_material_cache(cache: Dictionary) -> void:
	_material_cache = cache

func set_heightmap_data(hmap: PackedFloat32Array, res: int, size: float) -> void:
	_hmap = hmap
	_hmap_res = res
	_hmap_half = size * 0.5
	_hmap_step = size / float(res)
	_terrain_size = size
	_terrain_res = res

func set_settlements(settlements: Array) -> void:
	_settlements = settlements

## Main generation entry point
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Terrain mesh generation will be called separately by WorldBuilder
	pass

## Get height at world position
func get_height_at(x: float, z: float) -> float:
	return _ground_height(x, z)

## Get normal at world position
func get_normal_at(x: float, z: float) -> Vector3:
	if _hmap_res <= 0 or _hmap.is_empty():
		return Vector3.UP

	var u: float = (x + _hmap_half) / _hmap_step
	var v: float = (z + _hmap_half) / _hmap_step
	u = clamp(u, 0.0, float(_hmap_res))
	v = clamp(v, 0.0, float(_hmap_res))

	var x0: int = int(floor(u))
	var z0: int = int(floor(v))

	return _n_at_idx(x0, z0, _hmap_step)

## Get slope at world position (degrees)
func get_slope_at(x: float, z: float) -> float:
	return rad_to_deg(atan(_slope_at(x, z)))

## Check if near coastline
func is_near_coast(x: float, z: float, radius: float) -> bool:
	var h: float = _ground_height(x, z)
	if h > Game.sea_level + 1.5:
		return false
	for i in range(8):
		var ang: float = float(i) * PI * 0.25
		var tx: float = x + cos(ang) * radius
		var tz: float = z + sin(ang) * radius
		var th: float = _ground_height(tx, tz)
		if th < Game.sea_level:
			return true
	return false

## Find random land point
func find_land_point(rng: RandomNumberGenerator, min_height: float, max_slope: float, prefer_coast: bool) -> Vector3:
	var sz: float = _terrain_size
	var max_tries: int = 500
	for i in range(max_tries):
		var x: float = rng.randf_range(-sz * 0.45, sz * 0.45)
		var z: float = rng.randf_range(-sz * 0.45, sz * 0.45)
		var h: float = _ground_height(x, z)
		var sl: float = _slope_at(x, z)
		if h < min_height or sl > max_slope:
			continue
		if prefer_coast:
			if not is_near_coast(x, z, 150.0):
				continue
		return Vector3(x, h, z)
	return Vector3.ZERO

## Build ocean mesh
func build_ocean(world_root: Node3D, params: Dictionary) -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(82000.0, 82000.0)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	ocean.mesh = pm
	ocean.position = Vector3(0.0, Game.sea_level - 0.35, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://resources/shaders/ocean.gdshader")
	ocean.material_override = mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(ocean)

## Build rivers
func build_rivers(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Rivers stub - original logic can be moved here
	pass

## Build runway
func build_runway(world_root: Node3D, params: Dictionary) -> void:
	# Runway stub - original logic can be moved here
	pass

## Build landmarks
func build_landmarks(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Landmarks stub - original logic can be moved here
	pass

## Apply LOD to terrain chunks
func apply_terrain_lod(camera_pos: Vector3, lod_enabled: bool, lod0_r: float, lod1_r: float) -> void:
	if not _terrain_render_root:
		return

	for chunk in _terrain_render_root.get_children():
		if not chunk is Node3D:
			continue
		var center: Vector2 = chunk.get_meta("center", Vector2.ZERO)
		var dist: float = Vector2(camera_pos.x, camera_pos.z).distance_to(center)

		var new_lod: int = 0
		if lod_enabled:
			if dist < lod0_r:
				new_lod = 0
			elif dist < lod1_r:
				new_lod = 1
			else:
				new_lod = 2

		var old_lod: int = chunk.get_meta("lod", -1)
		if old_lod == new_lod:
			continue

		chunk.set_meta("lod", new_lod)
		for i in range(3):
			var lod_node = chunk.get_node_or_null("LOD%d" % i)
			if lod_node:
				lod_node.visible = (i == new_lod)

# --- Internal helper functions ---

func _ground_height(x: float, z: float) -> float:
	if _hmap_res <= 0 or _hmap.is_empty():
		return float(Game.sea_level)

	var u: float = (x + _hmap_half) / _hmap_step
	var v: float = (z + _hmap_half) / _hmap_step
	u = clamp(u, 0.0, float(_hmap_res))
	v = clamp(v, 0.0, float(_hmap_res))

	var x0: int = int(floor(u))
	var z0: int = int(floor(v))
	var x1: int = min(x0 + 1, _hmap_res)
	var z1: int = min(z0 + 1, _hmap_res)

	var fu: float = u - float(x0)
	var fv: float = v - float(z0)

	var w: int = _hmap_res + 1
	var h00: float = float(_hmap[z0 * w + x0])
	var h10: float = float(_hmap[z0 * w + x1])
	var h01: float = float(_hmap[z1 * w + x0])
	var h11: float = float(_hmap[z1 * w + x1])

	var a: float = lerp(h00, h10, fu)
	var b: float = lerp(h01, h11, fu)
	return lerp(a, b, fv)

func _slope_at(x: float, z: float) -> float:
	var h: float = _ground_height(x, z)
	var hx: float = _ground_height(x + _hmap_step, z)
	var hz: float = _ground_height(x, z + _hmap_step)
	var sx: float = absf(hx - h) / maxf(0.001, _hmap_step)
	var sz: float = absf(hz - h) / maxf(0.001, _hmap_step)
	return maxf(sx, sz)

func _h_at_idx(ix: int, iz: int) -> float:
	var res: int = _terrain_res
	var w: int = res + 1
	ix = clampi(ix, 0, res)
	iz = clampi(iz, 0, res)
	return float(_hmap[iz * w + ix])

func _n_at_idx(ix: int, iz: int, step: float) -> Vector3:
	var hL: float = _h_at_idx(ix - 1, iz)
	var hR: float = _h_at_idx(ix + 1, iz)
	var hD: float = _h_at_idx(ix, iz - 1)
	var hU: float = _h_at_idx(ix, iz + 1)
	var nx: float = hL - hR
	var nz: float = hD - hU
	var n := Vector3(nx, 2.0 * step, nz)
	if n.length() < 0.0001:
		return Vector3.UP
	return n.normalized()
