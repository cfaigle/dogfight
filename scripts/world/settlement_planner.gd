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
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Main planning entry point
func plan_settlement(center: Vector3, type: String, desired_radius: float, terrain_gen: RefCounted) -> Dictionary:
    terrain_generator = terrain_gen
    settlement_center = center
    settlement_type = type
    
    # Adaptive sizing based on terrain difficulty
    max_radius = _adaptive_radius_for_terrain(center, type, desired_radius)
    
    print("🏘️  SettlementPlanner: Planning %s at (%.0f, %.0f, %.0f) adapted radius %.0f (was %.0f)" % [type, center.x, center.y, center.z, max_radius, desired_radius])

    # Step 1: Analyze terrain to create realistic boundary
    _analyze_terrain_boundary()

    # Step 2: Plan terrain-following road network
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


## Step 1: Create organic terrain-following boundary
func _analyze_terrain_boundary() -> void:
    var water_level: float = 0.0  # Default, will be overridden by Game.sea_level at runtime
    
    print("      Creating organic boundary for %s..." % settlement_type)
    
    # Generate boundary points that follow terrain contours
    var boundary_points: Array[Vector2] = []
    
    # Start from center and expand outward following terrain
    var current_angle: float = rng.randf() * TAU
    var expansion_steps: int = 120  # More steps for smoother boundaries
    
    for step in range(expansion_steps):
        var angle_increment: float = TAU / float(expansion_steps)
        current_angle += angle_increment
        
        # Variable distance based on terrain - organic shape
        var base_distance: float = max_radius * 0.7
        var terrain_factor: float = 1.0
        
        # Sample terrain in this direction to find optimal boundary
        var optimal_distance: float = _find_terrain_optimal_boundary_distance(
            Vector2(cos(current_angle), sin(current_angle)), 
            base_distance, 
            water_level
        )
        
        # Add organic variation
        var organic_variation: float = sin(float(step) * 0.3) * 0.15 + cos(float(step) * 0.7) * 0.1
        optimal_distance *= (1.0 + organic_variation)
        optimal_distance = clamp(optimal_distance, max_radius * 0.3, max_radius * 1.2)
        
        # Calculate world position
        var world_point: Vector2 = Vector2(settlement_center.x, settlement_center.z) + Vector2(cos(current_angle), sin(current_angle)) * optimal_distance
        
        boundary_points.append(world_point)
    
    # Smooth the boundary for natural appearance
    boundary_points = _smooth_polygon_organic(boundary_points, 2)
    
    # Convert to PackedVector2Array
    boundary_polygon = PackedVector2Array(boundary_points)
    
    # Calculate area
    valid_area = _calculate_polygon_area(boundary_polygon)
    
    print("      Organic boundary created: %.0f points, %.0f m² area" % [boundary_points.size(), valid_area])


## Adaptive radius based on terrain difficulty
func _adaptive_radius_for_terrain(center: Vector3, type: String, base_radius: float) -> float:
    if terrain_generator == null:
        return base_radius
    
    # Sample terrain around the settlement center
    var sample_radius: float = base_radius * 0.5
    var samples: int = 16
    var total_slope: float = 0.0
    var valid_samples: int = 0
    
    for i in range(samples):
        var angle: float = (2.0 * PI * float(i)) / float(samples)
        var test_x: float = center.x + cos(angle) * sample_radius
        var test_z: float = center.z + sin(angle) * sample_radius
        
        var height: float = terrain_generator.get_height_at(test_x, test_z)
        var slope: float = terrain_generator.get_slope_at(test_x, test_z)
        
# Only count valid samples (not underwater)
        if height > 0.0 + 1.0:  # Default sea level, will use Game.sea_level at runtime
            total_slope += slope
            valid_samples += 1
    
    if valid_samples == 0:
        return base_radius * 0.3  # Very small if mostly underwater
    
    var avg_slope: float = total_slope / float(valid_samples)
    
    # Adaptive scaling based on terrain difficulty
    var difficulty_multiplier: float = 1.0
    
    if avg_slope < 0.2:  # Flat terrain
        difficulty_multiplier = 1.0
    elif avg_slope < 0.4:  # Gentle hills
        difficulty_multiplier = 0.8
    elif avg_slope < 0.6:  # Moderate slopes
        difficulty_multiplier = 0.6
    elif avg_slope < 0.8:  # Steep terrain
        difficulty_multiplier = 0.4
    else:  # Very steep terrain
        difficulty_multiplier = 0.25
    
    # Type-specific adjustments
    if type == "hamlet":
        difficulty_multiplier *= 0.8  # Hamlets can handle steeper terrain
    elif type == "city":
        difficulty_multiplier *= 1.2  # Cities need more space, but also flatter terrain
    elif type == "town":
        difficulty_multiplier *= 1.0  # Towns are average
    
    var adapted_radius = base_radius * difficulty_multiplier
    adapted_radius = clamp(adapted_radius, base_radius * 0.2, base_radius * 1.5)
    
    print("      Terrain difficulty: avg_slope=%.2f, multiplier=%.2f, radius=%.0f" % [avg_slope, difficulty_multiplier, adapted_radius])
    
    return adapted_radius

## Find terrain-optimal boundary distance (organic placement)
func _find_terrain_optimal_boundary_distance(dir: Vector2, base_dist: float, water_level: float) -> float:
    var step_size: float = 8.0  # Sample every 8m for precision
    var max_steps: int = int(base_dist * 1.5 / step_size)
    
    var best_distance: float = base_dist
    var best_score: float = -999.0
    
    # Sample along the ray to find optimal boundary point
    for step in range(1, max_steps):
        var dist: float = float(step) * step_size
        var world_x: float = settlement_center.x + dir.x * dist
        var world_z: float = settlement_center.z + dir.y * dist
        
        if terrain_generator == null:
            continue
        
        var height: float = terrain_generator.get_height_at(world_x, world_z)
        var slope: float = terrain_generator.get_slope_at(world_x, world_z)
        
        # Calculate terrain suitability score
        var score: float = 0.0
        
        # Height preference (avoid too low or too high)
        if height > water_level + 5.0 and height < water_level + 60.0:
            score += 50.0
        elif height > water_level + 2.0:
            score += 20.0
        
        # Slope preference (gentler is better)
        var max_slope: float = 0.8 if settlement_type == "city" else 1.0
        if slope < max_slope:
            score += 30.0 * (1.0 - slope / max_slope)
        
        # Distance preference (prefer near base distance)
        var dist_factor: float = 1.0 - abs(dist - base_dist) / base_dist
        score += 20.0 * dist_factor
        
        # Update best position
        if score > best_score:
            best_score = score
            best_distance = dist
    
    return best_distance

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


## Organic polygon smoothing with natural variation
func _smooth_polygon_organic(points: Array[Vector2], iterations: int) -> Array[Vector2]:
    var smoothed := points.duplicate()

    for _iter in range(iterations):
        var new_points: Array[Vector2] = []
        for i in range(smoothed.size()):
            var prev: Vector2 = smoothed[(i - 1 + smoothed.size()) % smoothed.size()]
            var curr: Vector2 = smoothed[i]
            var next: Vector2 = smoothed[(i + 1) % smoothed.size()]

            # Weighted average with organic variation
            var weight: float = 0.6
            var avg: Vector2 = prev * (1.0 - weight) * 0.5 + curr * weight + next * (1.0 - weight) * 0.5
            
            # Add slight organic perturbation
            var perturbation: Vector2 = Vector2(
                rng.randf_range(-2.0, 2.0),
                rng.randf_range(-2.0, 2.0)
            )
            avg += perturbation
            
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
    print("      Planning terrain-following road network for %s..." % settlement_type)
    
    var water_level: float = float(Game.sea_level)
    
    # Create organic road network based on settlement type
    if settlement_type == "city":
        _plan_city_organic_roads(water_level)
    elif settlement_type == "town":
        _plan_town_organic_roads(water_level)
    else:  # hamlet
        _plan_hamlet_organic_roads(water_level)
    
    print("      Created %d terrain-following road segments" % road_segments.size())


## City organic road network (radial + ring pattern following terrain)
func _plan_city_organic_roads(water_level: float) -> void:
    var center_2d: Vector2 = Vector2(settlement_center.x, settlement_center.z)
    
    # Primary radial roads that follow terrain
    var radial_count: int = 4 + rng.randi() % 3  # 4-6 main roads
    for i in range(radial_count):
        var angle: float = (float(i) / float(radial_count)) * TAU + rng.randf_range(-0.2, 0.2)
        var end_dist: float = max_radius * 0.9
        
        var road_points: Array[Vector3] = _trace_terrain_road(
            center_2d, angle, end_dist, water_level, 6.0
        )
        
        # Create road segments
        for j in range(road_points.size() - 1):
            road_segments.append({
                "from": road_points[j],
                "to": road_points[j + 1],
                "width": 8.0,
                "type": "main_road"
            })
    
    # Secondary ring roads that follow terrain contours
    var ring_count: int = 2
    for ring in range(1, ring_count + 1):
        var ring_radius: float = max_radius * (float(ring) / float(ring_count + 1)) * 0.8
        var ring_points: Array[Vector3] = []
        
        for angle_deg in range(0, 360, 15):
            var angle: float = deg_to_rad(float(angle_deg))
            var point: Vector2 = center_2d + Vector2(cos(angle), sin(angle)) * ring_radius
            
            var height: float = terrain_generator.get_height_at(point.x, point.y)
            if height > water_level + 2.0:
                ring_points.append(Vector3(point.x, height, point.y))
        
        # Connect ring points
        for j in range(ring_points.size()):
            var next_j: int = (j + 1) % ring_points.size()
            if ring_points.size() > 1:
                road_segments.append({
                    "from": ring_points[j],
                    "to": ring_points[next_j],
                    "width": 6.0,
                    "type": "ring_road"
                })


## Town organic road network (main street + branches)
func _plan_town_organic_roads(water_level: float) -> void:
    var center_2d: Vector2 = Vector2(settlement_center.x, settlement_center.z)
    
    # Main street through town
    var main_angle: float = rng.randf() * TAU
    var main_street: Array[Vector3] = _trace_terrain_road(
        center_2d - Vector2(cos(main_angle), sin(main_angle)) * max_radius * 0.8,
        main_angle,
        max_radius * 1.6,
        water_level,
        5.0
    )
    
    # Create main street segments
    for i in range(main_street.size() - 1):
        road_segments.append({
            "from": main_street[i],
            "to": main_street[i + 1],
            "width": 6.0,
            "type": "main_street"
        })
    
    # Side streets branching off main street
    if main_street.size() > 3:  # Only create branches if main street is long enough
        var branch_count: int = 3 + rng.randi() % 3
        var branch_point: Vector3 = Vector3.ZERO  # Declare outside loop
        for i in range(branch_count):
            var branch_idx: int = rng.randi_range(1, main_street.size() - 2)
            branch_point = main_street[branch_idx]
        var branch_angle: float = main_angle + deg_to_rad(90) + rng.randf_range(-0.3, 0.3)
        
        var branch_length: float = max_radius * 0.4
        var branch_road: Array[Vector3] = _trace_terrain_road(
            Vector2(branch_point.x, branch_point.z),
            branch_angle,
            branch_length,
            water_level,
            4.0
        )
        
        # Connect branch to main street
        if branch_road.size() > 0:
            road_segments.append({
                "from": branch_point,
                "to": branch_road[0],
                "width": 4.0,
                "type": "side_street"
            })
            
            # Branch segments
            for j in range(branch_road.size() - 1):
                road_segments.append({
                    "from": branch_road[j],
                    "to": branch_road[j + 1],
                    "width": 4.0,
                    "type": "side_street"
                })


## Hamlet organic road network (simple access roads)
func _plan_hamlet_organic_roads(water_level: float) -> void:
    var center_2d: Vector2 = Vector2(settlement_center.x, settlement_center.z)
    
    # Simple access roads following natural terrain
    var road_count: int = 1 + rng.randi() % 2  # 1-2 simple roads
    
    for i in range(road_count):
        var angle: float = rng.randf() * TAU
        var length: float = max_radius * 0.6
        
        var road_points: Array[Vector3] = _trace_terrain_road(
            center_2d, angle, length, water_level, 3.0
        )
        
        # Create road segments
        for j in range(road_points.size() - 1):
            road_segments.append({
                "from": road_points[j],
                "to": road_points[j + 1],
                "width": 3.0,
                "type": "access_road"
            })

## Trace terrain-following road from start point in direction
func _trace_terrain_road(start_pos: Vector2, direction: float, max_length: float, water_level: float, step_size: float) -> Array[Vector3]:
    var points: Array[Vector3] = []
    
    var current_pos: Vector2 = start_pos
    var current_angle: float = direction
    var remaining_length: float = max_length
    var step_count: int = 0
    var max_steps: int = int(max_length / step_size)
    
    # Start point
    var start_height: float = terrain_generator.get_height_at(start_pos.x, start_pos.y)
    if start_height > water_level + 1.0:
        points.append(Vector3(start_pos.x, start_height, start_pos.y))
    
    while remaining_length > 0 and step_count < max_steps:
        step_count += 1
        
        # Calculate next position
        var next_pos: Vector2 = current_pos + Vector2(cos(current_angle), sin(current_angle)) * step_size
        
        # Check bounds
        var half_terrain: float = float(Game.settings.get("terrain_size", 6000.0)) * 0.5
        if abs(next_pos.x) > half_terrain * 0.95 or abs(next_pos.y) > half_terrain * 0.95:
            break
        
        # Get terrain info
        var height: float = terrain_generator.get_height_at(next_pos.x, next_pos.y)
        var slope: float = terrain_generator.get_slope_at(next_pos.x, next_pos.y)
        
        # Skip if underwater or too steep
        if height < water_level + 1.0 or slope > 0.8:
            break
        
        # Add road point
        points.append(Vector3(next_pos.x, height, next_pos.y))
        
        # Adjust angle based on terrain (follow natural contours)
        if slope > 0.3:
            # Follow gentle contours around steep areas
            var slope_angle: float = terrain_generator.get_slope_direction_at(next_pos.x, next_pos.y)
            current_angle = lerp_angle(current_angle, slope_angle + deg_to_rad(90), 0.1)
        
        # Add slight organic variation
        current_angle += rng.randf_range(-0.05, 0.05)
        
        current_pos = next_pos
        remaining_length -= step_size
    
    return points


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
