extends WorldComponentBase
class_name MasterRoadsComponent

## Unified road generation using RoadMasterPlanner
## Replaces: regional_roads, road_network, settlement_roads
## Uses build → test → refine strategy

func get_priority() -> int:
	return 56  # After settlements (55), before buildings (65)

func get_dependencies() -> Array[String]:
	return ["settlements"]

func get_optional_params() -> Dictionary:
	return {
		"enable_master_roads": true,
		"trunk_highway_width": 24.0,
		"arterial_road_width": 16.0,
		"country_lane_width": 10.0,
		"settlement_road_width": 10.0,
		"city_road_spacing": 60.0,
		"town_spoke_count": 8,
		"town_ring_radius_ratio": 0.70,
		"city_inner_ring_ratio": 0.4,
		"city_outer_ring_ratio": 0.75,
		"coastline_access_points": 8,
		"farm_lane_count": 20,
		"farm_band": 2600.0,
		"bridge_clearance": 15.0,
		"road_terrain_offset": 1.2,
		"road_merge_threshold": 50.0,
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if not bool(params.get("enable_master_roads", true)):
		return

	if ctx == null or ctx.terrain_generator == null:
		push_error("MasterRoadsComponent: missing ctx or terrain_generator")
		return

	if ctx.settlements.is_empty():
		push_warning("MasterRoadsComponent: no settlements to connect")
		return

	print("🚧 MasterRoadsComponent: Starting unified road planning...")

	# Create master planner
	var planner := RoadMasterPlanner.new()
	planner.terrain_generator = ctx.terrain_generator
	planner.bridge_clearance = float(params.get("bridge_clearance", 15.0))
	planner.road_terrain_offset = float(params.get("road_terrain_offset", 1.2))
	planner.merge_threshold = float(params.get("road_merge_threshold", 50.0))

	var roads_root := Node3D.new()
	roads_root.name = "MasterRoads"
	ctx.get_layer("Infrastructure").add_child(roads_root)

	# Materials
	var highway_mat := _create_road_material(Color(0.12, 0.12, 0.13))
	var arterial_mat := _create_road_material(Color(0.10, 0.10, 0.11))
	var lane_mat := _create_road_material(Color(0.09, 0.09, 0.10))
	var settlement_mat := _create_road_material(Color(0.08, 0.08, 0.09))

	# PHASE 1: COLLECT - Submit all road requests
	_collect_regional_highways(planner, params, highway_mat, arterial_mat, rng)
	_collect_country_lanes(planner, params, lane_mat, rng)
	_collect_settlement_roads(planner, params, settlement_mat, rng)
	_collect_boat_spawn_zones(planner)

	# PHASE 2: ANALYZE
	var analysis: Dictionary = planner.analyze_network()

	# PHASE 3: OPTIMIZE
	planner.optimize_network()

	# PHASE 4: BUILD
	var result: Dictionary = planner.build_network(roads_root)

	# Store results for other components
	ctx.set_data("master_roads", result.roads)
	ctx.set_data("bridge_exclusion_zones", result.exclusion_zones)
	ctx.set_data("water_crossings", result.water_crossings)

	print("✅ MasterRoadsComponent: Built %d optimized roads" % result.roads.size())


## Collect regional highway requests (MST-based trunk network)
func _collect_regional_highways(planner: RoadMasterPlanner, params: Dictionary, highway_mat: Material, arterial_mat: Material, rng: RandomNumberGenerator) -> void:
	var destinations: Array = _gather_destinations(params, rng)

	# Filter major destinations (cities, towns)
	var major_dests: Array = []
	for dest in destinations:
		if dest is Dictionary and dest.get("priority", 999) <= 2:
			major_dests.append(dest)

	if major_dests.size() < 2:
		return

	# Build MST edges
	var mst_edges: Array = _build_mst(major_dests)
	var all_edges: Array = _build_all_edges(major_dests)
	var target_count: int = int(float(mst_edges.size()) * 2.5)
	var final_edges: Array = _add_best_edges(mst_edges, all_edges, target_count)

	# Submit highway requests
	var highway_width: float = float(params.get("trunk_highway_width", 24.0))
	for edge in final_edges:
		planner.request_highway(edge.from, edge.to, highway_width, highway_mat, 10)

	# Arterial branches to secondary destinations
	var arterial_width: float = float(params.get("arterial_road_width", 16.0))
	for dest in destinations:
		if dest is Dictionary and dest.get("priority", 999) == 3:
			var pos: Vector3 = dest.get("position", Vector3.ZERO)
			var nearest: Vector3 = _find_nearest_destination(pos, major_dests)
			if nearest != Vector3.ZERO:
				planner.request_arterial(nearest, pos, arterial_width, arterial_mat, 8)


## Collect country lane requests (farms, coastlines)
func _collect_country_lanes(planner: RoadMasterPlanner, params: Dictionary, lane_mat: Material, rng: RandomNumberGenerator) -> void:
	var destinations: Array = _gather_destinations(params, rng)
	var lane_width: float = float(params.get("country_lane_width", 10.0))

	# Rural destinations (priority 4+)
	for dest in destinations:
		if dest is Dictionary and dest.get("priority", 999) >= 4:
			var pos: Vector3 = dest.get("position", Vector3.ZERO)
			# Find nearest major destination to connect from
			var nearest: Vector3 = _find_nearest_destination(pos, destinations)
			if nearest != Vector3.ZERO and nearest.distance_to(pos) > 100.0:
				planner.request_lane(nearest, pos, lane_width, lane_mat, 5)


## Collect settlement road requests (city grids, town spokes, rings)
func _collect_settlement_roads(planner: RoadMasterPlanner, params: Dictionary, settlement_mat: Material, rng: RandomNumberGenerator) -> void:
	var road_width: float = float(params.get("settlement_road_width", 10.0))
	var city_spacing: float = float(params.get("city_road_spacing", 60.0))
	var town_spokes: int = int(params.get("town_spoke_count", 8))
	var ring_ratio: float = float(params.get("town_ring_radius_ratio", 0.70))
	var inner_ring_ratio: float = float(params.get("city_inner_ring_ratio", 0.4))
	var outer_ring_ratio: float = float(params.get("city_outer_ring_ratio", 0.75))

	for settlement in ctx.settlements:
		if not (settlement is Dictionary):
			continue

		var s_type: String = str(settlement.get("type", ""))
		var center: Vector3 = settlement.get("center", Vector3.ZERO)
		var radius: float = settlement.get("radius", 200.0)

		if s_type == "hamlet" or s_type == "industry":
			continue  # Too small for internal roads

		var settlement_name: String = "%s_%d" % [s_type, rng.randi()]

		if s_type == "city":
			_request_city_roads(planner, center, radius, city_spacing, inner_ring_ratio, outer_ring_ratio, road_width, settlement_mat, settlement_name)
		elif s_type == "town":
			_request_town_roads(planner, center, radius, town_spokes, ring_ratio, road_width, settlement_mat, settlement_name)


func _request_city_roads(planner: RoadMasterPlanner, center: Vector3, radius: float, spacing: float, inner_ratio: float, outer_ratio: float, width: float, mat: Material, name: String) -> void:
	var road_extent: float = radius * 0.85
	var count: int = int(road_extent * 2.0 / spacing)

	# North-south grid roads
	for i in range(-count/2, count/2 + 1):
		var x: float = center.x + float(i) * spacing
		var road_offset: float = abs(float(i) * spacing)
		if road_offset > road_extent:
			continue

		var max_z: float = sqrt(road_extent * road_extent - road_offset * road_offset)
		var start := Vector3(x, 0, center.z - max_z)
		var end := Vector3(x, 0, center.z + max_z)

		planner.request_settlement_road(start, end, width, mat, name, 7)

	# East-west grid roads
	for j in range(-count/2, count/2 + 1):
		var z: float = center.z + float(j) * spacing
		var road_offset: float = abs(float(j) * spacing)
		if road_offset > road_extent:
			continue

		var max_x: float = sqrt(road_extent * road_extent - road_offset * road_offset)
		var start := Vector3(center.x - max_x, 0, z)
		var end := Vector3(center.x + max_x, 0, z)

		planner.request_settlement_road(start, end, width, mat, name, 7)

	# Ring roads
	_request_ring_road(planner, center, radius * inner_ratio, 32, width, mat, name)
	_request_ring_road(planner, center, radius * outer_ratio, 48, width * 1.1, mat, name)


func _request_town_roads(planner: RoadMasterPlanner, center: Vector3, radius: float, spoke_count: int, ring_ratio: float, width: float, mat: Material, name: String) -> void:
	var spoke_extent: float = radius * 0.9

	# Radial spokes
	for i in range(spoke_count):
		var angle: float = float(i) * TAU / float(spoke_count)
		var end_x: float = center.x + cos(angle) * spoke_extent
		var end_z: float = center.z + sin(angle) * spoke_extent
		var end := Vector3(end_x, 0, end_z)

		planner.request_settlement_road(center, end, width * 0.85, mat, name, 7)

	# Ring road
	_request_ring_road(planner, center, radius * ring_ratio, 24, width * 0.75, mat, name)


func _request_ring_road(planner: RoadMasterPlanner, center: Vector3, radius: float, segments: int, width: float, mat: Material, name: String) -> void:
	for i in range(segments):
		var angle1: float = float(i) * TAU / float(segments)
		var angle2: float = float(i + 1) * TAU / float(segments)

		var p1 := Vector3(center.x + cos(angle1) * radius, 0, center.z + sin(angle1) * radius)
		var p2 := Vector3(center.x + cos(angle2) * radius, 0, center.z + sin(angle2) * radius)

		planner.request_settlement_road(p1, p2, width, mat, name, 7)


## Collect boat spawn zones to exclude
func _collect_boat_spawn_zones(planner: RoadMasterPlanner) -> void:
	# TODO: Query where boats will spawn from ocean/lake features
	# For now, assume boats spawn near coastlines at water level
	pass


## Helper: Gather all road destinations
func _gather_destinations(params: Dictionary, rng: RandomNumberGenerator) -> Array:
	var dests: Array = []

	# Settlements
	for settlement in ctx.settlements:
		if settlement is Dictionary:
			var s_type: String = settlement.get("type", "")
			var priority: int = 1 if s_type == "city" else 2 if s_type == "town" else 3
			dests.append({
				"type": "settlement",
				"subtype": s_type,
				"position": settlement.get("center", Vector3.ZERO),
				"priority": priority
			})

	# Coastlines
	var coast_count: int = int(params.get("coastline_access_points", 8))
	var terrain_size: float = float(Game.settings.get("terrain_size", 6000.0))
	var half_size: float = terrain_size * 0.5

	for i in range(coast_count):
		var angle: float = float(i) * TAU / float(coast_count) + rng.randf_range(-0.2, 0.2)
		var dist: float = half_size * 0.9
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var h: float = ctx.terrain_generator.get_height_at(x, z)

		if h < float(Game.sea_level) + 5.0:
			dests.append({
				"type": "coastline",
				"position": Vector3(x, h, z),
				"priority": 4
			})

	# Landmarks
	if ctx.has_data("landmarks"):
		var landmarks: Array = ctx.get_data("landmarks")
		for landmark in landmarks:
			if landmark is Dictionary:
				dests.append({
					"type": "landmark",
					"position": landmark.get("position", Vector3.ZERO),
					"priority": 3
				})

	# Farm areas
	var farm_band: float = float(params.get("farm_band", 2600.0))
	var farm_lane_count: int = int(params.get("farm_lane_count", 20))

	for settlement in ctx.settlements:
		if not (settlement is Dictionary):
			continue

		var s_type: String = settlement.get("type", "")
		if s_type == "industry":
			continue

		var center: Vector3 = settlement.get("center", Vector3.ZERO)
		var radius: float = settlement.get("radius", 350.0)
		var zones: Dictionary = settlement.get("zones", {}) as Dictionary
		var suburb_r: float = float(zones.get("suburb_radius", radius * 1.25))

		var inner: float = maxf(suburb_r, radius) + 120.0
		var outer: float = inner + farm_band
		var lanes_per_settlement: int = maxi(2, farm_lane_count / maxi(1, ctx.settlements.size()))

		for i in range(lanes_per_settlement):
			var ang: float = float(i) * TAU / float(lanes_per_settlement) + rng.randf_range(-0.3, 0.3)
			var rr: float = inner + rng.randf_range(0.3, 0.8) * (outer - inner)
			var x: float = center.x + cos(ang) * rr
			var z: float = center.z + sin(ang) * rr
			var h: float = ctx.terrain_generator.get_height_at(x, z)

			if h > float(Game.sea_level) + 1.0:
				var slope: float = ctx.terrain_generator.get_slope_at(x, z)
				if slope < 15.0:
					dests.append({
						"type": "farm",
						"position": Vector3(x, h, z),
						"priority": 5
					})

	return dests


## Helper: Build MST
func _build_mst(destinations: Array) -> Array:
	var all_edges: Array = _build_all_edges(destinations)
	all_edges.sort_custom(func(a, b): return a.weight < b.weight)

	var parent: Array = []
	parent.resize(destinations.size())
	for i in range(destinations.size()):
		parent[i] = i

	var find_root = func(x: int) -> int:
		while parent[x] != x:
			x = parent[x]
		return x

	var mst: Array = []
	for edge in all_edges:
		var rx: int = find_root.call(edge.from_idx)
		var ry: int = find_root.call(edge.to_idx)
		if rx != ry:
			mst.append(edge)
			parent[rx] = ry
			if mst.size() >= destinations.size() - 1:
				break

	return mst


func _build_all_edges(destinations: Array) -> Array:
	var edges: Array = []
	for i in range(destinations.size()):
		var di: Dictionary = destinations[i] as Dictionary
		var pi: Vector3 = di.get("position", Vector3.ZERO)
		for j in range(i + 1, destinations.size()):
			var dj: Dictionary = destinations[j] as Dictionary
			var pj: Vector3 = dj.get("position", Vector3.ZERO)
			var dist: float = pi.distance_to(pj)
			edges.append({
				"from": pi,
				"to": pj,
				"weight": dist,
				"from_idx": i,
				"to_idx": j
			})
	return edges


func _add_best_edges(mst: Array, all_edges: Array, target: int) -> Array:
	var final: Array = mst.duplicate()
	var existing: Dictionary = {}

	for e in final:
		var key: String = "%d_%d" % [e.from_idx, e.to_idx]
		existing[key] = true

	var remaining: Array = []
	for e in all_edges:
		var key: String = "%d_%d" % [e.from_idx, e.to_idx]
		if not existing.has(key):
			remaining.append(e)

	remaining.sort_custom(func(a, b): return a.weight < b.weight)

	for e in remaining:
		if final.size() >= target:
			break
		final.append(e)

	return final


func _find_nearest_destination(pos: Vector3, destinations: Array) -> Vector3:
	var nearest: Vector3 = Vector3.ZERO
	var min_dist: float = INF

	for dest in destinations:
		if not dest is Dictionary:
			continue
		var dest_pos: Vector3 = dest.get("position", Vector3.ZERO)
		var dist: float = pos.distance_to(dest_pos)
		if dist < min_dist:
			min_dist = dist
			nearest = dest_pos

	return nearest


func _create_road_material(color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.metallic = 0.05
	return mat
