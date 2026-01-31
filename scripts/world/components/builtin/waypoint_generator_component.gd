extends WorldComponentBase
class_name WaypointGeneratorComponent

## Identifies interesting terrain features (valleys, plateaus, coasts) that roads should connect
## Priority: 54 (after landmarks, before roads)

func get_priority() -> int:
    return 54

func get_dependencies() -> Array[String]:
    return ["heightmap", "biomes"]

func get_optional_params() -> Dictionary:
    return {
        "terrain_size": 1000.0,
        "waypoint_count": 250,
        "waypoint_coastal_count": 30,
        "waypoint_min_spacing": 400.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("WaypointGeneratorComponent: missing ctx/terrain_generator")
        return

    var terrain_size: int = int(params.get("terrain_size", 1000))
    print("   📍 WaypointGenerator: terrain_size = ", terrain_size)
    var sample_spacing: float = 200.0  # Sample every 200m

    # Sample terrain features on coarse grid
    var samples := _sample_terrain_features(terrain_size, sample_spacing, params)

    # Identify different waypoint types
    var valley_waypoints := _identify_valleys(samples, terrain_size)
    var plateau_waypoints := _identify_plateaus(samples)
    var mountain_waypoints := _identify_mountains(samples, terrain_size)  # NEW!
    var coastal_waypoints := _identify_coastal_nodes(terrain_size, params)
    var transition_waypoints := _identify_biome_transitions(samples, terrain_size)

    # Combine and score all waypoints
    var all_waypoints: Array = []
    all_waypoints.append_array(valley_waypoints)
    all_waypoints.append_array(plateau_waypoints)
    all_waypoints.append_array(mountain_waypoints)
    all_waypoints.append_array(coastal_waypoints)
    all_waypoints.append_array(transition_waypoints)

    print("   ⛰️ Found %d valleys, %d mountains, %d plateaus" % [
        valley_waypoints.size(), mountain_waypoints.size(), plateau_waypoints.size()
    ])

    # Add player spawn as high-priority waypoint
    var player_spawn := ctx.runway_spawn
    if player_spawn != Vector3.ZERO:
        all_waypoints.append({
            "position": player_spawn,
            "type": "spawn",
            "priority": 100,
            "biome": "grassland",
            "buildability_score": 1.0
        })

    # Print waypoint distribution for debugging
    print("📍 WaypointGenerator: Raw waypoint counts:")
    var valley_count = 0
    var plateau_count = 0
    var mountain_count = 0
    var coastal_count = 0
    var transition_count = 0
    var spawn_count = 0

    for wp in all_waypoints:
        match wp.type:
            "valley": valley_count += 1
            "plateau": plateau_count += 1
            "mountain": mountain_count += 1
            "coast": coastal_count += 1
            "transition": transition_count += 1
            "spawn": spawn_count += 1

    print("   Valleys: ", valley_count, " Plateaus: ", plateau_count, " Mountains: ", mountain_count)
    print("   Coastal: ", coastal_count, " Transitions: ", transition_count, " Spawn: ", spawn_count)

    # Print some sample positions to check distribution
    print("   Sample waypoint positions (first 10):")
    for i in range(min(10, all_waypoints.size())):
        var wp = all_waypoints[i]
        print("     ", i, ": type='", wp.type, "' pos=(", wp.position.x, ", ", wp.position.z, ")")

    # Filter by minimum spacing and select top waypoints
    var min_spacing: float = float(params.get("waypoint_min_spacing", 500.0))
    var target_count: int = int(params.get("waypoint_count", 30))
    var filtered_waypoints := _filter_by_spacing(all_waypoints, min_spacing, target_count)

    ctx.set_data("waypoints", filtered_waypoints)
    print("WaypointGenerator: Generated ", filtered_waypoints.size(), " waypoints after filtering")

    # Print final waypoint distribution
    print("   Final waypoint distribution (first 10):")
    for i in range(min(10, filtered_waypoints.size())):
        var wp = filtered_waypoints[i]
        print("     ", i, ": type='", wp.type, "' pos=(", wp.position.x, ", ", wp.position.z, ")")

func _sample_terrain_features(terrain_size: int, spacing: float, params: Dictionary) -> Array:
    var samples: Array = []
    var sea_level: float = float(params.get("sea_level", 20.0))

    # Terrain is centered at origin, so sample from -half to +half
    var half: float = terrain_size * 0.5
    for x in range(-int(half), int(half), int(spacing)):
        for z in range(-int(half), int(half), int(spacing)):
            var pos := Vector3(x, 0, z)
            var height := ctx.terrain_generator.get_height_at(x, z)

            if height < sea_level + 1.0:
                continue  # Skip underwater points

            pos.y = height
            var slope := ctx.terrain_generator.get_slope_at(x, z)
            var curvature := _calculate_curvature(x, z, spacing * 0.5)
            var biome := _sample_biome(x, z, terrain_size)

            samples.append({
                "position": pos,
                "height": height,
                "slope": slope,
                "curvature": curvature,
                "biome": biome
            })

    return samples

func _identify_valleys(samples: Array, terrain_size: int) -> Array:
    var waypoints: Array = []
    var sea_level: float = float(ctx.params.get("sea_level", 0.0))
    var terrain_amp: float = float(ctx.params.get("terrain_amp", 300.0))
    var valley_threshold := sea_level + (terrain_amp * 0.5)  # 50% above sea level

    for sample in samples:
        # Valleys: lower than surroundings, gentle slope
        if sample.slope < 35.0 and sample.height < valley_threshold:
            var is_local_min := _is_local_minimum(sample.position, 400.0)
            if is_local_min:
                var buildability := _calculate_buildability(sample.slope, sample.height)
                if buildability > 0.1:  # Very permissive
                    waypoints.append({
                        "position": sample.position,
                        "type": "valley",
                        "priority": 8,
                        "biome": sample.biome,
                        "buildability_score": buildability
                    })

    return waypoints

func _identify_plateaus(samples: Array) -> Array:
    var waypoints: Array = []

    for sample in samples:
        # Plateaus have low slope and low curvature (flat areas)
        if sample.slope < 25.0 and abs(sample.curvature) < 0.6:
            var buildability := _calculate_buildability(sample.slope, sample.height)
            if buildability > 0.15:  # Very permissive
                waypoints.append({
                    "position": sample.position,
                    "type": "plateau",
                    "priority": 10,
                    "biome": sample.biome,
                    "buildability_score": buildability
                })

    return waypoints

func _identify_mountains(samples: Array, terrain_size: int) -> Array:
    var waypoints: Array = []

    # Sort samples by height to find high points
    var sorted_samples := samples.duplicate()
    sorted_samples.sort_custom(func(a, b): return a.height > b.height)

    # Take top 10% as potential mountain candidates
    var mountain_candidates := sorted_samples.slice(0, max(40, sorted_samples.size() / 10))

    for sample in mountain_candidates:
        # Mountains: highest points with moderate slope
        if sample.slope < 35.0:
            var is_local_max := _is_local_maximum(sample.position, terrain_size, 400.0)
            if is_local_max:
                var buildability := _calculate_buildability(sample.slope, sample.height)
                if buildability > 0.2:  # Can tolerate steeper slopes
                    waypoints.append({
                        "position": sample.position,
                        "type": "mountain",
                        "priority": 9,  # High priority
                        "biome": sample.biome,
                        "buildability_score": buildability
                    })

    return waypoints

func _identify_coastal_nodes(terrain_size: int, params: Dictionary) -> Array:
    var waypoints: Array = []
    var sea_level: float = float(params.get("sea_level", 20.0))
    var target_count: int = int(params.get("waypoint_coastal_count", 10))
    var step := terrain_size / maxi(target_count, 4)

    # Sample perimeter of terrain (corrected for centered world coordinates)
    var half_size: float = float(terrain_size) / 2.0
    var step_count: int = int(terrain_size / step)

    # Sample bottom and top edges (x varies, z is constant)
    for i in range(step_count + 1):
        var x_coord: float = -half_size + (float(i) / float(step_count)) * float(terrain_size)

        var positions_x := [
            Vector2(x_coord, -half_size),  # Bottom edge: x varies, z = -half_size
            Vector2(x_coord, half_size)    # Top edge: x varies, z = +half_size
        ]

        for pos_2d in positions_x:
            var height := ctx.terrain_generator.get_height_at(pos_2d.x, pos_2d.y)
            if height > sea_level + 1.0 and height < sea_level + 20.0:
                var slope := ctx.terrain_generator.get_slope_at(pos_2d.x, pos_2d.y)
                if slope < 25.0:
                    waypoints.append({
                        "position": Vector3(pos_2d.x, height, pos_2d.y),
                        "type": "coast",
                        "priority": 7,
                        "biome": "coast",
                        "buildability_score": 0.8
                    })

    # Sample left and right edges (z varies, x is constant)
    for i in range(step_count + 1):
        var z_coord: float = -half_size + (float(i) / float(step_count)) * float(terrain_size)

        var positions_z := [
            Vector2(-half_size, z_coord),  # Left edge: x = -half_size, z varies
            Vector2(half_size, z_coord)    # Right edge: x = +half_size, z varies
        ]

        for pos_2d in positions_z:
            var height := ctx.terrain_generator.get_height_at(pos_2d.x, pos_2d.y)
            if height > sea_level + 1.0 and height < sea_level + 20.0:
                var slope := ctx.terrain_generator.get_slope_at(pos_2d.x, pos_2d.y)
                if slope < 25.0:
                    waypoints.append({
                        "position": Vector3(pos_2d.x, height, pos_2d.y),
                        "type": "coast",
                        "priority": 7,
                        "biome": "coast",
                        "buildability_score": 0.8
                    })

    return waypoints

func _identify_biome_transitions(samples: Array, terrain_size: int) -> Array:
    var waypoints: Array = []

    for sample in samples:
        # Check if different biomes exist within radius
        var has_transition := _check_biome_variety(sample.position, 100.0, terrain_size)
        if has_transition and sample.slope < 20.0:
            var buildability := _calculate_buildability(sample.slope, sample.height)
            if buildability > 0.5:
                waypoints.append({
                    "position": sample.position,
                    "type": "transition",
                    "priority": 6,
                    "biome": sample.biome,
                    "buildability_score": buildability
                })

    return waypoints

func _filter_by_spacing(waypoints: Array, min_spacing: float, target_count: int) -> Array:
    var filtered: Array = []
    var min_spacing_sq := min_spacing * min_spacing

    # Create a copy of waypoints to work with
    var remaining_waypoints = waypoints.duplicate()

    # Instead of always picking the highest priority, we'll use a more balanced approach
    # that considers both priority and spatial distribution
    while filtered.size() < target_count and remaining_waypoints.size() > 0:
        var best_wp = null
        var best_idx = -1
        var best_score = -1.0

        # Evaluate each remaining waypoint based on priority and spatial distribution
        for i in range(remaining_waypoints.size()):
            var wp = remaining_waypoints[i]

            # Check if this waypoint is too close to any already-selected waypoint
            var too_close = false
            for existing in filtered:
                if wp.position.distance_squared_to(existing.position) < min_spacing_sq:
                    too_close = true
                    break

            if too_close:
                continue

            # Calculate a score that balances priority and spatial distribution
            # Higher priority is good, but being far from other selected points is also good
            var priority_score = float(wp.priority)
            var distribution_score = 0.0

            if filtered.size() > 0:
                # Calculate minimum distance to any selected waypoint
                var min_dist_sq = wp.position.distance_squared_to(filtered[0].position)
                for j in range(1, filtered.size()):
                    var dist_sq = wp.position.distance_squared_to(filtered[j].position)
                    if dist_sq < min_dist_sq:
                        min_dist_sq = dist_sq
                # Reward being far from other selected points
                distribution_score = sqrt(min_dist_sq) * 0.1  # Weight distribution less than priority

            var total_score = priority_score + distribution_score

            if total_score > best_score:
                best_score = total_score
                best_wp = wp
                best_idx = i

        if best_wp != null:
            filtered.append(best_wp)
            remaining_waypoints.remove_at(best_idx)
        else:
            # If no valid waypoint found, break to avoid infinite loop
            break

    return filtered

func _calculate_curvature(x: float, z: float, radius: float) -> float:
    # 2nd derivative approximation
    var h_center := ctx.terrain_generator.get_height_at(x, z)
    var h_right := ctx.terrain_generator.get_height_at(x + radius, z)
    var h_left := ctx.terrain_generator.get_height_at(x - radius, z)

    var d2h := (h_right + h_left - 2.0 * h_center) / (radius * radius)
    return d2h

func _is_local_minimum(pos: Vector3, radius: float) -> bool:
    var h_center := pos.y
    var samples := 8
    for i in range(samples):
        var angle := (i / float(samples)) * TAU
        var offset := Vector2(cos(angle), sin(angle)) * radius
        var sample_h := ctx.terrain_generator.get_height_at(pos.x + offset.x, pos.z + offset.y)
        if sample_h < h_center:
            return false
    return true

func _is_local_maximum(pos: Vector3, terrain_size: int, radius: float) -> bool:
    var h_center := pos.y
    var samples := 8
    for i in range(samples):
        var angle := (i / float(samples)) * TAU
        var offset := Vector2(cos(angle), sin(angle)) * radius
        var sample_h := ctx.terrain_generator.get_height_at(pos.x + offset.x, pos.z + offset.y)
        if sample_h > h_center:
            return false
    return true

func _calculate_buildability(slope: float, height: float) -> float:
    var sea_level: float = float(ctx.params.get("sea_level", 0.0))
    var slope_score: float = clamp(1.0 - slope / 45.0, 0.0, 1.0)
    var height_score: float = 1.0 if height > sea_level - 1.0 else 0.0
    return slope_score * height_score

func _sample_biome(x: float, z: float, terrain_size: int) -> String:
    if ctx.biome_map == null:
        return "grassland"

    var biome_res := ctx.biome_map.get_width()
    var px := clampi(int(x / terrain_size * biome_res), 0, biome_res - 1)
    var pz := clampi(int(z / terrain_size * biome_res), 0, biome_res - 1)
    var color := ctx.biome_map.get_pixel(px, pz)
    var biome_idx := int(color.r * 7.999)
    var biome_names := ["ocean", "beach", "grassland", "forest", "desert", "mountain", "snow", "tundra"]
    return biome_names[biome_idx]

func _check_biome_variety(pos: Vector3, radius: float, terrain_size: int) -> bool:
    var center_biome := _sample_biome(pos.x, pos.z, terrain_size)
    var samples := 8
    for i in range(samples):
        var angle := (i / float(samples)) * TAU
        var offset := Vector2(cos(angle), sin(angle)) * radius
        var sample_biome := _sample_biome(pos.x + offset.x, pos.z + offset.y, terrain_size)
        if sample_biome != center_biome:
            return true
    return false
