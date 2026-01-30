class_name RoadElevationAdjuster
extends RefCounted

## Adjusts road elevations dynamically to follow terrain contours and create realistic road profiles

var terrain_generator = null
var world_context = null

# Elevation adjustment parameters
var max_gradient: float = 0.15  # Maximum road gradient (15%)
var min_cut_depth: float = 0.5  # Minimum depth for cutting into terrain
var max_fill_height: float = 10.0  # Maximum height for filling above terrain
var cut_slope_limit: float = 30.0  # Maximum slope for cuts (degrees)
var fill_slope_limit: float = 25.0  # Maximum slope for fills (degrees)
var smoothing_distance: float = 20.0  # Distance over which to smooth elevation changes

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx) -> void:
    world_context = world_ctx

## Adjust road elevations to follow terrain contours appropriately
func adjust_road_elevations(waypoints: PackedVector3Array, width: float, road_type: String = "local") -> PackedVector3Array:
    if waypoints.size() < 2 or terrain_generator == null or not terrain_generator.has_method("get_height_at"):
        return waypoints
    
    var adjusted_waypoints: PackedVector3Array = PackedVector3Array()
    
    # Determine parameters based on road type
    var type_params: Dictionary = _get_road_type_parameters(road_type)
    
    # Process each waypoint
    for i in range(waypoints.size()):
        var original_point: Vector3 = waypoints[i]
        var adjusted_point: Vector3 = original_point
        
        # Get terrain height at this point
        var terrain_height: float = terrain_generator.get_height_at(original_point.x, original_point.z)
        
        # Determine if we should cut, fill, or follow terrain
        var target_elevation: float = _calculate_target_elevation(
            original_point, 
            terrain_height, 
            i, 
            waypoints, 
            type_params
        )
        
        adjusted_point.y = target_elevation
        adjusted_waypoints.append(adjusted_point)
    
    # Apply smoothing to reduce abrupt elevation changes
    var smoothed_waypoints: PackedVector3Array = _apply_elevation_smoothing(adjusted_waypoints, type_params.max_gradient)
    
    return smoothed_waypoints

## Calculate target elevation for a point based on terrain and road requirements
func _calculate_target_elevation(point: Vector3, terrain_height: float, index: int,
                                all_waypoints: PackedVector3Array, params: Dictionary) -> float:
    # Check if this point is over actual water (not just below sea level)
    var sea_level: float = 20.0  # Default sea level
    if world_context and world_context.has_method("get_sea_level"):
        sea_level = float(world_context.get_sea_level())
    elif world_context and world_context.has_method("get"):
        var sea_level_val = world_context.get("sea_level")
        if sea_level_val != null:
            sea_level = float(sea_level_val)

    # Only treat as water crossing if the terrain height is significantly below sea level
    # and there's actual water (e.g., very close to sea level and below it)
    # This prevents all low-lying terrain from being treated as water
    if terrain_height < sea_level - 0.5:  # Only if significantly below sea level
        # Check if this is likely actual water by checking nearby terrain heights
        var is_actual_water = _is_likely_water_body(point, terrain_height, sea_level)
        if is_actual_water:
            # This is a water crossing - needs bridge or tunnel
            return _handle_water_crossing(point, terrain_height, sea_level, params)

    # Calculate required elevation based on terrain and road type
    var base_elevation: float = terrain_height + params.road_offset

    # Check local terrain slope
    if terrain_generator and terrain_generator.has_method("get_slope_at"):
        var local_slope: float = terrain_generator.get_slope_at(point.x, point.z)

        if local_slope > params.cut_slope_limit and terrain_height < point.y:
            # Steep terrain ahead - consider cutting
            return _evaluate_cut_scenario(point, terrain_height, base_elevation, local_slope, params)
        elif local_slope > params.fill_slope_limit and terrain_height > point.y:
            # Steep fill required - consider alternative route or reinforcement
            return _evaluate_fill_scenario(point, terrain_height, base_elevation, local_slope, params)

    # Normal terrain - follow with appropriate offset
    return base_elevation

## Check if a low-lying area is likely an actual water body
func _is_likely_water_body(point: Vector3, terrain_height: float, sea_level: float) -> bool:
    if terrain_generator == null:
        return false

    # Check if the terrain height is very close to sea level (indicating water)
    # and if nearby terrain heights are also near sea level (indicating a continuous water body)
    var sample_distance: float = 10.0  # Distance to sample around the point
    var sample_points: int = 8  # Number of points to sample around
    var water_threshold: float = 0.5  # How close to sea level indicates water

    var water_samples: int = 0
    var total_samples: int = 0

    for i in range(sample_points):
        var angle: float = (TAU * i) / sample_points
        var sample_x: float = point.x + cos(angle) * sample_distance
        var sample_z: float = point.z + sin(angle) * sample_distance

        var sample_height: float = terrain_generator.get_height_at(sample_x, sample_z)

        # If sample is close to sea level, consider it water
        if abs(sample_height - sea_level) <= water_threshold:
            water_samples += 1
        total_samples += 1

    # If most samples around the point are at water level, it's likely a water body
    var water_ratio: float = float(water_samples) / float(total_samples)
    return water_ratio >= 0.6  # At least 60% of samples must be water level

## Get parameters based on road type
func _get_road_type_parameters(road_type: String) -> Dictionary:
    var params: Dictionary = {
        "road_offset": 0.5,  # Base offset above terrain
        "cut_slope_limit": cut_slope_limit,
        "fill_slope_limit": fill_slope_limit,
        "max_gradient": max_gradient,
        "importance": 1.0  # Multiplier for construction effort
    }
    
    match road_type:
        "highway":
            params.road_offset = 0.8
            params.cut_slope_limit = cut_slope_limit * 1.2  # Highways can handle steeper cuts
            params.fill_slope_limit = fill_slope_limit * 1.2
            params.max_gradient = max_gradient * 0.8  # Stricter gradient for highways
            params.importance = 2.0
        "arterial":
            params.road_offset = 0.6
            params.max_gradient = max_gradient * 0.9
            params.importance = 1.5
        "local":
            params.road_offset = 0.5
            params.importance = 1.0
        "access":
            params.road_offset = 0.3
            params.importance = 0.7
            params.cut_slope_limit *= 0.8
            params.fill_slope_limit *= 0.8
    
    return params

## Handle water crossing scenarios
func _handle_water_crossing(point: Vector3, terrain_height: float, sea_level: float, params: Dictionary) -> float:
    # For now, return bridge elevation
    # In a full implementation, this would determine if bridge, tunnel, or ferry is appropriate
    var bridge_clearance: float = 8.0  # Standard bridge clearance
    return sea_level + bridge_clearance

## Evaluate if cutting into terrain is appropriate
func _evaluate_cut_scenario(point: Vector3, terrain_height: float, base_elevation: float, 
                           slope: float, params: Dictionary) -> float:
    # Calculate potential cut depth
    var potential_cut: float = terrain_height - base_elevation
    
    if potential_cut > min_cut_depth:
        # Cutting is appropriate
        return base_elevation
    else:
        # Just follow terrain
        return terrain_height + params.road_offset

## Evaluate if filling above terrain is appropriate
func _evaluate_fill_scenario(point: Vector3, terrain_height: float, base_elevation: float, 
                            slope: float, params: Dictionary) -> float:
    # Calculate potential fill height
    var potential_fill: float = base_elevation - terrain_height
    
    if potential_fill > 0 and potential_fill < max_fill_height:
        # Filling is appropriate
        return base_elevation
    else:
        # If fill would be too high, follow terrain more closely
        return terrain_height + min(potential_fill, params.road_offset)

## Apply smoothing to reduce elevation gradients
func _apply_elevation_smoothing(waypoints: PackedVector3Array, max_gradient: float) -> PackedVector3Array:
    if waypoints.size() < 3:
        return waypoints
    
    var smoothed: PackedVector3Array = waypoints.duplicate()
    
    # Forward pass: ensure uphill gradients don't exceed limit
    for i in range(1, waypoints.size()):
        var prev_point: Vector3 = smoothed[i - 1]
        var curr_point: Vector3 = smoothed[i]
        
        var horizontal_dist: float = Vector2(prev_point.x, prev_point.z).distance_to(Vector2(curr_point.x, curr_point.z))
        var max_elevation_change: float = horizontal_dist * max_gradient
        
        # Check uphill (current higher than previous)
        if curr_point.y - prev_point.y > max_elevation_change:
            smoothed[i].y = prev_point.y + max_elevation_change
        # Check downhill (previous higher than current) 
        elif prev_point.y - curr_point.y > max_elevation_change:
            smoothed[i].y = prev_point.y - max_elevation_change
    
    # Backward pass: ensure downhill gradients don't exceed limit
    for i in range(waypoints.size() - 2, -1, -1):
        var curr_point: Vector3 = smoothed[i]
        var next_point: Vector3 = smoothed[i + 1]
        
        var horizontal_dist: float = Vector2(curr_point.x, curr_point.z).distance_to(Vector2(next_point.x, next_point.z))
        var max_elevation_change: float = horizontal_dist * max_gradient
        
        # Check uphill (next higher than current)
        if next_point.y - curr_point.y > max_elevation_change:
            smoothed[i].y = next_point.y - max_elevation_change
        # Check downhill (current higher than next)
        elif curr_point.y - next_point.y > max_elevation_change:
            smoothed[i].y = next_point.y + max_elevation_change
    
    return smoothed