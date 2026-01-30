class_name RoadGeometryGenerator
extends RefCounted

## Generates improved road geometry using triangle strips with proper connections

var terrain_generator = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

## Generate road mesh using triangle strips with proper vertex connections and LOD support
func generate_road_mesh(waypoints: PackedVector3Array, width: float, material = null, lod_level: int = 0) -> MeshInstance3D:
    if waypoints.size() < 2:
        return null

    # Apply LOD by reducing the resolution of the path
    var lod_waypoints: PackedVector3Array = _apply_lod_to_path(waypoints, lod_level)

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

        # Use the Y coordinates as provided by the road system
        # The road system should have already adjusted these to follow terrain properly
        # We'll keep the original Y coordinates as set by the road system
        # The road system should have already handled terrain integration

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

## Generate a curved road segment with proper geometry
func generate_curved_road(start_pos: Vector3, control_pos: Vector3, end_pos: Vector3, num_segments: int, width: float, material = null) -> MeshInstance3D:
    var waypoints: PackedVector3Array = _generate_quadratic_bezier_curve(start_pos, control_pos, end_pos, num_segments)
    return generate_road_mesh(waypoints, width, material)

## Generate quadratic Bezier curve points
func _generate_quadratic_bezier_curve(start: Vector3, control: Vector3, end: Vector3, num_points: int) -> PackedVector3Array:
    var points: PackedVector3Array = PackedVector3Array()
    
    for i in range(num_points + 1):
        var t: float = float(i) / float(num_points)
        
        # Quadratic Bezier formula: B(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
        var point: Vector3 = (
            pow(1 - t, 2) * start +
            2 * (1 - t) * t * control +
            pow(t, 2) * end
        )
        
        points.append(point)
    
    return points

## Generate road with adaptive tessellation based on curvature
func generate_adaptive_road(waypoints: PackedVector3Array, width: float, max_curve_angle: float = 15.0, material = null) -> MeshInstance3D:
    var adaptive_waypoints: PackedVector3Array = _adaptive_subdivide_waypoints(waypoints, max_curve_angle)
    return generate_road_mesh(adaptive_waypoints, width, material)

## Adaptively subdivide waypoints based on curvature
func _adaptive_subdivide_waypoints(waypoints: PackedVector3Array, max_curve_angle: float) -> PackedVector3Array:
    if waypoints.size() < 3:
        return waypoints
    
    var result: PackedVector3Array = PackedVector3Array()
    result.append(waypoints[0])
    
    for i in range(1, waypoints.size()):
        var prev_point: Vector3 = waypoints[i - 1]
        var curr_point: Vector3 = waypoints[i]
        
        # Calculate direction vectors
        var segment_dir: Vector3 = (curr_point - prev_point).normalized()
        var segment_length: float = prev_point.distance_to(curr_point)
        
        # If this is the first segment, just add the point
        if i == 1:
            result.append(curr_point)
            continue
        
        # Calculate the angle between the previous segment and current segment
        var prev_segment_dir: Vector3 = Vector3.ZERO
        if i >= 2:
            prev_segment_dir = (waypoints[i - 1] - waypoints[i - 2]).normalized()
        
        if prev_segment_dir != Vector3.ZERO:
            var angle_radians: float = acos(clamp(prev_segment_dir.dot(segment_dir), -1.0, 1.0))
            var angle_degrees: float = rad_to_deg(angle_radians)
            
            # If the turn is sharper than our threshold, subdivide this segment
            if angle_degrees > max_curve_angle:
                # Calculate how many subdivisions we need based on the angle
                var subdivisions: int = int(ceil(angle_degrees / max_curve_angle))
                subdivisions = min(subdivisions, 10)  # Limit subdivisions to prevent excessive geometry
                
                for j in range(1, subdivisions):
                    var t: float = float(j) / float(subdivisions)
                    var subdivided_point: Vector3 = prev_point.lerp(curr_point, t)
                    
                    # Adjust height to follow terrain with consistent offset
                    if terrain_generator != null and terrain_generator.has_method("get_height_at"):
                        subdivided_point.y = terrain_generator.get_height_at(subdivided_point.x, subdivided_point.z) + 0.5  # Consistent offset with other roads
                    
                    result.append(subdivided_point)
            
            result.append(curr_point)
        else:
            result.append(curr_point)
    
    return result