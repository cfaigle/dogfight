class_name RoadModule
extends RefCounted

## Road generation module with basic A* pathfinding.
##
## API:
## - generate_road(start, end, params) -> PackedVector3Array
## - create_road_mesh(path, width, material) -> MeshInstance3D
##
## Notes:
## - Uses a 2D grid (Vector2i keys) for speed
## - Adds cost for water and steep slopes
## - Path smoothing is a simple averaging pass (fast + stable)

# Grid / costs
var _grid_resolution: float = 12.0 # meters per cell
var _water_cost: float = 220.0
var _steep_cost: float = 70.0
var _bridge_cost: float = 35.0

# Terrain query interface
var _terrain_generator: TerrainGenerator = null

# Convenience properties (callers can set fields directly).
var terrain_generator: TerrainGenerator:
	set(value):
		_terrain_generator = value
	get:
		return _terrain_generator

var road_width: float = 18.0
var road_smooth: bool = true
var allow_bridges: bool = true

func set_terrain_generator(gen: TerrainGenerator) -> void:
	_terrain_generator = gen

func set_grid_resolution(meters: float) -> void:
	_grid_resolution = maxf(2.0, meters)

## Generate road between two points.
func generate_road(start: Vector3, end: Vector3, params: Dictionary = {}) -> PackedVector3Array:
	if _terrain_generator == null:
		push_error("RoadModule: terrain_generator not set")
		return PackedVector3Array()

	# Merge caller params with instance defaults.
	var p_allow_bridges: bool = bool(params.get("allow_bridges", allow_bridges))
	var p_smooth: bool = bool(params.get("smooth", road_smooth))
	var p_grid: float = float(params.get("grid_resolution", _grid_resolution))
	set_grid_resolution(p_grid)

	var path: Array[Vector3] = _find_path(start, end, p_allow_bridges)

	if p_smooth:
		path = _smooth_path(path)

	# Convert to packed array.
	var out := PackedVector3Array()
	out.resize(path.size())
	for i in range(path.size()):
		out[i] = path[i]
	return out

## A* on a 2D grid. Returns Array[Vector3] world points.
func _find_path(start: Vector3, end: Vector3, p_allow_bridges: bool) -> Array[Vector3]:
	var open_set: Array[Vector2i] = []
	var open_lookup: Dictionary = {}
	var closed: Dictionary = {}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}

	var start_key: Vector2i = _vec_to_grid(start)
	var end_key: Vector2i = _vec_to_grid(end)

	open_set.append(start_key)
	open_lookup[start_key] = true
	g_score[start_key] = 0.0
	f_score[start_key] = _heuristic(start, end)

	var iterations: int = 0
	var max_iterations: int = 14000

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1

		# Find node with smallest f.
		var current_key: Vector2i = open_set[0]
		var current_f: float = float(f_score.get(current_key, INF))
		for k in open_set:
			var f: float = float(f_score.get(k, INF))
			if f < current_f:
				current_f = f
				current_key = k

		if current_key == end_key:
			return _reconstruct_path(came_from, current_key, start_key, start, end)

		open_set.erase(current_key)
		open_lookup.erase(current_key)
		closed[current_key] = true

		for n in _get_neighbors(current_key):
			if closed.has(n):
				continue

			var a_pos: Vector3 = _grid_to_vec(current_key)
			var b_pos: Vector3 = _grid_to_vec(n)
			var tentative_g: float = float(g_score.get(current_key, INF)) + _movement_cost(a_pos, b_pos, p_allow_bridges)

			var old_g: float = float(g_score.get(n, INF))
			var in_open: bool = open_lookup.has(n)
			if not in_open:
				open_set.append(n)
				open_lookup[n] = true
			elif tentative_g >= old_g:
				continue

			came_from[n] = current_key
			g_score[n] = tentative_g
			f_score[n] = tentative_g + _heuristic(b_pos, end)

	# Fallback: straight line.
	push_warning("RoadModule: No path found (iters=%d) - using straight line" % iterations)
	return [start, end]

func _movement_cost(from: Vector3, to: Vector3, p_allow_bridges: bool) -> float:
	var base_cost: float = from.distance_to(to)

	var h: float = _terrain_generator.get_height_at(to.x, to.z)
	if h < float(Game.sea_level):
		return base_cost + (_bridge_cost if p_allow_bridges else _water_cost)

	var slope: float = _terrain_generator.get_slope_at(to.x, to.z)
	if slope > 14.0:
		return base_cost + _steep_cost * (slope / 45.0)

	return base_cost

func _heuristic(a: Vector3, b: Vector3) -> float:
	return a.distance_to(b)

func _get_neighbors(key: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			out.append(Vector2i(key.x + dx, key.y + dy))
	return out

func _vec_to_grid(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / _grid_resolution)), int(floor(pos.z / _grid_resolution)))

func _grid_to_vec(key: Vector2i) -> Vector3:
	# Center of the cell, with Y from terrain.
	var x: float = (float(key.x) + 0.5) * _grid_resolution
	var z: float = (float(key.y) + 0.5) * _grid_resolution
	var y: float = _terrain_generator.get_height_at(x, z) + 0.08
	return Vector3(x, y, z)

func _reconstruct_path(came_from: Dictionary, current: Vector2i, start_key: Vector2i, start_pos: Vector3, end_pos: Vector3) -> Array[Vector3]:
	var keys: Array[Vector2i] = [current]
	var cur: Vector2i = current
	var guard: int = 0
	while cur != start_key and came_from.has(cur) and guard < 20000:
		guard += 1
		cur = came_from[cur] as Vector2i
		keys.append(cur)

	keys.reverse()

	var pts: Array[Vector3] = []
	pts.resize(keys.size())
	for i in range(keys.size()):
		pts[i] = _grid_to_vec(keys[i])

	# Snap endpoints to the requested points (avoid noticeable "grid snapping" at ends).
	if pts.size() >= 1:
		pts[0] = start_pos
	if pts.size() >= 2:
		pts[pts.size() - 1] = end_pos
	return pts

func _smooth_path(path: Array[Vector3]) -> Array[Vector3]:
	if path.size() < 3:
		return path

	var out: Array[Vector3] = []
	out.append(path[0])

	for i in range(1, path.size() - 1):
		var p0: Vector3 = path[i - 1]
		var p1: Vector3 = path[i]
		var p2: Vector3 = path[i + 1]
		var s: Vector3 = (p0 + p1 + p2) / 3.0
		s.y = _terrain_generator.get_height_at(s.x, s.z) + 0.08
		out.append(s)

	out.append(path[path.size() - 1])
	return out

## Create a simple road strip mesh and return a MeshInstance3D.
func create_road_mesh(path: PackedVector3Array, width: float = 18.0, material: Material = null) -> MeshInstance3D:
	if path.size() < 2:
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(path.size() - 1):
		var p0: Vector3 = path[i]
		var p1: Vector3 = path[i + 1]
		var dir: Vector3 = (p1 - p0).normalized()
		var right: Vector3 = dir.cross(Vector3.UP).normalized() * width * 0.5

		var v0: Vector3 = p0 - right
		var v1: Vector3 = p0 + right
		var v2: Vector3 = p1 + right
		var v3: Vector3 = p1 - right

		# Fixed winding order: counter-clockwise when viewed from above
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, float(i))); st.add_vertex(v0)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, float(i + 1))); st.add_vertex(v2)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, float(i))); st.add_vertex(v1)

		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, float(i))); st.add_vertex(v0)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.0, float(i + 1))); st.add_vertex(v3)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(1.0, float(i + 1))); st.add_vertex(v2)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	if material != null:
		mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
