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
        "road_merge_distance": 80.0,  # Merge roads within 80m to avoid parallel routes
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
    var merge_distance: float = float(params.get("road_merge_distance", 80.0))

    # Build a spatial index of existing road endpoints for merging
    var road_endpoints := []
    for road in existing_roads:
        if road.path.size() >= 2:
            road_endpoints.append(road.path[0])
            road_endpoints.append(road.path[road.path.size() - 1])

    # Generate local roads for each settlement
    for settlement in settlements:
        var local_roads := _generate_settlement_roads(settlement, params, rng, terrain_size)

        # Build visual meshes and store data
        for road_data in local_roads:
            # ROAD MERGING: Check if we can connect to an existing road instead of running parallel
            var target: Vector3 = road_data.to
            var merge_point = _find_nearby_road_endpoint(target, road_endpoints, merge_distance)
            if merge_point != null and merge_point is Vector3:
                target = merge_point as Vector3  # Connect to existing road → T-junction!

            var distance: float = road_data.from.distance_to(target)
            var grid_res: float = clamp(16.0 + (distance / 100.0), 16.0, 100.0)  # Scale up to 100m for long local roads

            var path: PackedVector3Array = road_module.generate_road(road_data.from, target, {
                "smooth": true,
                "allow_bridges": true,
                "grid_resolution": grid_res
            })

            if path.size() < 2:
                path = PackedVector3Array([road_data.from, road_data.to])

            # Use the road module for local roads to ensure consistency with carving
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
                "to": target
            })

            # Add new endpoints to spatial index for future merging
            if path.size() >= 2:
                road_endpoints.append(path[0])
                road_endpoints.append(path[path.size() - 1])

            local_roads_count += 1

    # REMOVED: Random exploration roads - they covered the map without purpose
    # Citizens need roads that GO somewhere (settlement to settlement), not random coverage

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

    # DENSE roads inside settlements - people live here!
    match density_class:
        "urban_core":
            spacing = float(params.get("local_roads_urban_core_spacing", 80.0))
            waypoint_count = 25  # VERY dense - big city needs lots of streets
            use_grid = rng.randf() < 0.4  # 40% chance of grid
        "urban":
            spacing = float(params.get("local_roads_urban_spacing", 120.0))
            waypoint_count = 15  # Medium density town
            use_grid = rng.randf() < 0.2  # 20% chance of grid
        "suburban":
            spacing = float(params.get("local_roads_suburban_spacing", 180.0))
            waypoint_count = 8  # Suburban neighborhoods
        _:  # rural
            spacing = float(params.get("local_roads_rural_spacing", 300.0))
            waypoint_count = 4  # Just a few roads in hamlets

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

    # Connect each waypoint to nearest neighbors - MORE connections = denser streets
    for i in range(waypoints.size()):
        var wp_i: Vector3 = waypoints[i]

        # Find nearest neighbors
        var neighbors := []
        for j in range(waypoints.size()):
            if i == j:
                continue
            var wp_j: Vector3 = waypoints[j]
            var dist: float = wp_i.distance_to(wp_j)
            neighbors.append({"idx": j, "dist": dist, "pos": wp_j})

        neighbors.sort_custom(func(a, b): return a.dist < b.dist)

        # Connect to MORE neighbors in dense areas - creates interconnected streets
        var connect_count := 2
        if density_class == "urban_core":
            connect_count = 4  # Each waypoint connects to 4 others → dense grid
        elif density_class == "urban":
            connect_count = 3  # Medium density
        elif density_class == "suburban":
            connect_count = 3
        else:  # rural
            connect_count = 2
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
    # Check bounds (world is centered at origin, so coordinates range from -terrain_size/2 to terrain_size/2)
    var half_size: float = float(terrain_size) / 2.0
    var margin: float = 100.0
    if pos.x < -half_size + margin or pos.x >= half_size - margin or pos.z < -half_size + margin or pos.z >= half_size - margin:
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

func _find_nearby_road_endpoint(pos: Vector3, endpoints: Array, max_distance: float) -> Variant:
    # Find closest existing road endpoint within max_distance
    # Returns the endpoint position if found, null otherwise
    var closest_endpoint = null
    var closest_dist := max_distance

    for endpoint in endpoints:
        var dist := pos.distance_to(endpoint)
        if dist < closest_dist and dist > 10.0:  # Ignore if too close (same point)
            closest_dist = dist
            closest_endpoint = endpoint

    return closest_endpoint
