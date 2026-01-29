class_name RoadLODManager
extends RefCounted

## Manages Level of Detail for road networks to optimize rendering performance

var roads_root: Node3D = null
var road_segments: Array = []
var lod_distances: Dictionary = {
    "lod0_max_distance": 500.0,   # Full detail up to 500m
    "lod1_max_distance": 1500.0,  # Medium detail up to 1500m
    "lod2_max_distance": 3000.0,  # Low detail up to 3000m
    "lod3_max_distance": INF      # Very low detail beyond 3000m
}

var lod_meshes: Dictionary = {}  # Stores different LOD levels for each road segment
var terrain_generator = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

func set_roads_root(root_node: Node3D) -> void:
    roads_root = root_node

func set_lod_distances(lod_settings: Dictionary) -> void:
    lod_distances = lod_settings

## Initialize LOD system for road segments
func initialize_lod_for_roads(road_segments_array: Array, camera_position: Vector3) -> void:
    road_segments = road_segments_array

    # Create LOD meshes for each road segment
    for i in range(road_segments.size()):
        var segment: Dictionary = road_segments[i]
        var path: PackedVector3Array = segment.get("path", PackedVector3Array())
        var width: float = segment.get("width", 8.0)
        var road_type: String = segment.get("type", "local")
        var material = segment.get("material", null)

        if path.size() >= 2:
            # Create different LOD levels for this segment
            var lod_meshes_for_segment: Dictionary = {}

            # LOD 0: Full detail (original)
            lod_meshes_for_segment[0] = _create_lod0_mesh(path, width, material)

            # LOD 1: Medium detail (reduce resolution by 2x)
            var lod1_path: PackedVector3Array = _create_lod_path(path, 2)
            lod_meshes_for_segment[1] = _create_lod1_mesh(lod1_path, width, material)

            # LOD 2: Low detail (reduce resolution by 4x)
            var lod2_path: PackedVector3Array = _create_lod_path(lod1_path, 2)  # Further reduce from lod1
            lod_meshes_for_segment[2] = _create_lod2_mesh(lod2_path, width, material)

            # LOD 3: Very low detail (simplified to 2 points)
            var lod3_path: PackedVector3Array = PackedVector3Array([path[0], path[-1]])  # Just endpoints
            lod_meshes_for_segment[3] = _create_lod3_mesh(lod3_path, width, material)

            lod_meshes[str(i)] = lod_meshes_for_segment

## Update LOD visibility based on camera position
func update_lod_visibility(camera_position: Vector3) -> void:
    if roads_root == null:
        return

    for i in range(road_segments.size()):
        var segment: Dictionary = road_segments[i]
        var segment_center: Vector3 = _get_segment_center(segment)
        var distance: float = camera_position.distance_to(segment_center)

        # Determine appropriate LOD level based on distance
        var lod_level: int = _get_lod_level_for_distance(distance)

        # Create LOD nodes if they don't exist yet
        for lod_idx in range(4):
            var lod_node_name: String = "RoadSegment_%d_LOD%d" % [i, lod_idx]
            var lod_node: Node3D = roads_root.get_node_or_null(NodePath(lod_node_name))

            if lod_node == null:
                # Create the LOD node if it doesn't exist
                if lod_meshes.has(str(i)) and lod_meshes[str(i)].has(lod_idx):
                    var mesh_instance: MeshInstance3D = lod_meshes[str(i)][lod_idx]
                    if mesh_instance:
                        mesh_instance.name = lod_node_name
                        roads_root.add_child(mesh_instance)
                        lod_node = mesh_instance

        # Hide all LODs for this segment first
        for lod_idx in range(4):
            var lod_node_name: String = "RoadSegment_%d_LOD%d" % [i, lod_idx]
            var lod_node: Node3D = roads_root.get_node_or_null(NodePath(lod_node_name))
            if lod_node:
                lod_node.visible = (lod_idx == lod_level)  # Only show the selected LOD

## Get appropriate LOD level for distance
func _get_lod_level_for_distance(distance: float) -> int:
    if distance <= lod_distances.get("lod0_max_distance", 500.0):
        return 0  # Full detail
    elif distance <= lod_distances.get("lod1_max_distance", 1500.0):
        return 1  # Medium detail
    elif distance <= lod_distances.get("lod2_max_distance", 3000.0):
        return 2  # Low detail
    else:
        return 3  # Very low detail

## Create LOD0 (full detail) mesh
func _create_lod0_mesh(path: PackedVector3Array, width: float, material) -> MeshInstance3D:
    # This would use the full-resolution path
    # For now, return a simplified version - in a full implementation this would use the actual road geometry generator
    return _create_basic_road_mesh(path, width, material)

## Create LOD1 (medium detail) mesh
func _create_lod1_mesh(path: PackedVector3Array, width: float, material) -> MeshInstance3D:
    return _create_basic_road_mesh(path, width, material)

## Create LOD2 (low detail) mesh
func _create_lod2_mesh(path: PackedVector3Array, width: float, material) -> MeshInstance3D:
    return _create_basic_road_mesh(path, width, material)

## Create LOD3 (very low detail) mesh
func _create_lod3_mesh(path: PackedVector3Array, width: float, material) -> MeshInstance3D:
    return _create_basic_road_mesh(path, width, material)

## Create basic road mesh for LOD
func _create_basic_road_mesh(path: PackedVector3Array, width: float, material) -> MeshInstance3D:
    if path.size() < 2:
        return null
    
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    var road_offset: float = 0.1  # Small offset above terrain
    
    for i in range(path.size() - 1):
        var p0: Vector3 = path[i]
        var p1: Vector3 = path[i + 1]
        
        # Calculate direction and perpendicular vectors
        var direction: Vector3 = (p1 - p0).normalized()
        var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
        
        # Calculate terrain height at each point
        var h0: float = 0.0
        var h1: float = 0.0
        if terrain_generator:
            h0 = terrain_generator.get_height_at(p0.x, p0.z) + road_offset
            h1 = terrain_generator.get_height_at(p1.x, p1.z) + road_offset
        else:
            h0 = p0.y + road_offset
            h1 = p1.y + road_offset
        
        var v0_left: Vector3 = Vector3(p0.x, h0, p0.z) - right
        var v0_right: Vector3 = Vector3(p0.x, h0, p0.z) + right
        var v1_left: Vector3 = Vector3(p1.x, h1, p1.z) - right
        var v1_right: Vector3 = Vector3(p1.x, h1, p1.z) + right
        
        # Add triangles
        st.set_normal(Vector3.UP)
        st.add_vertex(v0_left)
        st.add_vertex(v1_right)
        st.add_vertex(v0_right)
        
        st.set_normal(Vector3.UP)
        st.add_vertex(v0_left)
        st.add_vertex(v1_left)
        st.add_vertex(v1_right)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    return mesh_instance

## Create reduced resolution path for LOD
func _create_lod_path(full_path: PackedVector3Array, reduction_factor: int) -> PackedVector3Array:
    if full_path.size() <= 2 or reduction_factor <= 1:
        return full_path.duplicate()
    
    var lod_path: PackedVector3Array = PackedVector3Array()
    
    # Always include first and last points
    lod_path.append(full_path[0])
    
    # Add points at intervals based on reduction factor
    var step: int = max(1, reduction_factor)
    for i in range(step, full_path.size() - 1, step):
        lod_path.append(full_path[i])
    
    # Always include last point
    if full_path.size() > 1:
        lod_path.append(full_path[-1])
    
    return lod_path

## Get center of a road segment for distance calculations
func _get_segment_center(segment: Dictionary) -> Vector3:
    var path: PackedVector3Array = segment.get("path", PackedVector3Array())
    if path.size() == 0:
        return Vector3.ZERO
    elif path.size() == 1:
        return path[0]
    else:
        # Return midpoint of the path
        return path[0].lerp(path[-1], 0.5)

## Update camera position for LOD management
func update_camera_position(camera_pos: Vector3) -> void:
    update_lod_visibility(camera_pos)

## Get current LOD statistics
func get_lod_stats() -> Dictionary:
    var stats: Dictionary = {
        "total_segments": road_segments.size(),
        "visible_lod0": 0,
        "visible_lod1": 0,
        "visible_lod2": 0,
        "visible_lod3": 0
    }
    
    if roads_root == null:
        return stats
    
    # Count visible segments at each LOD level
    for i in range(road_segments.size()):
        for lod_level in range(4):
            var lod_node_name: String = "RoadSegment_%d_LOD%d" % [i, lod_level]
            var lod_node: Node3D = roads_root.get_node_or_null(NodePath(lod_node_name))
            if lod_node and lod_node.visible:
                match lod_level:
                    0: stats.visible_lod0 += 1
                    1: stats.visible_lod1 += 1
                    2: stats.visible_lod2 += 1
                    3: stats.visible_lod3 += 1
    
    return stats