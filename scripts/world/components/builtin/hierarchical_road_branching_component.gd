extends WorldComponentBase
class_name HierarchicalRoadBranchingComponent

## Creates recursive branching road networks (arterials → branches → leaves)
## Generates 2000-3000 additional branching roads for organic city structure
## Priority: 57.8 (after local roads, before plots)

const RoadModule = preload("res://scripts/world/modules/road_module.gd")

func get_priority() -> int:
    return 58  # After settlement_local_roads (57)

func get_dependencies() -> Array[String]:
    return ["organic_roads", "road_density_analysis"]

func get_optional_params() -> Dictionary:
    return {
        "branch_min_length": 300.0,
        "branch_max_length": 1000.0,
        "branch_probability": 0.2,
        "max_branch_depth": 2,
        "branch_angle_variance": 60.0,
        "max_branches_per_road": 2,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("HierarchicalRoadBranchingComponent: missing ctx/terrain_generator")
        return

    if not ctx.has_data("organic_roads") or not ctx.has_data("density_grid"):
        push_warning("HierarchicalRoadBranchingComponent: missing data")
        return

    var existing_roads: Array = ctx.get_data("organic_roads")
    var density_grid: Dictionary = ctx.get_data("density_grid")
    var terrain_size: int = int(params.get("terrain_size", 4096))
    var cell_size: float = float(params.get("density_grid_cell_size", 100.0))

    # Get infrastructure layer
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var roads_root: Node3D = infra.get_node_or_null("OrganicRoadNetwork")
    if roads_root == null:
        roads_root = Node3D.new()
        roads_root.name = "OrganicRoadNetwork"
        infra.add_child(roads_root)

    var branch_mat := StandardMaterial3D.new()
    branch_mat.roughness = 0.90
    branch_mat.metallic = 0.0
    branch_mat.albedo_color = Color(0.12, 0.12, 0.13)
    branch_mat.uv1_scale = Vector3(0.7, 0.7, 0.7)

    var road_module := RoadModule.new()
    road_module.set_terrain_generator(ctx.terrain_generator)
    road_module.world_ctx = ctx

    var branch_count := 0
    var start_time := Time.get_ticks_msec()

    # Build spatial index of road endpoints for smart merging
    var road_endpoints := []
    for road in existing_roads:
        if road.path.size() >= 2:
            road_endpoints.append(road.path[0])
            road_endpoints.append(road.path[road.path.size() - 1])

    # For each existing road, generate branches along its length
    # Only branch from roads in MEDIUM-DENSITY areas (not wilderness, not dense cities)
    var roads_to_process: Array[Dictionary] = []
    for current_road in existing_roads:
        var road_type: String = current_road.get("type", "local")
        # Branch from highways/arterials in medium-density areas
        if road_type in ["highway", "arterial"]:
            # Check if road passes through medium-density area
            var mid_point: Vector3 = current_road.path[current_road.path.size() / 2] if current_road.path.size() > 0 else Vector3.ZERO
            var density := _sample_density(mid_point, density_grid, cell_size)

            # Branch from all highways/arterials to spread across map
            roads_to_process.append(current_road)

    print("🌳 HierarchicalRoadBranching: Processing ", roads_to_process.size(), " roads in medium-density areas (", existing_roads.size(), " total roads)")

    var roads_processed := 0
    for road in roads_to_process:
        roads_processed += 1

        # Progress update every 10 roads
        if roads_processed % 10 == 0:
            var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
            var avg_time := elapsed / float(roads_processed)
            var eta: float = avg_time * (roads_to_process.size() - roads_processed)
            print("   🌳 Progress: %d/%d roads (%.1fs elapsed, ~%.1fs remaining, %d branches so far)" % [
                roads_processed, roads_to_process.size(), elapsed, eta, branch_count
            ])
        var path: PackedVector3Array = road.path
        if path.size() < 2:
            continue

        # Sample density along road to determine branch frequency
        var mid_point := path[path.size() / 2]
        var density := _sample_density(mid_point, density_grid, cell_size)

        # Higher density = more branches (but less frequent than before to speed up)
        var branch_interval := 300.0 if density > 8.0 else 600.0  # Reduced branching frequency
        var branches := _generate_branches_along_road(path, branch_interval, params, rng, density, terrain_size)

        # CRITICAL: Limit branches per road to prevent explosion
        var max_branches: int = int(params.get("max_branches_per_road", 3))
        branches = branches.slice(0, min(branches.size(), max_branches))

        var branches_added_for_this_road := 0
        for branch_data in branches:
            # Recursively create branch tree (branch → sub-branch → leaf)
            # Pass road_endpoints so branches can merge
            var branch_tree := _create_branch_tree(branch_data.start, branch_data.direction, 0, params, rng, density, terrain_size, road_endpoints)

            for branch_road in branch_tree:
                # Pathfind with adaptive corridor
                var distance: float = branch_road.from.distance_to(branch_road.to)
                var corridor_multiplier: float = 1.5  # Wider corridor for problem roads
                var grid_res: float = clamp(20.0 + (distance / 80.0), 20.0, 100.0)  # Up to 100m grid for long branches

                var branch_path: PackedVector3Array = road_module.generate_road(branch_road.from, branch_road.to, {
                    "smooth": true,
                    "allow_bridges": true,
                    "grid_resolution": grid_res
                })

                if branch_path.size() < 2:
                    branch_path = PackedVector3Array([branch_road.from, branch_road.to])

                # Create mesh
                var mesh: MeshInstance3D = road_module.create_road_mesh(branch_path, branch_road.width, branch_mat)
                if mesh != null:
                    mesh.name = "BranchRoad"
                    roads_root.add_child(mesh)

                # Add to roads array
                existing_roads.append({
                    "path": branch_path,
                    "width": branch_road.width,
                    "type": "branch",
                    "from": branch_road.from,
                    "to": branch_road.to
                })
                branch_count += 1
                branches_added_for_this_road += 1

    ctx.set_data("organic_roads", existing_roads)

    var total_time := (Time.get_ticks_msec() - start_time) / 1000.0
    print("🌳 HierarchicalRoadBranching: Complete! Generated ", branch_count, " branching roads in %.1fs" % total_time)
    print("   📊 Total road network: ", existing_roads.size(), " roads (", roads_to_process.size(), " major + branches)")

func _generate_branches_along_road(path: PackedVector3Array, interval: float, params: Dictionary, rng: RandomNumberGenerator, density: float, terrain_size: int) -> Array:
    var branches := []
    var accumulated_dist := 0.0
    var sea_level: float = float(params.get("sea_level", 20.0))

    for i in range(1, path.size()):
        var p1 := path[i - 1]
        var p2 := path[i]
        var segment_length := p1.distance_to(p2)
        var segment_dir := (p2 - p1).normalized()

        var local_dist := 0.0
        while local_dist < segment_length:
            accumulated_dist += interval
            if accumulated_dist >= interval:
                accumulated_dist = 0.0

                # Branch point
                var t := local_dist / segment_length
                var branch_start := p1.lerp(p2, t)

                # Check if valid (not over water)
                var h := ctx.terrain_generator.get_height_at(branch_start.x, branch_start.z)
                if h < sea_level + 0.5:
                    local_dist += interval
                    continue

                # Probability check
                if rng.randf() > float(params.get("branch_probability", 0.7)):
                    local_dist += interval
                    continue

                # Calculate branch direction (perpendicular + variance)
                var perpendicular := Vector3(-segment_dir.z, 0, segment_dir.x)
                var side := 1 if rng.randf() < 0.5 else -1
                var angle_variance := deg_to_rad(rng.randf_range(-float(params.get("branch_angle_variance", 60.0)), float(params.get("branch_angle_variance", 60.0))))

                # Rotate perpendicular by variance
                var cos_a := cos(angle_variance)
                var sin_a := sin(angle_variance)
                var branch_dir := Vector3(
                    perpendicular.x * cos_a - perpendicular.z * sin_a,
                    0,
                    perpendicular.x * sin_a + perpendicular.z * cos_a
                ) * side

                branches.append({
                    "start": branch_start,
                    "direction": branch_dir.normalized()
                })

            local_dist += interval

    return branches

func _create_branch_tree(start: Vector3, direction: Vector3, depth: int, params: Dictionary, rng: RandomNumberGenerator, density: float, terrain_size: int, road_endpoints: Array) -> Array:
    var roads := []
    var max_depth: int = int(params.get("max_branch_depth", 3))
    var sea_level: float = float(params.get("sea_level", 20.0))

    if depth >= max_depth:
        return roads

    # Random branch length
    var min_len: float = float(params.get("branch_min_length", 100.0))
    var max_len: float = float(params.get("branch_max_length", 500.0))
    var branch_length := rng.randf_range(min_len, max_len) * (1.0 - depth * 0.3)  # Shorter at deeper levels

    var end_pos := start + direction * branch_length

    # Check if end point is valid
    if end_pos.x < 100 or end_pos.x >= terrain_size - 100 or end_pos.z < 100 or end_pos.z >= terrain_size - 100:
        return roads

    var end_height := ctx.terrain_generator.get_height_at(end_pos.x, end_pos.z)
    if end_height < sea_level + 0.5:
        return roads  # Don't branch into water

    end_pos.y = end_height

    # SMART MERGING: Check if there's an existing road endpoint nearby
    # If yes, connect to it instead of creating parallel route!
    var merge_distance: float = 150.0  # Merge within 150m
    var merge_target = _find_nearby_endpoint(end_pos, road_endpoints, merge_distance)
    if merge_target != null and merge_target is Vector3:
        end_pos = merge_target as Vector3  # Snap to existing road → T-junction!

    # Add this branch road
    var width := 7.0 - depth * 1.0  # Narrower at deeper levels (7m → 6m → 5m)
    roads.append({
        "from": start,
        "to": end_pos,
        "width": max(width, 4.0)
    })

    # Recursively create sub-branches from end point
    # CRITICAL: Much lower probability to prevent exponential explosion
    var sub_branch_prob := 0.15 - (depth * 0.05)  # 15% at depth 0, 10% at depth 1, 5% at depth 2
    if depth < max_depth - 1 and rng.randf() < sub_branch_prob:
        # Create only 1 sub-branch (never 2)
        var sub_branch_count := 1

        for i in range(sub_branch_count):
            # New direction: continue + variance
            var angle_variance := deg_to_rad(rng.randf_range(-45.0, 45.0))
            var cos_a := cos(angle_variance)
            var sin_a := sin(angle_variance)
            var new_dir := Vector3(
                direction.x * cos_a - direction.z * sin_a,
                0,
                direction.x * sin_a + direction.z * cos_a
            ).normalized()

            var sub_tree := _create_branch_tree(end_pos, new_dir, depth + 1, params, rng, density, terrain_size, road_endpoints)
            roads.append_array(sub_tree)

    return roads

func _sample_density(pos: Vector3, density_grid: Dictionary, cell_size: float) -> float:
    var cell := Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))
    if density_grid.has(cell):
        return density_grid[cell].density_score
    return 0.0

func _find_nearby_endpoint(pos: Vector3, endpoints: Array, max_distance: float) -> Variant:
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
