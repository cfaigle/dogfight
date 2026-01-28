class_name SettlementPlanner
extends RefCounted

## Per-settlement terrain-aware planning
## Creates realistic boundaries, road networks, and building zones

var terrain_generator: RefCounted = null
var settlement_center: Vector3 = Vector3.ZERO
var settlement_type: String = ""  # "city", "town", "hamlet"
var max_radius: float = 500.0

# Planning outputs
var boundary_polygon: PackedVector2Array = PackedVector2Array()
var valid_area: float = 0.0
var road_segments: Array = []  # Array of {from: Vector3, to: Vector3, width: float}
var building_zones: Dictionary = {}  # {"residential": [], "commercial": [], ...}
var terrain_stats: Dictionary = {}


## Main planning entry point
func plan_settlement(center: Vector3, type: String, desired_radius: float, terrain_gen: RefCounted) -> Dictionary:
	terrain_generator = terrain_gen
	settlement_center = center
	settlement_type = type
	max_radius = desired_radius

	print("🏘️  SettlementPlanner: Planning %s at (%.0f, %.0f, %.0f) radius %.0f" % [type, center.x, center.y, center.z, desired_radius])

	# Step 1: Analyze terrain to create realistic boundary
	_analyze_terrain_boundary()

	# Step 2: Plan internal road network
	_plan_road_network()

	# Step 3: Divide into building zones
	_plan_building_zones()

	# Step 4: Calculate statistics
	_calculate_stats()

	print("   ✅ Planned %s: valid area %.0fm², %d road segments, %d zones" % [type, valid_area, road_segments.size(), building_zones.size()])

	return {
		"boundary": boundary_polygon,
		"valid_area": valid_area,
		"roads": road_segments,
		"zones": building_zones,
		"stats": terrain_stats,
		"center": settlement_center,
		"type": settlement_type
	}


## Step 1: Create terrain-aware boundary polygon (not a circle!)
func _analyze_terrain_boundary() -> void:
	var water_level: float = float(Game.sea_level)
	var max_slope: float = 20.0 if settlement_type == "city" else 25.0
	var sample_count: int = 64  # Ray-cast in 64 directions

	var boundary_points: Array[Vector2] = []

	# Ray-cast from center outward in all directions
	for i in range(sample_count):
		var angle: float = float(i) * TAU / float(sample_count)
		var dir: Vector2 = Vector2(cos(angle), sin(angle))

		# Find valid distance in this direction
		var valid_distance: float = _find_valid_distance_in_direction(dir, max_radius, water_level, max_slope)

		# Add point to boundary
		var world_point: Vector2 = Vector2(settlement_center.x, settlement_center.z) + dir * valid_distance
		boundary_points.append(world_point)

	# Smooth the boundary (avoid jagged edges)
	boundary_points = _smooth_polygon(boundary_points, 3)

	# Convert to PackedVector2Array
	boundary_polygon = PackedVector2Array(boundary_points)

	# Calculate area
	valid_area = _calculate_polygon_area(boundary_polygon)


## Find valid distance from center in given direction (stops at water/steep slopes)
func _find_valid_distance_in_direction(dir: Vector2, max_dist: float, water_level: float, max_slope: float) -> float:
	var step_size: float = 10.0  # Sample every 10m
	var steps: int = int(max_dist / step_size)

	for i in range(1, steps + 1):
		var dist: float = float(i) * step_size
		var world_x: float = settlement_center.x + dir.x * dist
		var world_z: float = settlement_center.z + dir.y * dist

		# Check terrain validity
		if terrain_generator != null:
			var height: float = terrain_generator.get_height_at(world_x, world_z)
			var slope: float = terrain_generator.get_slope_at(world_x, world_z)

			# Stop at water
			if height < water_level + 0.5:
				return maxf(dist - step_size, step_size)  # Back up to last valid point

			# Stop at steep slopes
			if slope > max_slope:
				return maxf(dist - step_size, step_size)

	# Reached max distance without hitting obstacles
	return max_dist


## Smooth polygon using moving average
func _smooth_polygon(points: Array[Vector2], iterations: int) -> Array[Vector2]:
	var smoothed := points.duplicate()

	for _iter in range(iterations):
		var new_points: Array[Vector2] = []
		for i in range(smoothed.size()):
			var prev: Vector2 = smoothed[(i - 1 + smoothed.size()) % smoothed.size()]
			var curr: Vector2 = smoothed[i]
			var next: Vector2 = smoothed[(i + 1) % smoothed.size()]

			# Average with neighbors
			var avg: Vector2 = (prev + curr + next) / 3.0
			new_points.append(avg)

		smoothed = new_points

	return smoothed


## Calculate area of polygon
func _calculate_polygon_area(polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0

	var area: float = 0.0
	for i in range(polygon.size()):
		var p1: Vector2 = polygon[i]
		var p2: Vector2 = polygon[(i + 1) % polygon.size()]
		area += (p1.x * p2.y - p2.x * p1.y)

	return abs(area) * 0.5


## Step 2: Plan internal road network (terrain-aware!)
func _plan_road_network() -> void:
	road_segments.clear()

	if settlement_type == "city":
		_plan_city_grid_roads()
	elif settlement_type == "town":
		_plan_town_radial_roads()
	# Hamlets don't need internal roads


## Plan city grid roads (only within valid boundary)
func _plan_city_grid_roads() -> void:
	var spacing: float = 60.0
	var road_width: float = 10.0
	var water_level: float = float(Game.sea_level)

	# Get bounding box of boundary
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for point in boundary_polygon:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.y)
		max_z = maxf(max_z, point.y)

	# Create grid roads (only if they stay within boundary and on land)
	var grid_count: int = int((max_x - min_x) / spacing)

	# North-south roads
	for i in range(grid_count + 1):
		var x: float = min_x + float(i) * spacing
		var start_z: float = min_z
		var end_z: float = max_z

		# Check if this road stays within boundary and on land
		if _is_road_valid(Vector3(x, 0, start_z), Vector3(x, 0, end_z), water_level):
			var from: Vector3 = Vector3(x, _get_terrain_height(x, start_z), start_z)
			var to: Vector3 = Vector3(x, _get_terrain_height(x, end_z), end_z)
			road_segments.append({"from": from, "to": to, "width": road_width})

	# East-west roads
	for j in range(grid_count + 1):
		var z: float = min_z + float(j) * spacing
		var start_x: float = min_x
		var end_x: float = max_x

		# Check if this road stays within boundary and on land
		if _is_road_valid(Vector3(start_x, 0, z), Vector3(end_x, 0, z), water_level):
			var from: Vector3 = Vector3(start_x, _get_terrain_height(start_x, z), z)
			var to: Vector3 = Vector3(end_x, _get_terrain_height(end_x, z), z)
			road_segments.append({"from": from, "to": to, "width": road_width})

	# Add ring roads at 40% and 75% of boundary
	_add_ring_road(0.4, road_width * 1.2)
	_add_ring_road(0.75, road_width * 1.1)


## Plan town radial roads (spokes from center)
func _plan_town_radial_roads() -> void:
	var spoke_count: int = 8
	var road_width: float = 8.0
	var water_level: float = float(Game.sea_level)

	# Radial spokes
	for i in range(spoke_count):
		var angle: float = float(i) * TAU / float(spoke_count)
		var dir: Vector2 = Vector2(cos(angle), sin(angle))

		# Find valid length for this spoke
		var spoke_length: float = _find_valid_distance_in_direction(dir, max_radius * 0.9, water_level, 25.0)

		var end_x: float = settlement_center.x + dir.x * spoke_length
		var end_z: float = settlement_center.z + dir.y * spoke_length

		var from: Vector3 = Vector3(settlement_center.x, _get_terrain_height(settlement_center.x, settlement_center.z), settlement_center.z)
		var to: Vector3 = Vector3(end_x, _get_terrain_height(end_x, end_z), end_z)

		road_segments.append({"from": from, "to": to, "width": road_width})

	# Ring road at 70% radius
	_add_ring_road(0.7, road_width * 0.75)


## Add circular ring road
func _add_ring_road(radius_ratio: float, width: float) -> void:
	var segments: int = 32
	var water_level: float = float(Game.sea_level)

	for i in range(segments):
		var angle1: float = float(i) * TAU / float(segments)
		var angle2: float = float(i + 1) * TAU / float(segments)

		var r: float = max_radius * radius_ratio

		var x1: float = settlement_center.x + cos(angle1) * r
		var z1: float = settlement_center.z + sin(angle1) * r
		var x2: float = settlement_center.x + cos(angle2) * r
		var z2: float = settlement_center.z + sin(angle2) * r

		# Only add segment if it's within boundary and on land
		if _is_point_in_boundary(Vector2(x1, z1)) and _is_point_in_boundary(Vector2(x2, z2)):
			var from: Vector3 = Vector3(x1, _get_terrain_height(x1, z1), z1)
			var to: Vector3 = Vector3(x2, _get_terrain_height(x2, z2), z2)

			# Check if segment crosses water
			if _is_road_valid(from, to, water_level):
				road_segments.append({"from": from, "to": to, "width": width})


## Check if road segment is valid (stays on land, within boundary)
func _is_road_valid(from: Vector3, to: Vector3, water_level: float) -> bool:
	var samples: int = 10
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var p: Vector3 = from.lerp(to, t)

		# Check if point is in boundary
		if not _is_point_in_boundary(Vector2(p.x, p.z)):
			return false

		# Check if point is above water
		if terrain_generator != null:
			var height: float = terrain_generator.get_height_at(p.x, p.z)
			if height < water_level + 0.5:
				return false

	return true


## Check if 2D point is inside boundary polygon
func _is_point_in_boundary(point: Vector2) -> bool:
	if boundary_polygon.size() < 3:
		return false

	# Ray-casting algorithm
	var intersections: int = 0
	for i in range(boundary_polygon.size()):
		var p1: Vector2 = boundary_polygon[i]
		var p2: Vector2 = boundary_polygon[(i + 1) % boundary_polygon.size()]

		if _ray_intersects_segment(point, p1, p2):
			intersections += 1

	return (intersections % 2) == 1


## Ray-casting helper
func _ray_intersects_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> bool:
	if seg_start.y > seg_end.y:
		var temp := seg_start
		seg_start = seg_end
		seg_end = temp

	if point.y < seg_start.y or point.y >= seg_end.y:
		return false

	if point.x >= maxf(seg_start.x, seg_end.x):
		return false

	if point.x < minf(seg_start.x, seg_end.x):
		return true

	var slope: float = (seg_end.x - seg_start.x) / (seg_end.y - seg_start.y) if (seg_end.y - seg_start.y) != 0.0 else 0.0
	var x_intersection: float = seg_start.x + (point.y - seg_start.y) * slope

	return point.x < x_intersection


## Get terrain height safely
func _get_terrain_height(x: float, z: float) -> float:
	if terrain_generator != null:
		return terrain_generator.get_height_at(x, z)
	return 0.0


## Step 3: Divide settlement into building zones
func _plan_building_zones() -> void:
	building_zones.clear()

	if settlement_type == "city":
		building_zones = {
			"downtown": [],  # Central commercial core
			"commercial": [],  # Commercial strips along main roads
			"residential": [],  # Residential neighborhoods
			"mixed": []  # Mixed-use areas
		}
		_plan_city_zones()
	elif settlement_type == "town":
		building_zones = {
			"town_center": [],  # Central area
			"residential": [],  # Residential areas
			"farms": []  # Outlying farms
		}
		_plan_town_zones()
	elif settlement_type == "hamlet":
		building_zones = {
			"rural": []  # Simple rural buildings
		}
		_plan_hamlet_zones()


## Plan city zones (downtown, commercial strips, residential)
func _plan_city_zones() -> void:
	var water_level: float = float(Game.sea_level)

	# Downtown: central 30% radius
	var downtown_radius: float = max_radius * 0.3
	_add_zone_in_radius("downtown", downtown_radius, water_level)

	# Commercial: 30%-60% radius along major roads
	# Residential: 60%-90% radius
	var commercial_inner: float = max_radius * 0.3
	var commercial_outer: float = max_radius * 0.6
	var residential_outer: float = max_radius * 0.9

	# Sample points in boundary
	_add_zone_in_annulus("commercial", commercial_inner, commercial_outer, water_level)
	_add_zone_in_annulus("residential", commercial_outer, residential_outer, water_level)


## Plan town zones (center + residential + farms)
func _plan_town_zones() -> void:
	var water_level: float = float(Game.sea_level)

	# Town center: central 20% radius
	var center_radius: float = max_radius * 0.2
	_add_zone_in_radius("town_center", center_radius, water_level)

	# Residential: 20%-80% radius
	_add_zone_in_annulus("residential", max_radius * 0.2, max_radius * 0.8, water_level)

	# Farms: 80%-100% radius (if on land)
	_add_zone_in_annulus("farms", max_radius * 0.8, max_radius, water_level)


## Plan hamlet zones (simple rural)
func _plan_hamlet_zones() -> void:
	var water_level: float = float(Game.sea_level)
	_add_zone_in_radius("rural", max_radius, water_level)


## Add zone within radius
func _add_zone_in_radius(zone_name: String, radius: float, water_level: float) -> void:
	var samples: int = 50
	var points: Array = []

	for _i in range(samples):
		var angle: float = randf() * TAU
		var dist: float = sqrt(randf()) * radius  # Sqrt for uniform distribution

		var x: float = settlement_center.x + cos(angle) * dist
		var z: float = settlement_center.z + sin(angle) * dist

		# Check validity
		if _is_point_in_boundary(Vector2(x, z)):
			var height: float = _get_terrain_height(x, z)
			if height > water_level + 0.5:
				points.append(Vector3(x, height, z))

	building_zones[zone_name] = points


## Add zone in annulus (ring)
func _add_zone_in_annulus(zone_name: String, inner_radius: float, outer_radius: float, water_level: float) -> void:
	var samples: int = 100
	var points: Array = []

	for _i in range(samples):
		var angle: float = randf() * TAU
		var dist: float = lerp(inner_radius, outer_radius, randf())

		var x: float = settlement_center.x + cos(angle) * dist
		var z: float = settlement_center.z + sin(angle) * dist

		# Check validity
		if _is_point_in_boundary(Vector2(x, z)):
			var height: float = _get_terrain_height(x, z)
			if height > water_level + 0.5:
				points.append(Vector3(x, height, z))

	building_zones[zone_name] = points


## Step 4: Calculate statistics
func _calculate_stats() -> void:
	terrain_stats = {
		"boundary_points": boundary_polygon.size(),
		"valid_area_m2": valid_area,
		"road_segments": road_segments.size(),
		"zone_count": building_zones.size(),
		"buildable_plots": 0
	}

	# Count total buildable plots
	for zone in building_zones.values():
		if zone is Array:
			terrain_stats.buildable_plots += zone.size()
