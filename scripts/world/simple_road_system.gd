class_name SimpleRoadSystem
extends RefCounted

## Simplified road system that addresses the core issues without circular dependencies

var terrain_generator = null
var world_context = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx) -> void:
    world_context = world_ctx

## Generate a complete road network for a set of settlements
func generate_complete_road_network(settlements: Array, params: Dictionary = {}) -> Dictionary:
    var generation_result: Dictionary = {
        "success": false,
        "road_segments": [],
        "generation_stats": {},
        "errors": []
    }
    
    if settlements.size() < 2:
        generation_result.errors.append("Need at least 2 settlements to generate road network")
        return generation_result
    
    print("🏗️ Starting simplified road network generation for %d settlements" % settlements.size())
    
    # Step 1: Create intelligent road network using minimum spanning tree
    var road_segments: Array = _create_intelligent_road_network(settlements)
    
    # Step 2: Process each road segment with advanced techniques
    print("⛰️ Processing road segments with terrain integration...")
    var processed_segments: Array = []
    for segment in road_segments:
        var processed_segment: Dictionary = _process_road_segment(segment, params)
        if processed_segment != null:
            processed_segments.append(processed_segment)
    
    # Prepare final result
    generation_result.success = true
    generation_result.road_segments = processed_segments
    generation_result.generation_stats = {
        "total_segments": processed_segments.size()
    }
    
    print("✅ Simplified road network generation complete: %d segments" % [
        processed_segments.size()
    ])
    
    return generation_result

## Process a single road segment with all improvements
func _process_road_segment(segment: Dictionary, params: Dictionary) -> Dictionary:
    var start_pos: Vector3 = segment.from
    var end_pos: Vector3 = segment.to
    var road_type: String = segment.type
    var width: float = segment.width
    
    # Create a simple path (straight line for now, would be more complex in full implementation)
    var path: PackedVector3Array = PackedVector3Array()
    path.append(start_pos)
    path.append(end_pos)
    
    # Check if this road segment crosses water and needs bridges
    var water_crossings: Array = _detect_water_crossings(start_pos, end_pos)

    if water_crossings.size() > 0:
        # This segment crosses water - needs bridges for the water sections
        var adjusted_path: PackedVector3Array = _adjust_road_elevations(path, width, road_type)

        # For segments with water crossings, elevate only the water sections
        adjusted_path = _elevate_path_for_water_crossings(adjusted_path, water_crossings)

        # Create the processed segment with bridge information
        var processed_segment: Dictionary = {
            "from": start_pos,
            "to": end_pos,
            "type": road_type,
            "width": width,
            "path": adjusted_path,
            "length": _calculate_path_length(adjusted_path),
            "is_bridge": true,
            "water_crossings": water_crossings
        }

        return processed_segment
    else:
        # No water crossings - adjust elevations to follow terrain properly
        var adjusted_path: PackedVector3Array = _adjust_road_elevations(path, width, road_type)

        # Carve terrain to integrate road properly
        _carve_road_terrain(adjusted_path, width, 0.5, 1.5)

        # Create the processed segment
        var processed_segment: Dictionary = {
            "from": start_pos,
            "to": end_pos,
            "type": road_type,
            "width": width,
            "path": adjusted_path,
            "length": _calculate_path_length(adjusted_path),
            "is_bridge": false,
            "water_crossings": []
        }

        return processed_segment

## Simplified elevation adjustment that properly follows terrain
func _adjust_road_elevations(waypoints: PackedVector3Array, width: float, road_type: String) -> PackedVector3Array:
    if waypoints.size() < 2 or terrain_generator == null or not terrain_generator.has_method("get_height_at"):
        return waypoints

    var adjusted_waypoints: PackedVector3Array = PackedVector3Array()

    for i in range(waypoints.size()):
        var original_point: Vector3 = waypoints[i]
        var adjusted_point: Vector3 = original_point

        # Get terrain height at this point
        var terrain_height: float = terrain_generator.get_height_at(original_point.x, original_point.z)

        # Apply appropriate offset above terrain based on road type
        var offset: float = 0.5  # Default offset
        if road_type == "highway":
            offset = 0.8
        elif road_type == "arterial":
            offset = 0.6
        elif road_type == "local":
            offset = 0.5

        # Apply the offset to ensure road is above terrain
        adjusted_point.y = terrain_height + offset
        adjusted_waypoints.append(adjusted_point)

    # Apply smoothing to reduce abrupt elevation changes
    var smoothed_waypoints: PackedVector3Array = _smooth_elevation_changes(adjusted_waypoints)

    return smoothed_waypoints

## Smooth elevation changes to avoid abrupt transitions
func _smooth_elevation_changes(waypoints: PackedVector3Array) -> PackedVector3Array:
    if waypoints.size() < 3:
        return waypoints

    var smoothed: PackedVector3Array = waypoints.duplicate()

    # Apply smoothing to reduce elevation differences between adjacent points
    for i in range(1, waypoints.size() - 1):
        var prev_point: Vector3 = smoothed[i - 1]
        var curr_point: Vector3 = smoothed[i]
        var next_point: Vector3 = smoothed[i + 1]

        # Calculate horizontal distances
        var dist_prev_curr: float = Vector2(prev_point.x, prev_point.z).distance_to(Vector2(curr_point.x, curr_point.z))
        var dist_curr_next: float = Vector2(curr_point.x, curr_point.z).distance_to(Vector2(next_point.x, next_point.z))

        # Calculate maximum allowable elevation changes based on gradient limits
        var max_gradient: float = 0.15  # 15% maximum gradient
        var max_elevation_change_prev: float = dist_prev_curr * max_gradient
        var max_elevation_change_next: float = dist_curr_next * max_gradient

        # Adjust current point elevation to respect gradient limits
        var target_elevation: float = (prev_point.y + next_point.y) / 2.0  # Average of neighbors
        var elevation_diff: float = abs(curr_point.y - target_elevation)

        if elevation_diff > max_elevation_change_prev or elevation_diff > max_elevation_change_next:
            # Limit elevation to respect gradient constraints
            var max_change: float = min(max_elevation_change_prev, max_elevation_change_next)
            var direction: float = sign(target_elevation - curr_point.y)
            var limited_elevation: float = curr_point.y + direction * min(elevation_diff, max_change)
            smoothed[i].y = limited_elevation

    return smoothed

## Simplified terrain carving
func _carve_road_terrain(waypoints: PackedVector3Array, width: float, depth: float = 0.5, 
                       shoulder_width: float = 2.0, shoulder_depth: float = 0.2) -> void:
    if waypoints.size() < 2 or terrain_generator == null:
        return
    
    # Calculate carving parameters
    var half_width: float = width / 2.0
    var half_total_width: float = half_width + shoulder_width
    
    # Process each segment of the road
    for i in range(waypoints.size() - 1):
        var start_point: Vector3 = waypoints[i]
        var end_point: Vector3 = waypoints[i + 1]
        
        # Calculate direction vector
        var direction: Vector3 = (end_point - start_point).normalized()
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
        
        # Carve along the segment (simplified)
        _carve_road_segment(start_point, end_point, half_width, depth,
                           shoulder_width, shoulder_depth)

## Carve a single road segment
func _carve_road_segment(start: Vector3, end: Vector3, half_road_width: float, road_depth: float,
                       shoulder_width: float, shoulder_depth: float) -> void:
    # Calculate the length of this segment
    var segment_length: float = start.distance_to(end)
    var num_samples: int = max(5, int(segment_length / 5.0))  # Sample every 5m or 5 samples minimum

    # Calculate direction vector
    var direction: Vector3 = (end - start).normalized()
    var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()

    # Sample along the segment
    for i in range(num_samples + 1):
        var t: float = float(i) / float(num_samples)
        var center_point: Vector3 = start.lerp(end, t)

        # Carve the road bed
        _carve_elliptical_hole(center_point, half_road_width, road_depth, 0.0)

        # Carve shoulders on both sides
        var left_shoulder_center: Vector3 = center_point - Vector3(perpendicular.x, 0, perpendicular.z) * (half_road_width + shoulder_width/2.0)
        var right_shoulder_center: Vector3 = center_point + Vector3(perpendicular.x, 0, perpendicular.z) * (half_road_width + shoulder_width/2.0)

        _carve_elliptical_hole(left_shoulder_center, shoulder_width/2.0, shoulder_depth, 0.3)  # Less deep with more smoothing
        _carve_elliptical_hole(right_shoulder_center, shoulder_width/2.0, shoulder_depth, 0.3)

## Carve an elliptical hole in the terrain
func _carve_elliptical_hole(center: Vector3, radius: float, depth: float, smoothing: float = 0.5) -> void:
    if terrain_generator == null or not terrain_generator.has_method("get_height_at") or not terrain_generator.has_method("set_height_at"):
        return
    
    # Determine the area to modify
    var cell_size = 10.0  # Default cell size if not available
    if terrain_generator.has_method("get_cell_size"):
        cell_size = terrain_generator.get_cell_size()
    
    var min_x: int = int(floor((center.x - radius) / cell_size))
    var max_x: int = int(ceil((center.x + radius) / cell_size))
    var min_z: int = int(floor((center.z - radius) / cell_size))
    var max_z: int = int(ceil((center.z + radius) / cell_size))
    
    # Iterate through the affected area
    for x in range(min_x, max_x + 1):
        for z in range(min_z, max_z + 1):
            var world_x: float = float(x) * cell_size
            var world_z: float = float(z) * cell_size
            
            # Calculate distance from center
            var dist: float = sqrt(pow(world_x - center.x, 2) + pow(world_z - center.z, 2))
            
            if dist <= radius:
                # Calculate the influence based on distance and smoothing
                var normalized_dist: float = dist / radius
                var influence: float = 1.0 - pow(normalized_dist, 2)  # Quadratic falloff
                influence = lerp(influence, 0.0, smoothing)  # Apply smoothing
                
                # Calculate new height
                var current_height: float = terrain_generator.get_height_at(world_x, world_z)
                var target_height: float = center.y - depth
                var new_height: float = lerp(current_height, target_height, influence)
                
                # Set the new height
                terrain_generator.set_height_at(x, z, new_height)

## Determine road type based on settlement characteristics
func _determine_road_type(settlement_a: Dictionary, settlement_b: Dictionary) -> String:
    var pop_a: int = settlement_a.get("population", 100)
    var pop_b: int = settlement_b.get("population", 100)
    var total_pop: int = pop_a + pop_b
    
    if total_pop >= 1000:  # Combined population of 1000+
        return "highway"
    elif total_pop >= 400:  # Combined population of 400+
        return "arterial"
    else:
        return "local"

## Get appropriate width for road type
func _get_road_width_for_type(road_type: String) -> float:
    match road_type:
        "highway": return 18.0
        "arterial": return 12.0
        "local": return 8.0
        _: return 8.0

## Create intelligent road network using minimum spanning tree approach
func _create_intelligent_road_network(settlements: Array) -> Array:
    var road_segments: Array = []

    if settlements.size() < 2:
        return road_segments

    # Create a list of all possible connections with their costs
    var connections: Array = []
    for i in range(settlements.size()):
        for j in range(i + 1, settlements.size()):
            var settlement_a: Dictionary = settlements[i]
            var settlement_b: Dictionary = settlements[j]

            var start_pos: Vector3 = settlement_a.get("center", Vector3.ZERO)
            var end_pos: Vector3 = settlement_b.get("center", Vector3.ZERO)

            if start_pos != Vector3.ZERO and end_pos != Vector3.ZERO:
                var distance: float = start_pos.distance_to(end_pos)

                # Calculate cost based on distance and settlement importance
                var pop_a: int = settlement_a.get("population", 100)
                var pop_b: int = settlement_b.get("population", 100)
                var combined_pop: int = pop_a + pop_b

                # Base cost is distance, reduced for high-population connections
                var base_cost: float = distance
                var pop_factor: float = 1.0 / (float(combined_pop) / 100.0)  # Higher population = lower cost per distance
                var cost: float = base_cost * pop_factor

                # Add terrain difficulty cost
                if terrain_generator:
                    cost += _estimate_terrain_difficulty(start_pos, end_pos)

                # Check if this connection crosses water and add bridge cost multiplier
                if _crosses_water(start_pos, end_pos):
                    cost *= 10.0  # 10x cost for bridges

                connections.append({
                    "from_idx": i,
                    "to_idx": j,
                    "cost": cost,
                    "distance": distance,
                    "settlement_a": settlement_a,
                    "settlement_b": settlement_b
                })

    # Sort connections by cost (cheapest first)
    connections.sort_custom(func(a, b): return a.cost < b.cost)

    # Use Union-Find to implement Kruskal's algorithm for MST
    var parent: Array = []
    parent.resize(settlements.size())
    for i in range(settlements.size()):
        parent[i] = i

    # Build MST
    var mst_connections: Array = []
    for connection in connections:
        if _union_find_union(connection.from_idx, connection.to_idx, parent):
            mst_connections.append(connection)
            # Stop if we have n-1 edges (complete tree)
            if mst_connections.size() == settlements.size() - 1:
                break

    # Convert MST connections to road segments
    for connection in mst_connections:
        var settlement_a: Dictionary = connection.settlement_a
        var settlement_b: Dictionary = connection.settlement_b

        var start_pos: Vector3 = settlement_a.get("center", Vector3.ZERO)
        var end_pos: Vector3 = settlement_b.get("center", Vector3.ZERO)

        # Determine road type based on settlement sizes
        var road_type: String = _determine_road_type(settlement_a, settlement_b)
        var width: float = _get_road_width_for_type(road_type)

        # Create road segment
        var segment: Dictionary = {
            "from": start_pos,
            "to": end_pos,
            "type": road_type,
            "width": width
        }

        road_segments.append(segment)

    # Add some strategic secondary connections for better connectivity
    var secondary_connections: Array = _add_secondary_connections(settlements, mst_connections)
    for connection in secondary_connections:
        var settlement_a: Dictionary = connection.settlement_a
        var settlement_b: Dictionary = connection.settlement_b

        var start_pos: Vector3 = settlement_a.get("center", Vector3.ZERO)
        var end_pos: Vector3 = settlement_b.get("center", Vector3.ZERO)

        # Determine road type based on settlement sizes
        var road_type: String = _determine_road_type(settlement_a, settlement_b)
        var width: float = _get_road_width_for_type(road_type)

        # Create road segment
        var segment: Dictionary = {
            "from": start_pos,
            "to": end_pos,
            "type": road_type,
            "width": width
        }

        road_segments.append(segment)

    print("   🗺️ Created ", road_segments.size(), " connections using MST + strategic secondary connections (instead of ",
          settlements.size() * (settlements.size() - 1) / 2, " possible connections)")

    return road_segments

## Check if a connection crosses water
func _crosses_water(start_pos: Vector3, end_pos: Vector3) -> bool:
    if not terrain_generator or not terrain_generator.has_method("get_height_at"):
        return false

    # Sample along the path to check for water
    var samples: int = max(5, int(start_pos.distance_to(end_pos) / 50.0))  # Sample every ~50m
    var sea_level: float = 20.0  # Default sea level

    # Try to get sea level from context if available
    if world_context and world_context.has_method("get_sea_level"):
        sea_level = float(world_context.get_sea_level())
    elif world_context and world_context.has_method("get"):
        var sea_level_val = world_context.get("sea_level")
        if sea_level_val != null:
            sea_level = float(sea_level_val)

    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        var height: float = terrain_generator.get_height_at(pos.x, pos.z)

        # Check if this point is below sea level (water)
        if height < sea_level:
            return true

        # Also check if world context has lake detection
        if world_context and world_context.has_method("is_in_lake"):
            if world_context.is_in_lake(pos.x, pos.z):
                return true

    return false

## Estimate terrain difficulty between two points
func _estimate_terrain_difficulty(start_pos: Vector3, end_pos: Vector3) -> float:
    if not terrain_generator or not terrain_generator.has_method("get_slope_at"):
        return 0.0

    # Sample terrain along the path
    var samples: int = max(5, int(start_pos.distance_to(end_pos) / 100.0))  # Sample every ~100m
    var total_difficulty: float = 0.0

    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)

        # Higher slopes = higher difficulty/cost
        if slope > 20.0:  # Very steep
            total_difficulty += slope * 2.0
        elif slope > 10.0:  # Moderately steep
            total_difficulty += slope * 1.0
        # Gentle slopes don't add much cost

    return total_difficulty / float(max(samples, 1))

## Add strategic secondary connections to improve connectivity
func _add_secondary_connections(settlements: Array, mst_connections: Array) -> Array:
    var secondary_connections: Array = []

    # Only add secondary connections if we have enough settlements to make it meaningful
    if settlements.size() < 4:
        return secondary_connections

    # Add connections between high-importance settlements (cities)
    var important_settlements: Array = []
    for settlement in settlements:
        var pop: int = settlement.get("population", 100)
        if pop >= 500:  # Major cities
            important_settlements.append(settlement)

    # Connect important settlements that aren't already connected in MST
    for i in range(important_settlements.size()):
        for j in range(i + 1, important_settlements.size()):
            var settlement_a: Dictionary = important_settlements[i]
            var settlement_b: Dictionary = important_settlements[j]

            # Check if these settlements are already connected in MST
            var already_connected: bool = false
            for mst_conn in mst_connections:
                var mst_a: Dictionary = mst_conn.settlement_a
                var mst_b: Dictionary = mst_conn.settlement_b

                if (mst_a.get("center", Vector3.ZERO) == settlement_a.get("center", Vector3.ZERO) and
                    mst_b.get("center", Vector3.ZERO) == settlement_b.get("center", Vector3.ZERO)) or \
                   (mst_a.get("center", Vector3.ZERO) == settlement_b.get("center", Vector3.ZERO) and
                    mst_b.get("center", Vector3.ZERO) == settlement_a.get("center", Vector3.ZERO)):
                    already_connected = true
                    break

            if not already_connected:
                secondary_connections.append({
                    "settlement_a": settlement_a,
                    "settlement_b": settlement_b
                })

    # Add some regional connections (connect nearby settlements)
    var max_regional_distance: float = 1000.0  # Only connect settlements within 1km
    for i in range(settlements.size()):
        var settlement_a: Dictionary = settlements[i]
        var pos_a: Vector3 = settlement_a.get("center", Vector3.ZERO)

        for j in range(i + 1, settlements.size()):
            var settlement_b: Dictionary = settlements[j]
            var pos_b: Vector3 = settlement_b.get("center", Vector3.ZERO)

            var distance: float = pos_a.distance_to(pos_b)
            if distance <= max_regional_distance:
                # Check if already connected in MST or secondary
                var already_connected: bool = false

                # Check MST
                for mst_conn in mst_connections:
                    var mst_pos_a: Vector3 = mst_conn.settlement_a.get("center", Vector3.ZERO)
                    var mst_pos_b: Vector3 = mst_conn.settlement_b.get("center", Vector3.ZERO)

                    if (mst_pos_a == pos_a and mst_pos_b == pos_b) or (mst_pos_a == pos_b and mst_pos_b == pos_a):
                        already_connected = true
                        break

                # Check secondary connections already added
                if not already_connected:
                    for sec_conn in secondary_connections:
                        var sec_pos_a: Vector3 = sec_conn.settlement_a.get("center", Vector3.ZERO)
                        var sec_pos_b: Vector3 = sec_conn.settlement_b.get("center", Vector3.ZERO)

                        if (sec_pos_a == pos_a and sec_pos_b == pos_b) or (sec_pos_a == pos_b and sec_pos_b == pos_a):
                            already_connected = true
                            break

                if not already_connected:
                    # Add with probability based on proximity (closer = higher chance)
                    var connection_probability: float = 1.0 - (distance / max_regional_distance)
                    # Use a deterministic approach instead of randf() to avoid needing random number generator
                    var pseudo_random: float = fmod(pos_a.x * 12.9898 + pos_a.z * 78.233 + pos_b.x * 37.719 + pos_b.z * 123.456, 1.0)
                    if pseudo_random < connection_probability * 0.3:  # Only add 30% of eligible connections
                        secondary_connections.append({
                            "settlement_a": settlement_a,
                            "settlement_b": settlement_b
                        })

    return secondary_connections

## Union-find helper function to find root with path compression
func _union_find_find_root(x: int, parent: Array) -> int:
    if parent[x] != x:
        parent[x] = _union_find_find_root(parent[x], parent)  # Path compression
    return parent[x]

## Union-find helper function to unite two sets
func _union_find_union(x: int, y: int, parent: Array) -> bool:
    var root_x: int = _union_find_find_root(x, parent)
    var root_y: int = _union_find_find_root(y, parent)
    if root_x == root_y:
        return false  # Would create cycle
    parent[root_x] = root_y
    return true

## Detect water crossings along a path
func _detect_water_crossings(start_pos: Vector3, end_pos: Vector3) -> Array:
    if not terrain_generator or not terrain_generator.has_method("get_height_at"):
        return []

    var water_crossings: Array = []
    var samples: int = max(10, int(start_pos.distance_to(end_pos) / 50.0))  # Sample every ~50m
    var sea_level: float = 20.0  # Default sea level

    # Get sea level from context if available
    if world_context and world_context.has_method("get_sea_level"):
        sea_level = float(world_context.get_sea_level())
    elif world_context and world_context.has_method("get"):
        var sea_level_val = world_context.get("sea_level")
        if sea_level_val != null:
            sea_level = float(sea_level_val)

    # Track water crossing state
    var in_water: bool = false
    var crossing_start_idx: int = -1

    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        var height: float = terrain_generator.get_height_at(pos.x, pos.z)

        var is_water: bool = height < sea_level

        # Check for lake crossings if world context available
        if not is_water and world_context and world_context.has_method("is_in_lake"):
            if world_context.is_in_lake(pos.x, pos.z):
                is_water = true

        if is_water and not in_water:
            # Start of water crossing
            crossing_start_idx = i
            in_water = true
        elif not is_water and in_water:
            # End of water crossing
            var crossing: Dictionary = {
                "start_idx": crossing_start_idx,
                "end_idx": i - 1,
                "start_pos": start_pos.lerp(end_pos, float(crossing_start_idx) / float(samples)),
                "end_pos": start_pos.lerp(end_pos, float(i - 1) / float(samples)),
                "length": start_pos.lerp(end_pos, float(crossing_start_idx) / float(samples)).distance_to(
                    start_pos.lerp(end_pos, float(i - 1) / float(samples))
                )
            }
            water_crossings.append(crossing)
            in_water = false
            crossing_start_idx = -1

    # Handle crossing that extends to end of path
    if in_water and crossing_start_idx >= 0:
        var crossing: Dictionary = {
            "start_idx": crossing_start_idx,
            "end_idx": samples,
            "start_pos": start_pos.lerp(end_pos, float(crossing_start_idx) / float(samples)),
            "end_pos": end_pos,
            "length": start_pos.lerp(end_pos, float(crossing_start_idx) / float(samples)).distance_to(end_pos)
        }
        water_crossings.append(crossing)

    return water_crossings

## Elevate only water sections of a path for bridges
func _elevate_path_for_water_crossings(path: PackedVector3Array, water_crossings: Array) -> PackedVector3Array:
    if path.size() < 2 or terrain_generator == null or water_crossings.size() == 0:
        return path

    var elevated_path: PackedVector3Array = path.duplicate()

    # Process each water crossing
    for crossing in water_crossings:
        # Calculate water level for this crossing
        var water_level: float = _get_water_level_for_crossing(crossing.start_pos, crossing.end_pos)
        var bridge_height: float = water_level + 8.0  # Standard bridge clearance

        # Find points in the path that correspond to this crossing
        for i in range(path.size()):
            var point: Vector3 = path[i]

            # Check if this point is near the crossing path segment
            var start_pos: Vector3 = crossing.start_pos
            var end_pos: Vector3 = crossing.end_pos
            var dist_to_segment: float = _distance_to_line_segment(point, start_pos, end_pos)

            # If point is close to the water crossing segment, elevate it
            if dist_to_segment < 50.0:  # Within 50m of the crossing
                var elevated_point: Vector3 = elevated_path[i]
                elevated_point.y = bridge_height
                elevated_path[i] = elevated_point

    return elevated_path

## Calculate distance from a point to a line segment
func _distance_to_line_segment(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> float:
    var segment_vec: Vector3 = segment_end - segment_start
    var point_vec: Vector3 = point - segment_start
    var segment_length_sq: float = segment_vec.length_squared()

    if segment_length_sq == 0.0:
        return point.distance_to(segment_start)

    var t: float = point_vec.dot(segment_vec) / segment_length_sq
    t = clampf(t, 0.0, 1.0)

    var projection: Vector3 = segment_start + segment_vec * t
    return point.distance_to(projection)

## Get water level for a crossing (highest of terrain or sea level)
func _get_water_level_for_crossing(start_pos: Vector3, end_pos: Vector3) -> float:
    if not terrain_generator:
        return 20.0

    var samples: int = max(5, int(start_pos.distance_to(end_pos) / 20.0))  # Sample every ~20m
    var min_terrain_height: float = INF

    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = start_pos.lerp(end_pos, t)
        var h: float = terrain_generator.get_height_at(pos.x, pos.z)
        if h < min_terrain_height:
            min_terrain_height = h

    var sea_level: float = 20.0
    if world_context and world_context.has_method("get_sea_level"):
        sea_level = float(world_context.get_sea_level())
    elif world_context and world_context.has_method("get"):
        var sea_level_val = world_context.get("sea_level")
        if sea_level_val != null:
            sea_level = float(sea_level_val)

    return max(min_terrain_height, sea_level)

## Calculate path length
func _calculate_path_length(path: PackedVector3Array) -> float:
    var length: float = 0.0
    for i in range(path.size() - 1):
        length += path[i].distance_to(path[i + 1])
    return length