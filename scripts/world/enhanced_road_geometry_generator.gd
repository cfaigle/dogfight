class_name EnhancedRoadGeometryGenerator
extends RefCounted

## Generates enhanced road geometry with adaptive subdivision and proper connection handling
## Addresses issues with roads being broken by terrain, poor bridge connections, and local road gaps

var terrain_generator = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

## Generate road mesh with adaptive subdivision based on terrain variations
func generate_road_mesh_with_adaptive_subdivision(waypoints: PackedVector3Array, width: float, material = null, lod_level: int = 0, subdivision_tolerance: float = 2.0) -> MeshInstance3D:
    if waypoints.size() < 2:
        return null

    # Apply adaptive subdivision based on terrain variations
    var subdivided_waypoints: PackedVector3Array = _adaptive_subdivide_by_terrain(waypoints, subdivision_tolerance)
    
    # Apply LOD if needed
    var lod_waypoints: PackedVector3Array = _apply_lod_to_path(subdivided_waypoints, lod_level)

    # Validate the entire path to ensure no part of the road goes under terrain
    var validated_waypoints: PackedVector3Array = _validate_and_adjust_path_heights(lod_waypoints, width)

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Generate the road geometry as a connected strip
    var road_vertices: Array = []
    var road_normals: Array = []
    var road_uvs: Array = []

    # Calculate all vertices first to ensure proper connections
    for i in range(lod_waypoints.size()):
        var pos: Vector3 = lod_waypoints[i]

        # Determine direction vector for this segment
        var forward: Vector3
        if i == 0:
            # First point: use direction to next point
            forward = (lod_waypoints[1] - lod_waypoints[0]).normalized()
        elif i == lod_waypoints.size() - 1:
            # Last point: use direction from previous point
            forward = (lod_waypoints[i] - lod_waypoints[i-1]).normalized()
        else:
            # Middle points: average of adjacent segments
            var prev_dir: Vector3 = (lod_waypoints[i] - lod_waypoints[i-1]).normalized()
            var next_dir: Vector3 = (lod_waypoints[i+1] - lod_waypoints[i]).normalized()
            forward = (prev_dir + next_dir).normalized()

        # Calculate right vector (perpendicular to forward)
        var right: Vector3 = forward.cross(Vector3.UP).normalized()

        # Calculate left and right edge positions
        var left_pos: Vector3 = pos - right * (width / 2.0)
        var right_pos: Vector3 = pos + right * (width / 2.0)

        # Ensure the Y coordinate follows the terrain precisely with validated height
        if terrain_generator != null:
            # Use proper clearance to ensure roads are always above terrain
            var clearance_height: float = 2.0  # Proper clearance above terrain
            left_pos.y = terrain_generator.get_height_at(left_pos.x, left_pos.z) + clearance_height
            right_pos.y = terrain_generator.get_height_at(right_pos.x, right_pos.z) + clearance_height
            pos.y = terrain_generator.get_height_at(pos.x, pos.z) + clearance_height

        # Store vertices for this waypoint
        road_vertices.append(left_pos)
        road_vertices.append(right_pos)

        # Calculate normals based on actual terrain at the positions
        var left_normal: Vector3 = _get_terrain_normal(left_pos.x, left_pos.z)
        var right_normal: Vector3 = _get_terrain_normal(right_pos.x, right_pos.z)
        var center_normal: Vector3 = _get_terrain_normal(pos.x, pos.z)

        road_normals.append(left_normal)
        road_normals.append(right_normal)

        # Calculate UVs (distance along road)
        var dist_from_start: float = _calculate_distance_to_point(lod_waypoints, i)
        var u_coord: float = dist_from_start * 0.05  # Scale for texture tiling
        road_uvs.append(Vector2(0.0, u_coord))  # Left side
        road_uvs.append(Vector2(1.0, u_coord))  # Right side

    # Create triangles from the vertices
    for i in range(lod_waypoints.size() - 1):
        var idx_current_left = i * 2
        var idx_current_right = i * 2 + 1
        var idx_next_left = (i + 1) * 2
        var idx_next_right = (i + 1) * 2 + 1

        # First triangle (left_current, right_next, right_current)
        st.set_normal(road_normals[idx_current_left])
        st.set_uv(road_uvs[idx_current_left])
        st.add_vertex(road_vertices[idx_current_left])

        st.set_normal(road_normals[idx_next_right])
        st.set_uv(road_uvs[idx_next_right])
        st.add_vertex(road_vertices[idx_next_right])

        st.set_normal(road_normals[idx_current_right])
        st.set_uv(road_uvs[idx_current_right])
        st.add_vertex(road_vertices[idx_current_right])

        # Second triangle (left_current, left_next, right_next)
        st.set_normal(road_normals[idx_current_left])
        st.set_uv(road_uvs[idx_current_left])
        st.add_vertex(road_vertices[idx_current_left])

        st.set_normal(road_normals[idx_next_left])
        st.set_uv(road_uvs[idx_next_left])
        st.add_vertex(road_vertices[idx_next_left])

        st.set_normal(road_normals[idx_next_right])
        st.set_uv(road_uvs[idx_next_right])
        st.add_vertex(road_vertices[idx_next_right])

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    return mesh_instance

## Adaptive subdivision based on terrain elevation differences
func _adaptive_subdivide_by_terrain(waypoints: PackedVector3Array, tolerance: float) -> PackedVector3Array:
    if waypoints.size() < 2 or terrain_generator == null:
        return waypoints.duplicate()

    var result: PackedVector3Array = PackedVector3Array()
    result.append(waypoints[0])

    for i in range(waypoints.size() - 1):
        var start_point: Vector3 = waypoints[i]
        var end_point: Vector3 = waypoints[i + 1]
        
        # Subdivide the segment based on terrain variations
        var segment_points: PackedVector3Array = _subdivide_segment_by_terrain(start_point, end_point, tolerance)
        
        # Add all points except the first (to avoid duplication)
        for j in range(1, segment_points.size()):
            result.append(segment_points[j])

    return result

## Subdivide a single segment based on terrain variations with recursion protection
func _subdivide_segment_by_terrain(start: Vector3, end: Vector3, tolerance: float, max_depth: int = 5, current_depth: int = 0) -> PackedVector3Array:
    var result: PackedVector3Array = PackedVector3Array()
    result.append(start)

    # Prevent infinite recursion by limiting depth
    if current_depth >= max_depth:
        # At max depth, just add the end point with proper terrain clearance
        var end_terrain_height: float = terrain_generator.get_height_at(end.x, end.z)
        var end_road_height: float = end_terrain_height + 2.0  # Ensure clearance
        result.append(Vector3(end.x, end_road_height, end.z))
        return result

    # Calculate the straight-line path and check for terrain deviations
    var distance: float = start.distance_to(end)
    var min_segment_length: float = 5.0  # Minimum segment length to prevent excessive subdivision
    var segment_steps: int = max(2, min(int(distance / min_segment_length), 20))  # Limit subdivision steps

    # Sample intermediate points and check for terrain deviations
    var needs_subdivision: bool = false
    var intermediate_points: Array[Vector3] = []

    for step in range(1, segment_steps):
        var t: float = float(step) / float(segment_steps)
        var intermediate_pos: Vector3 = start.lerp(end, t)

        # Get the terrain height at this position
        var terrain_height: float = terrain_generator.get_height_at(intermediate_pos.x, intermediate_pos.z)
        # Calculate expected height on straight line
        var expected_height: float = lerp(start.y, end.y, t)
        var deviation: float = abs(terrain_height - expected_height)

        if deviation > tolerance:
            needs_subdivision = true
        # Ensure the road point is always above terrain with proper clearance
        var min_clearance: float = 2.0  # Minimum clearance above terrain
        var road_height: float = terrain_height + min_clearance
        intermediate_points.append(Vector3(intermediate_pos.x, road_height, intermediate_pos.z))

    if needs_subdivision:
        # Recursively subdivide each sub-segment with depth tracking
        var last_point: Vector3 = start
        for point in intermediate_points:
            var sub_segment: PackedVector3Array = _subdivide_segment_by_terrain(last_point, point, tolerance, max_depth, current_depth + 1)
            # Add points except the first to avoid duplication
            for i in range(1, sub_segment.size()):
                result.append(sub_segment[i])
            last_point = point

        # Add the final point with proper terrain clearance
        var final_terrain_height: float = terrain_generator.get_height_at(end.x, end.z)
        var final_road_height: float = final_terrain_height + 2.0  # Ensure clearance
        var final_point: Vector3 = Vector3(end.x, final_road_height, end.z)
        var final_segment: PackedVector3Array = _subdivide_segment_by_terrain(last_point, final_point, tolerance, max_depth, current_depth + 1)
        for i in range(1, final_segment.size()):
            result.append(final_segment[i])
    else:
        # If no significant deviation, just add the end point with proper clearance
        var end_terrain_height: float = terrain_generator.get_height_at(end.x, end.z)
        var end_road_height: float = end_terrain_height + 2.0  # Ensure clearance
        result.append(Vector3(end.x, end_road_height, end.z))

    return result

## Calculate distance along the path to a specific point
func _calculate_distance_to_point(waypoints: PackedVector3Array, target_index: int) -> float:
    var total_distance: float = 0.0

    for i in range(target_index):
        total_distance += waypoints[i].distance_to(waypoints[i + 1])

    return total_distance

## Apply LOD to path by reducing resolution based on LOD level
func _apply_lod_to_path(path: PackedVector3Array, lod_level: int) -> PackedVector3Array:
    if lod_level <= 0 or path.size() <= 2:
        return path.duplicate()  # Full detail for LOD 0

    var reduced_path: PackedVector3Array = PackedVector3Array()

    # Always include first and last points
    reduced_path.append(path[0])

    # Calculate step size based on LOD level
    var step_size: int = 1
    match lod_level:
        1: step_size = 2  # LOD 1: every 2nd point
        2: step_size = 4  # LOD 2: every 4th point
        3: step_size = 8  # LOD 3: every 8th point
        _: step_size = max(2, lod_level)  # For higher LOD levels

    # Add points at intervals based on LOD level
    for i in range(step_size, path.size() - 1, step_size):
        reduced_path.append(path[i])

    # Always include last point
    if path.size() > 1:
        reduced_path.append(path[-1])

    return reduced_path

## Get terrain normal at a given position for proper lighting
func _get_terrain_normal(x: float, z: float) -> Vector3:
    if terrain_generator == null or not terrain_generator.has_method("get_height_at") or not terrain_generator.has_method("get_normal_at"):
        return Vector3.UP

    # Use the terrain generator's normal function if available
    if terrain_generator.has_method("get_normal_at"):
        return terrain_generator.get_normal_at(x, z)

    # Fallback: calculate normal from height differences
    var sample_dist: float = 2.0
    var h_center: float = terrain_generator.get_height_at(x, z)
    var h_right: float = terrain_generator.get_height_at(x + sample_dist, z)
    var h_forward: float = terrain_generator.get_height_at(x, z + sample_dist)

    # Calculate tangent vectors
    var right_vec: Vector3 = Vector3(sample_dist, h_right - h_center, 0.0)
    var forward_vec: Vector3 = Vector3(0.0, h_forward - h_center, sample_dist)

    # Cross product gives normal
    var normal: Vector3 = forward_vec.cross(right_vec).normalized()

    # Ensure normal points upward
    if normal.y < 0.0:
        normal = -normal

    return normal

## Generate bridge with proper connection to road geometry
func generate_bridge_with_road_continuity(start_pos: Vector3, end_pos: Vector3, width: float, road_material = null, bridge_material = null) -> MeshInstance3D:
    if terrain_generator == null:
        return null

    # Get terrain heights at connection points to ensure proper alignment
    var start_terrain_height: float = terrain_generator.get_height_at(start_pos.x, start_pos.z)
    var end_terrain_height: float = terrain_generator.get_height_at(end_pos.x, end_pos.z)
    
    # Adjust connection points to match terrain height
    var adjusted_start: Vector3 = Vector3(start_pos.x, start_terrain_height + 0.1, start_pos.z)
    var adjusted_end: Vector3 = Vector3(end_pos.x, end_terrain_height + 0.1, end_pos.z)
    
    # Create bridge geometry that connects smoothly to road elevation
    return _create_proper_bridge_geometry(adjusted_start, adjusted_end, width, bridge_material)

## Create proper bridge geometry with smooth connections
func _create_proper_bridge_geometry(start: Vector3, end: Vector3, width: float, material = null) -> MeshInstance3D:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Calculate bridge direction and perpendicular vectors
    var direction: Vector3 = (end - start).normalized()
    var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5

    # Create bridge deck with proper elevation matching
    var segments: int = max(2, int(start.distance_to(end) / 20.0))  # Segment based on length
    var segment_length: float = start.distance_to(end) / float(segments)

    for i in range(segments):
        var t0: float = float(i) / float(segments)
        var t1: float = float(i + 1) / float(segments)

        var pos0: Vector3 = start.lerp(end, t0)
        var pos1: Vector3 = start.lerp(end, t1)

        # Calculate bridge height (maintaining connection to road elevation)
        var height0: float = lerp(start.y, end.y, t0)
        var height1: float = lerp(start.y, end.y, t1)

        var deck_left0: Vector3 = Vector3(pos0.x, height0, pos0.z) - right
        var deck_right0: Vector3 = Vector3(pos0.x, height0, pos0.z) + right
        var deck_left1: Vector3 = Vector3(pos1.x, height1, pos1.z) - right
        var deck_right1: Vector3 = Vector3(pos1.x, height1, pos1.z) + right

        # Add deck surface
        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_right1)
        st.add_vertex(deck_right0)

        st.set_normal(Vector3.UP)
        st.add_vertex(deck_left0)
        st.add_vertex(deck_left1)
        st.add_vertex(deck_right1)

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    return mesh_instance

## Generate road with smooth connections between segments for local roads
func generate_connected_local_road(waypoints: PackedVector3Array, width: float, material = null) -> MeshInstance3D:
    if waypoints.size() < 2:
        return null

    # Ensure continuity by using shared vertices at connection points
    var processed_waypoints: PackedVector3Array = _ensure_local_road_continuity(waypoints)
    
    return generate_road_mesh_with_adaptive_subdivision(processed_waypoints, width, material, 0, 1.5)

## Ensure continuity in local road networks by matching connection points
func _ensure_local_road_continuity(waypoints: PackedVector3Array) -> PackedVector3Array:
    if waypoints.size() < 2 or terrain_generator == null:
        return waypoints.duplicate()

    var result: PackedVector3Array = PackedVector3Array()

    for i in range(waypoints.size()):
        var point: Vector3 = waypoints[i]
        # Ensure each point follows the terrain precisely
        var terrain_height: float = terrain_generator.get_height_at(point.x, point.z)
        result.append(Vector3(point.x, terrain_height + 0.1, point.z))

    return result

## Validate entire path to ensure no part of road goes under terrain (optimized version with validation levels)
func _validate_and_adjust_path_heights(waypoints: PackedVector3Array, road_width: float, validation_level: int = 1) -> PackedVector3Array:
    if waypoints.size() < 2 or terrain_generator == null:
        return waypoints.duplicate()

    var validated_path: PackedVector3Array = waypoints.duplicate()

    # Performance optimization: different validation levels for different performance needs
    var max_samples_per_segment: int
    var min_sample_distance: float

    match validation_level:
        0:  # Minimal validation - only check endpoints and midpoint
            # For minimal validation, just ensure endpoints are above terrain
            for i in range(waypoints.size()):
                var point: Vector3 = validated_path[i]
                var terrain_height: float = terrain_generator.get_height_at(point.x, point.z)
                if point.y <= terrain_height:
                    validated_path[i].y = terrain_height + 2.0  # Add clearance
            return validated_path
        1:  # Basic validation (default) - limited samples
            max_samples_per_segment = 4
            min_sample_distance = 30.0
        2:  # Detailed validation - more samples
            max_samples_per_segment = 8
            min_sample_distance = 20.0
        3:  # Maximum validation - most samples
            max_samples_per_segment = 12
            min_sample_distance = 15.0
        _:  # Default to basic validation
            max_samples_per_segment = 4
            min_sample_distance = 30.0

    # For each segment, check if the road intersects with terrain
    for i in range(waypoints.size() - 1):
        var start_point: Vector3 = validated_path[i]
        var end_point: Vector3 = validated_path[i + 1]

        # Sample intermediate points along the segment to check for terrain intersections
        var segment_length: float = start_point.distance_to(end_point)
        var sample_distance: float = max(min_sample_distance, segment_length / float(max_samples_per_segment))
        var num_samples: int = max(2, min(max_samples_per_segment, int(segment_length / sample_distance)))

        var max_terrain_height: float = max(start_point.y, end_point.y)  # Start with current road height

        # Check terrain height at intermediate points along the segment
        for j in range(1, num_samples):  # Skip first and last since we already have those
            var t: float = float(j) / float(num_samples)
            var sample_pos: Vector3 = start_point.lerp(end_point, t)

            # Check terrain height at center and edges of road (performance: cache terrain queries)
            var center_terrain_height: float = terrain_generator.get_height_at(sample_pos.x, sample_pos.z)

            # Calculate perpendicular vector once for efficiency
            var direction: Vector3 = (end_point - start_point).normalized()
            var right: Vector3 = direction.cross(Vector3.UP).normalized()

            var right_edge_pos: Vector3 = sample_pos + right * (road_width / 2.0)
            var left_edge_pos: Vector3 = sample_pos - right * (road_width / 2.0)

            var right_terrain_height: float = terrain_generator.get_height_at(right_edge_pos.x, right_edge_pos.z)
            var left_terrain_height: float = terrain_generator.get_height_at(left_edge_pos.x, left_edge_pos.z)

            # Find the maximum terrain height that the road needs to clear
            var segment_max_height: float = max(center_terrain_height, max(right_terrain_height, left_terrain_height))
            max_terrain_height = max(max_terrain_height, segment_max_height)

        # If the terrain is higher than the planned road height, adjust the road height for this segment
        var required_height: float = max_terrain_height + 2.0  # Add 2m clearance
        if required_height > start_point.y:
            validated_path[i].y = required_height
        if required_height > end_point.y:
            validated_path[i + 1].y = required_height

    return validated_path