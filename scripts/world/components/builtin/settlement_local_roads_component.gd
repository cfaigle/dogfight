extends WorldComponentBase
class_name SettlementLocalRoadsComponent

## Generates dense local road networks within settlements
## Creates 1500-2000 additional local roads for urban density
## Priority: 57.5 (after density analysis, before plot generation)

const RoadModule = preload("res://scripts/world/modules/road_module.gd")

func get_priority() -> int:
	return 57  # Between density (56) and plots (57) - actually will be 57.5

func get_dependencies() -> Array[String]:
	return ["organic_roads", "road_density_analysis"]

func get_optional_params() -> Dictionary:
	return {
		"local_roads_urban_core_spacing": 80.0,
		"local_roads_urban_spacing": 120.0,
		"local_roads_suburban_spacing": 180.0,
		"local_roads_rural_spacing": 300.0,
		"random_road_count": 100,  # Extra random exploration roads
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if ctx == null or ctx.terrain_generator == null:
		push_error("SettlementLocalRoadsComponent: missing ctx/terrain_generator")
		return

	if not ctx.has_data("organic_roads") or not ctx.has_data("emergent_settlements"):
		push_warning("SettlementLocalRoadsComponent: missing data")
		return

	var existing_roads: Array = ctx.get_data("organic_roads")
	var settlements: Array = ctx.get_data("emergent_settlements")
	var terrain_size: int = int(params.get("terrain_size", 4096))

	# Get infrastructure layer and road visual root
	var infra: Node3D = ctx.get_layer("Infrastructure")
	var roads_root: Node3D = infra.get_node_or_null("OrganicRoadNetwork")
	if roads_root == null:
		roads_root = Node3D.new()
		roads_root.name = "OrganicRoadNetwork"
		infra.add_child(roads_root)

	# Material for local roads (slightly different from highways)
	var local_mat := StandardMaterial3D.new()
	local_mat.roughness = 0.92
	local_mat.metallic = 0.0
	local_mat.albedo_color = Color(0.1, 0.1, 0.11)  # Slightly lighter than highways
	local_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)

	var road_module := RoadModule.new()
	road_module.set_terrain_generator(ctx.terrain_generator)
	road_module.world_ctx = ctx

	var local_roads_count := 0

	# Generate local roads for each settlement
	for settlement in settlements:
		var local_roads := _generate_settlement_roads(settlement, params, rng, terrain_size)

		# Build visual meshes and store data
		for road_data in local_roads:
			var path: PackedVector3Array = road_module.generate_road(road_data.from, road_data.to, {
				"smooth": true,
				"allow_bridges": true,
				"grid_resolution": 16.0  # Finer grid for local roads
			})

			if path.size() < 2:
				path = PackedVector3Array([road_data.from, road_data.to])

			# Create visual mesh
			var mesh: MeshInstance3D = road_module.create_road_mesh(path, road_data.width, local_mat)
			if mesh != null:
				mesh.name = "LocalRoad"
				roads_root.add_child(mesh)

			# Add to roads array
			existing_roads.append({
				"path": path,
				"width": road_data.width,
				"type": "local",
				"from": road_data.from,
				"to": road_data.to
			})
			local_roads_count += 1

	# Add random exploration roads throughout map
	var random_roads := _generate_random_exploration_roads(int(params.get("random_road_count", 100)), terrain_size, params, rng)
	for road_data in random_roads:
		var path: PackedVector3Array = road_module.generate_road(road_data.from, road_data.to, {
			"smooth": true,
			"allow_bridges": true,
			"grid_resolution": 20.0
		})

		if path.size() < 2:
			path = PackedVector3Array([road_data.from, road_data.to])

		var mesh: MeshInstance3D = road_module.create_road_mesh(path, road_data.width, local_mat)
		if mesh != null:
			mesh.name = "ExplorationRoad"
			roads_root.add_child(mesh)

		existing_roads.append({
			"path": path,
			"width": road_data.width,
			"type": "local",
			"from": road_data.from,
			"to": road_data.to
		})
		local_roads_count += 1

	# Update organic_roads with expanded network
	ctx.set_data("organic_roads", existing_roads)
	print("SettlementLocalRoads: Generated ", local_roads_count, " local roads across ", settlements.size(), " settlements")

func _generate_settlement_roads(settlement: Dictionary, params: Dictionary, rng: RandomNumberGenerator, terrain_size: int) -> Array:
	var roads := []
	var center: Vector3 = settlement.center
	var radius: float = settlement.radius
	var density_class: String = settlement.density_class
	var sea_level: float = float(params.get("sea_level", 20.0))

	# Determine local waypoint spacing and count based on density
	var spacing: float
	var waypoint_count: int
	var use_grid := false

	match density_class:
		"urban_core":
			spacing = float(params.get("local_roads_urban_core_spacing", 80.0))
			waypoint_count = 16  # Dense network
			use_grid = rng.randf() < 0.3  # 30% chance of small grid
		"urban":
			spacing = float(params.get("local_roads_urban_spacing", 120.0))
			waypoint_count = 10
			use_grid = rng.randf() < 0.15  # 15% chance of grid
		"suburban":
			spacing = float(params.get("local_roads_suburban_spacing", 180.0))
			waypoint_count = 6
		_:  # rural
			spacing = float(params.get("local_roads_rural_spacing", 300.0))
			waypoint_count = 3

	# Generate local waypoints
	var waypoints := []

	if use_grid and density_class in ["urban_core", "urban"]:
		# Small grid pattern (3x3 or 2x2)
		var grid_size := 3 if density_class == "urban_core" else 2
		var grid_spacing := spacing
		var grid_offset := -float(grid_size - 1) * grid_spacing * 0.5

		for gx in range(grid_size):
			for gz in range(grid_size):
				var pos := center + Vector3(grid_offset + gx * grid_spacing, 0, grid_offset + gz * grid_spacing)

				# Check if valid (not over water, in bounds)
				if _is_valid_waypoint(pos, terrain_size, sea_level):
					var h := ctx.terrain_generator.get_height_at(pos.x, pos.z)
					waypoints.append(Vector3(pos.x, h, pos.z))
	else:
		# Organic scattered waypoints
		for i in range(waypoint_count):
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(spacing * 0.3, radius * 0.8)
			var pos := center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

			if _is_valid_waypoint(pos, terrain_size, sea_level):
				var h := ctx.terrain_generator.get_height_at(pos.x, pos.z)
				waypoints.append(Vector3(pos.x, h, pos.z))

	# Connect waypoints with local roads
	if waypoints.size() < 2:
		return roads

	# Connect each waypoint to nearest neighbors
	for i in range(waypoints.size()):
		var wp_i: Vector3 = waypoints[i]

		# Find 2-3 nearest neighbors
		var neighbors := []
		for j in range(waypoints.size()):
			if i == j:
				continue
			var wp_j: Vector3 = waypoints[j]
			var dist: float = wp_i.distance_to(wp_j)
			neighbors.append({"idx": j, "dist": dist, "pos": wp_j})

		neighbors.sort_custom(func(a, b): return a.dist < b.dist)

		# Connect to 2-3 nearest (creates organic network)
		var connect_count := 2 if density_class == "rural" else 3
		for n_idx in range(min(connect_count, neighbors.size())):
			var neighbor = neighbors[n_idx]
			if i < neighbor.idx:  # Avoid duplicates
				roads.append({
					"from": wp_i,
					"to": neighbor.pos,
					"width": 7.0 if density_class in ["urban_core", "urban"] else 6.0
				})

	return roads

func _generate_random_exploration_roads(count: int, terrain_size: int, params: Dictionary, rng: RandomNumberGenerator) -> Array:
	var roads := []
	var sea_level: float = float(params.get("sea_level", 20.0))

	# Generate random points that are interesting (varied height, not water)
	var interesting_points := []
	var attempts := 0
	while interesting_points.size() < count * 2 and attempts < count * 5:
		attempts += 1
		var x := rng.randf_range(terrain_size * 0.1, terrain_size * 0.9)
		var z := rng.randf_range(terrain_size * 0.1, terrain_size * 0.9)
		var h := ctx.terrain_generator.get_height_at(x, z)

		if h > sea_level + 2.0:  # Not water
			var slope := ctx.terrain_generator.get_slope_at(x, z)
			if slope < 35.0:  # Buildable
				interesting_points.append(Vector3(x, h, z))

	# Connect random pairs of interesting points
	for i in range(0, min(count, interesting_points.size() / 2) * 2, 2):
		if i + 1 < interesting_points.size():
			roads.append({
				"from": interesting_points[i],
				"to": interesting_points[i + 1],
				"width": 8.0
			})

	return roads

func _is_valid_waypoint(pos: Vector3, terrain_size: int, sea_level: float) -> bool:
	# Check bounds
	if pos.x < 100 or pos.x >= terrain_size - 100 or pos.z < 100 or pos.z >= terrain_size - 100:
		return false

	# Check not over water - CRITICAL!
	var h := ctx.terrain_generator.get_height_at(pos.x, pos.z)
	if h < sea_level + 0.5:
		return false

	# Check slope not too steep
	var slope := ctx.terrain_generator.get_slope_at(pos.x, pos.z)
	if slope > 30.0:
		return false

	return true
