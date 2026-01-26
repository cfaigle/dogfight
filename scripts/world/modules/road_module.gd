class_name RoadModule
extends RefCounted

## Road generation module with pathfinding and obstacle avoidance
## Foundation for component-based world building system
## Routes around water, creates bridges, avoids steep terrain

# Pathfinding parameters
var _grid_resolution: float = 10.0  # Grid cell size for pathfinding
var _water_cost: float = 100.0      # High cost to avoid water
var _steep_cost: float = 50.0       # Cost penalty for steep slopes
var _bridge_cost: float = 30.0      # Cost to build bridges

# Terrain query interface
var _terrain_generator: TerrainGenerator = null

func set_terrain_generator(gen: TerrainGenerator) -> void:
	_terrain_generator = gen

## Generate road between two points
## @param start: Start position
## @param end: End position
## @param params: Road parameters (width, material, etc.)
## @return Array of Vector3 waypoints
func generate_road(start: Vector3, end: Vector3, params: Dictionary) -> Array:
	if not _terrain_generator:
		push_error("RoadModule: terrain_generator not set")
		return []

	# Simple pathfinding using A* on terrain grid
	var path = _find_path(start, end, params)

	# Smooth the path
	if params.get("smooth", true):
		path = _smooth_path(path, params)

	return path

## Find path using A* algorithm
func _find_path(start: Vector3, end: Vector3, params: Dictionary) -> Array:
	# A* pathfinding implementation
	var open_set = []
	var closed_set = {}
	var came_from = {}
	var g_score = {}
	var f_score = {}

	var start_key = _vec_to_grid(start)
	var end_key = _vec_to_grid(end)

	open_set.append(start_key)
	g_score[start_key] = 0.0
	f_score[start_key] = _heuristic(start, end)

	var max_iterations = 10000
	var iterations = 0

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1

		# Find node with lowest f_score
		var current_key = open_set[0]
		var min_f = f_score.get(current_key, INF)
		for key in open_set:
			var f = f_score.get(key, INF)
			if f < min_f:
				min_f = f
				current_key = key

		if current_key == end_key:
			# Reconstruct path
			return _reconstruct_path(came_from, current_key, start_key)

		open_set.erase(current_key)
		closed_set[current_key] = true

		# Check neighbors
		for neighbor_key in _get_neighbors(current_key):
			if closed_set.has(neighbor_key):
				continue

			var neighbor_pos = _grid_to_vec(neighbor_key)
			var tentative_g = g_score.get(current_key, INF) + _movement_cost(
				_grid_to_vec(current_key),
				neighbor_pos,
				params
			)

			if not open_set.has(neighbor_key):
				open_set.append(neighbor_key)
			elif tentative_g >= g_score.get(neighbor_key, INF):
				continue

			came_from[neighbor_key] = current_key
			g_score[neighbor_key] = tentative_g
			f_score[neighbor_key] = tentative_g + _heuristic(neighbor_pos, end)

	# No path found - return straight line
	push_warning("RoadModule: No path found, using straight line")
	return [start, end]

## Calculate movement cost between two points
func _movement_cost(from: Vector3, to: Vector3, params: Dictionary) -> float:
	var base_cost = from.distance_to(to)

	# Check terrain height (water detection)
	var height = _terrain_generator.get_height_at(to.x, to.z)
	if height < Game.sea_level:
		# In water - high cost unless building bridges
		if params.get("allow_bridges", true):
			return base_cost + _bridge_cost
		else:
			return base_cost + _water_cost

	# Check slope
	var slope = _terrain_generator.get_slope_at(to.x, to.z)
	if slope > 15.0:  # Steep terrain
		return base_cost + _steep_cost * (slope / 45.0)

	return base_cost

## Heuristic for A* (Euclidean distance)
func _heuristic(from: Vector3, to: Vector3) -> float:
	return from.distance_to(to)

## Get neighbor grid cells
func _get_neighbors(key: String) -> Array:
	var coords = key.split(",")
	var x = int(coords[0])
	var z = int(coords[1])

	var neighbors = []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			neighbors.append("%d,%d" % [x + dx, z + dz])

	return neighbors

## Convert world position to grid key
func _vec_to_grid(pos: Vector3) -> String:
	var x = int(floor(pos.x / _grid_resolution))
	var z = int(floor(pos.z / _grid_resolution))
	return "%d,%d" % [x, z]

## Convert grid key to world position
func _grid_to_vec(key: String) -> Vector3:
	var coords = key.split(",")
	var x = float(coords[0]) * _grid_resolution
	var z = float(coords[1]) * _grid_resolution
	var y = _terrain_generator.get_height_at(x, z) if _terrain_generator else 0.0
	return Vector3(x, y, z)

## Reconstruct path from A* came_from chain
func _reconstruct_path(came_from: Dictionary, current: String, start: String) -> Array:
	var path = []
	var key = current

	while key != start:
		path.push_front(_grid_to_vec(key))
		if not came_from.has(key):
			break
		key = came_from[key]

	path.push_front(_grid_to_vec(start))
	return path

## Smooth path using Catmull-Rom or simple averaging
func _smooth_path(path: Array, params: Dictionary) -> Array:
	if path.size() < 3:
		return path

	var smoothed = [path[0]]  # Keep start point

	# Simple averaging smoothing
	for i in range(1, path.size() - 1):
		var prev = path[i - 1]
		var curr = path[i]
		var next = path[i + 1]
		var smooth_point = (prev + curr + next) / 3.0
		smooth_point.y = _terrain_generator.get_height_at(smooth_point.x, smooth_point.z) + 0.1
		smoothed.append(smooth_point)

	smoothed.append(path[-1])  # Keep end point
	return smoothed

## Create road mesh from path
func create_road_mesh(path: Array, width: float, material: Material) -> MeshInstance3D:
	if path.size() < 2:
		return null

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Generate road strip along path
	for i in range(path.size() - 1):
		var p0: Vector3 = path[i]
		var p1: Vector3 = path[i + 1]

		var dir = (p1 - p0).normalized()
		var right = dir.cross(Vector3.UP).normalized() * width * 0.5

		var v0 = p0 - right
		var v1 = p0 + right
		var v2 = p1 + right
		var v3 = p1 - right

		# Create quad
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, float(i)))
		st.add_vertex(v0)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, float(i)))
		st.add_vertex(v1)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, float(i + 1)))
		st.add_vertex(v2)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, float(i)))
		st.add_vertex(v0)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, float(i + 1)))
		st.add_vertex(v2)

		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, float(i + 1)))
		st.add_vertex(v3)

	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return mi
