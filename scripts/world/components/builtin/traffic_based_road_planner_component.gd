extends WorldComponentBase
class_name TrafficBasedRoadPlannerComponent

## Replaces organic_road_network with intelligent traffic-based planning
## Calculates traffic demand, builds high-value corridors, consolidates parallel routes
## Priority: 55 (replaces organic_road_network)

const RoadModule = preload("res://scripts/world/modules/road_module.gd")

func get_priority() -> int:
    return 55

func get_dependencies() -> Array[String]:
    return ["waypoints", "heightmap"]

func get_optional_params() -> Dictionary:
    return {
        "road_merge_distance": 200.0,  # Merge parallel roads within 200m
        "min_road_value": 50.0,  # Minimum value score to keep road
        "traffic_decay_distance": 5000.0,  # Traffic demand decays with distance
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("TrafficBasedRoadPlanner: missing ctx")
        return

    var waypoints: Array = ctx.get_data("waypoints")
    if waypoints.size() < 2:
        ctx.set_data("organic_roads", [])
        return


    # PHASE 1: Calculate settlement importance (population potential)
    var importance_scores := _calculate_waypoint_importance(waypoints)

    # PHASE 2: Build traffic demand matrix (who travels where)
    var traffic_matrix := _build_traffic_demand_matrix(waypoints, importance_scores, params)

    # PHASE 3: Generate high-value corridors (sorted by traffic demand)
    var road_corridors := _generate_traffic_corridors(waypoints, traffic_matrix, params)


    # PHASE 4: Build actual roads with pathfinding + merge incentive
    var roads := _build_roads_with_merge_incentive(road_corridors, params)


    # PHASE 5: Consolidate parallel roads
    var consolidated_roads := _consolidate_parallel_roads(roads, float(params.get("road_merge_distance", 200.0)))


# PHASE 6: Value-based pruning
    var final_roads := _prune_low_value_roads(consolidated_roads, waypoints, importance_scores, params)

    # Create visual meshes using final_roads
    _create_road_meshes(final_roads, params)

    ctx.set_data("organic_roads", final_roads)
    print("🚗 TrafficBasedRoadPlanner: Complete - ", final_roads.size(), " optimized roads")

    # Print road distribution for debugging
    if final_roads.size() > 0:
        var avg_x = 0.0
        var avg_z = 0.0
        var count = 0
        for road in final_roads:
            var path: PackedVector3Array = road.path
            for point in path:
                avg_x += point.x
                avg_z += point.z
                count += 1

        if count > 0:
            avg_x /= count
            avg_z /= count
            print("   Average road position: (", avg_x, ", ", avg_z, ")")

        # Print some sample road endpoints
        print("   Sample road endpoints (first 5):")
        for i in range(min(5, final_roads.size())):
            var road = final_roads[i]
            var path: PackedVector3Array = road.path
            if path.size() >= 2:
                var start = path[0]
                var end = path[-1]  # Last element
                print("     ", i, ": from (", start.x, ", ", start.z, ") to (", end.x, ", ", end.z, ")")

func _calculate_waypoint_importance(waypoints: Array) -> Dictionary:
    # Importance = buildability + biome score + centrality
    var scores := {}

    for i in range(waypoints.size()):
        var wp: Dictionary = waypoints[i]
        var score := 0.0

        # Buildability matters
        score += wp.buildability_score * 50.0

        # Type matters (valleys/plateaus better than mountains)
        if wp.type == "valley":
            score += 30.0
        elif wp.type == "plateau":
            score += 40.0
        elif wp.type == "coast":
            score += 35.0
        elif wp.type == "mountain":
            score += 10.0

        # Centrality: waypoints near center of map = higher importance
        var terrain_size: float = float(ctx.params.get("terrain_size", 4096))
        var center: Vector3 = Vector3(0, 0, 0)  # World is centered at origin
        var dist_to_center: float = wp.position.distance_to(center)
        var centrality: float = 1.0 - (dist_to_center / (terrain_size * 0.7))
        score += centrality * 20.0

        scores[i] = max(score, 1.0)

    return scores

func _build_traffic_demand_matrix(waypoints: Array, importance_scores: Dictionary, params: Dictionary) -> Dictionary:
    # Traffic demand = (importance_A × importance_B) / distance^1.5
    # Higher importance = more people want to go there
    # Longer distance = less traffic (decay)
    var matrix := {}
    var decay_dist: float = float(params.get("traffic_decay_distance", 5000.0))

    for i in range(waypoints.size()):
        for j in range(i + 1, waypoints.size()):
            var wp_i: Dictionary = waypoints[i]
            var wp_j: Dictionary = waypoints[j]
            var dist: float = wp_i.position.distance_to(wp_j.position)

            var importance_i: float = importance_scores.get(i, 1.0)
            var importance_j: float = importance_scores.get(j, 1.0)

            # Traffic demand calculation
            var demand := (importance_i * importance_j) / pow(dist / decay_dist, 1.5)

            # Terrain cost penalty (steep = less traffic)
            var terrain_penalty := _estimate_terrain_difficulty(wp_i.position, wp_j.position)
            demand /= (1.0 + terrain_penalty * 0.3)

            matrix[Vector2i(i, j)] = {
                "demand": demand,
                "distance": dist,
                "from_idx": i,
                "to_idx": j
            }

    return matrix

func _generate_traffic_corridors(waypoints: Array, traffic_matrix: Dictionary, params: Dictionary) -> Array:
    # Sort corridors by traffic demand (high traffic = build first)
    var corridors := []
    for key in traffic_matrix:
        corridors.append(traffic_matrix[key])

    corridors.sort_custom(func(a, b): return a.demand > b.demand)

    # Take top corridors (don't build low-traffic roads)
    var max_corridors: int = min(corridors.size(), waypoints.size() * 3)  # ~3 roads per waypoint
    corridors = corridors.slice(0, max_corridors)

    # Add waypoint positions
    for corridor in corridors:
        corridor.from = waypoints[corridor.from_idx].position
        corridor.to = waypoints[corridor.to_idx].position

    return corridors

func _build_roads_with_merge_incentive(corridors: Array, params: Dictionary) -> Array:
    var roads := []
    var road_module := RoadModule.new()
    road_module.set_terrain_generator(ctx.terrain_generator)
    road_module.world_ctx = ctx

    # Build roads in order of traffic demand (high traffic first)
    for corridor in corridors:
        var distance: float = corridor.distance
        var grid_res: float = clamp(24.0 + (distance / 400.0), 24.0, 60.0)

        var path: PackedVector3Array = road_module.generate_road(corridor.from, corridor.to, {
            "smooth": true,
            "allow_bridges": true,
            "grid_resolution": grid_res
        })

        if path.size() < 2:
            path = PackedVector3Array([corridor.from, corridor.to])

        # Classify by traffic demand
        var width := 12.0
        var road_type := "arterial"
        if corridor.demand > 500.0:
            width = 24.0
            road_type = "highway"
        elif corridor.demand > 100.0:
            width = 16.0
            road_type = "arterial"
        else:
            width = 10.0
            road_type = "local"

        roads.append({
            "path": path,
            "width": width,
            "type": road_type,
            "from": corridor.from,
            "to": corridor.to,
            "demand": corridor.demand
        })

    return roads

func _consolidate_parallel_roads(roads: Array, merge_distance: float) -> Array:
    # Find roads that run parallel and merge them
    var consolidated := []
    var merged_flags := []
    merged_flags.resize(roads.size())
    merged_flags.fill(false)

    for i in range(roads.size()):
        if merged_flags[i]:
            continue

        var road_i: Dictionary = roads[i]
        var merged_with_i: bool = false

        for j in range(i + 1, roads.size()):
            if merged_flags[j]:
                continue

            var road_j: Dictionary = roads[j]

            # Check if roads are parallel (endpoints within merge_distance)
            var parallel := _are_roads_parallel(road_i, road_j, merge_distance)
            if parallel:
                # Merge road_j into road_i (use higher-demand road)
                if road_j.demand > road_i.demand:
                    road_i = road_j

                merged_flags[j] = true
                merged_with_i = true

        consolidated.append(road_i)
        merged_flags[i] = true

    return consolidated

func _prune_low_value_roads(roads: Array, waypoints: Array, importance_scores: Dictionary, params: Dictionary) -> Array:
    # Calculate value for each road: (traffic_demand × importance) / length
    var min_value: float = float(params.get("min_road_value", 50.0))
    var high_value_roads := []

    for road in roads:
        var length := _calculate_path_length(road.path)
        var demand: float = road.get("demand", 1.0)

        # Value = usefulness per unit length
        var value: float = (demand * 100.0) / max(length, 1.0)

        # Always keep highways (high demand)
        if road.type == "highway" or value >= min_value:
            high_value_roads.append(road)

    return high_value_roads

func _create_road_meshes(roads: Array, params: Dictionary) -> void:
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var roads_root := Node3D.new()
    roads_root.name = "OrganicRoadNetwork"
    
    if infra == null:
        push_error("TrafficBasedRoadPlanner: Infrastructure layer is null!")
        return
    
    infra.add_child(roads_root)

    var road_mat := StandardMaterial3D.new()
    road_mat.roughness = 0.95
    road_mat.metallic = 0.0
    road_mat.albedo_color = Color(0.2, 0.2, 0.2)
    road_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)

    var road_module := RoadModule.new()
    road_module.set_terrain_generator(ctx.terrain_generator)
    road_module.world_ctx = ctx

    for road in roads:
        var mesh: MeshInstance3D = road_module.create_road_mesh(road.path, road.width, road_mat)
        if mesh != null:
            mesh.name = road.type.capitalize() + "Road"
            roads_root.add_child(mesh)

func _estimate_terrain_difficulty(from: Vector3, to: Vector3) -> float:
    var samples := 5
    var total_difficulty := 0.0

    for i in range(samples):
        var t := i / float(samples - 1)
        var pos := from.lerp(to, t)
        var slope := ctx.terrain_generator.get_slope_at(pos.x, pos.z)
        total_difficulty += slope / 45.0  # Normalized to 0-1

    return total_difficulty / float(samples)

func _are_roads_parallel(road_a: Dictionary, road_b: Dictionary, threshold: float) -> bool:
    # Check if roads have similar start/end points (parallel routes)
    var dist_start_start: float = road_a.from.distance_to(road_b.from)
    var dist_end_end: float = road_a.to.distance_to(road_b.to)
    var dist_start_end: float = road_a.from.distance_to(road_b.to)
    var dist_end_start: float = road_a.to.distance_to(road_b.from)

    # Parallel if both endpoints are close
    if dist_start_start < threshold and dist_end_end < threshold:
        return true
    if dist_start_end < threshold and dist_end_start < threshold:
        return true

    return false

func _calculate_path_length(path: PackedVector3Array) -> float:
    var length := 0.0
    for i in range(1, path.size()):
        length += path[i].distance_to(path[i - 1])
    return length
