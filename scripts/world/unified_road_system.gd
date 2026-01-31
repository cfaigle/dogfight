class_name UnifiedRoadSystem
extends RefCounted

## Unified road system that handles all road generation with proper bridge detection and tessellated rendering

var terrain_generator = null
var world_context = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

func set_world_context(world_ctx) -> void:
    world_context = world_ctx

## Generate complete road network with proper bridges and tessellated rendering
func generate_complete_road_network(settlements: Array, params: Dictionary) -> Dictionary:
    var result: Dictionary = {
        "success": false,
        "road_segments": [],
        "generation_stats": {
            "total_segments": 0,
            "bridges_created": 0,
            "segments_skipped": 0
        },
        "errors": []
    }

    if settlements.size() < 2:
        result.errors.append("Need at least 2 settlements for road network")
        return result

    # Build road network using MST + extra connections
    var road_segments: Array = _build_road_network(settlements, params)
    
    # Process segments to detect water crossings and create appropriate bridges
    var processed_segments: Array = _process_road_segments(road_segments, params)
    
    result.success = true
    result.road_segments = processed_segments
    result.generation_stats.total_segments = processed_segments.size()
    
    return result

## Build the basic road network using MST algorithm
func _build_road_network(settlements: Array, params: Dictionary) -> Array:
    var segments: Array = []
    
    # Create candidate edges between settlements
    var candidate_edges: Array = _build_candidate_edges(settlements, params)
    
    # Build MST (Minimum Spanning Tree) to ensure all settlements are connected
    var mst_edges: Array = _build_mst(candidate_edges, settlements)
    
    # Add extra edges for redundancy and better connectivity
    var extra_edges: Array = _add_extra_connections(mst_edges, candidate_edges, params)
    
    # Convert edges to road segments
    for edge in extra_edges:
        var from_pos: Vector3 = edge.from
        var to_pos: Vector3 = edge.to
        
        segments.append({
            "from": from_pos,
            "to": to_pos,
            "type": edge.type if edge.has("type") else "local",
            "width": edge.width if edge.has("width") else float(params.get("road_width", 18.0))
        })
    
    return segments

## Build candidate edges between settlements
func _build_candidate_edges(settlements: Array, params: Dictionary) -> Array:
    var edges: Array = []
    var n: int = settlements.size()
    
    for i in range(n):
        var si: Dictionary = settlements[i] if settlements[i] is Dictionary else {"center": settlements[i]}
        var from_pos: Vector3 = si.get("center", si.get("position", Vector3.ZERO))
        
        # Connect to nearby settlements
        for j in range(i + 1, n):
            var sj: Dictionary = settlements[j] if settlements[j] is Dictionary else {"center": settlements[j]}
            var to_pos: Vector3 = sj.get("center", sj.get("position", Vector3.ZERO))
            
            var dist: float = from_pos.distance_to(to_pos)
            
            # Skip if too far apart (based on parameters)
            var max_dist: float = float(params.get("max_road_connection_distance", 8000.0))
            if dist > max_dist:
                continue
            
            # Calculate connection weight (considering terrain difficulty)
            var weight: float = _calculate_connection_weight(from_pos, to_pos, params)
            
            edges.append({
                "from": from_pos,
                "to": to_pos,
                "weight": weight,
                "distance": dist,
                "from_idx": i,
                "to_idx": j
            })
    
    return edges

## Calculate connection weight considering terrain factors
func _calculate_connection_weight(from_pos: Vector3, to_pos: Vector3, params: Dictionary) -> float:
    var base_weight: float = from_pos.distance_to(to_pos)
    
    # Add penalties for difficult terrain
    var slope_penalty: float = _estimate_slope_penalty(from_pos, to_pos)
    var water_penalty: float = _estimate_water_penalty(from_pos, to_pos, params)
    
    return base_weight + slope_penalty + water_penalty

## Estimate slope penalty along the path
func _estimate_slope_penalty(from_pos: Vector3, to_pos: Vector3) -> float:
    if terrain_generator == null:
        return 0.0
    
    var penalty: float = 0.0
    var samples: int = 10  # Number of points to sample along the path
    
    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = from_pos.lerp(to_pos, t)
        
        var slope: float = terrain_generator.get_slope_at(pos.x, pos.z)
        if slope > 20.0:  # High slope penalty
            penalty += slope * 2.0
    
    return penalty / float(samples + 1)

## Estimate water crossing penalty
func _estimate_water_penalty(from_pos: Vector3, to_pos: Vector3, params: Dictionary) -> float:
    if terrain_generator == null:
        return 0.0
    
    var penalty: float = 0.0
    var samples: int = 10  # Number of points to sample along the path
    var sea_level: float = float(params.get("sea_level", 20.0))
    
    for i in range(samples + 1):
        var t: float = float(i) / float(samples)
        var pos: Vector3 = from_pos.lerp(to_pos, t)
        
        var height: float = terrain_generator.get_height_at(pos.x, pos.z)
        
        # Check if this point is below sea level (water)
        if height < sea_level - 1.0:
            penalty += 100.0  # High penalty for water crossings
    
    return penalty / float(samples + 1)

## Build MST using Kruskal's algorithm
func _build_mst(edges: Array, settlements: Array) -> Array:
    # Sort edges by weight
    var sorted_edges: Array = edges.duplicate()
    sorted_edges.sort_custom(func(a, b): return a.weight < b.weight)
    
    # Union-Find for cycle detection
    var parent: Array = []
    parent.resize(settlements.size())
    for i in range(settlements.size()):
        parent[i] = i
    
    var find_root = func(x: int) -> int:
        var root: int = x
        while parent[root] != root:
            root = parent[root]
        # Path compression
        var node: int = x
        while node != root:
            var next: int = parent[node]
            parent[node] = root
            node = next
        return root
    
    var union = func(x: int, y: int) -> void:
        var rx: int = find_root.call(x)
        var ry: int = find_root.call(y)
        if rx != ry:
            parent[rx] = ry
    
    var mst: Array = []
    for edge in sorted_edges:
        var from_idx: int = edge.from_idx
        var to_idx: int = edge.to_idx
        
        if find_root.call(from_idx) != find_root.call(to_idx):
            mst.append(edge)
            union.call(from_idx, to_idx)
            
            if mst.size() >= settlements.size() - 1:
                break
    
    return mst

## Add extra connections for better network connectivity
func _add_extra_connections(mst_edges: Array, all_edges: Array, params: Dictionary) -> Array:
    var result: Array = mst_edges.duplicate()
    
    # Sort all edges by weight
    var sorted_edges: Array = all_edges.duplicate()
    sorted_edges.sort_custom(func(a, b): return a.weight < b.weight)
    
    # Add extra edges up to a certain limit
    var max_extra: int = int(float(mst_edges.size()) * float(params.get("extra_road_connectivity", 0.5)))
    var added: int = 0
    
    for edge in sorted_edges:
        # Check if this edge is already in MST
        var exists: bool = false
        for mst_edge in mst_edges:
            if (mst_edge.from_idx == edge.from_idx and mst_edge.to_idx == edge.to_idx) or \
               (mst_edge.from_idx == edge.to_idx and mst_edge.to_idx == edge.from_idx):
                exists = true
                break
        
        if not exists and added < max_extra:
            result.append(edge)
            added += 1
    
    return result

## Process road segments to create actual paths and detect bridges
func _process_road_segments(segments: Array, params: Dictionary) -> Array:
    var processed_segments: Array = []
    var bridge_count: int = 0
    
    for segment in segments:
        # Generate actual path using A* or straight line
        var path: PackedVector3Array = _generate_path(segment.from, segment.to, params)
        
        if path.size() < 2:
            continue  # Skip invalid segments
        
        # Detect water crossings in the path
        var water_crossings: Array = _detect_water_crossings_in_path(path, params)
        
        if water_crossings.size() > 0:
            # Split the path into land sections and water sections (bridges)
            var split_segments: Array = _split_path_by_water_crossings(path, water_crossings, segment)
            
            for split_segment in split_segments:
                processed_segments.append(split_segment)
                if split_segment.get("is_bridge", false):
                    bridge_count += 1
        else:
            # Regular land road
            processed_segments.append({
                "path": path,
                "width": segment.width,
                "type": segment.type,
                "from": segment.from,
                "to": segment.to,
                "is_bridge": false
            })
    
    return processed_segments

## Generate path between two points with dynamic height adjustment to ensure visibility above terrain
func _generate_path(start: Vector3, end: Vector3, params: Dictionary) -> PackedVector3Array:
    if terrain_generator == null:
        # Fallback to straight line
        return PackedVector3Array([start, end])

    # Use a simple straight-line path with terrain height sampling
    # In a more advanced system, this would use A* pathfinding
    var distance: float = start.distance_to(end)
    var min_segment_length: float = 20.0  # Minimum distance between path points
    var num_segments: int = max(2, int(distance / min_segment_length))

    var path: PackedVector3Array = PackedVector3Array()
    path.resize(num_segments + 1)

    # Calculate a safe height offset that ensures roads are always visible above terrain
    var min_clearance: float = 2.0  # Minimum clearance above terrain for visibility
    var adaptive_clearance: float = float(params.get("road_terrain_clearance", 2.0))

    for i in range(num_segments + 1):
        var t: float = float(i) / float(num_segments)
        var pos: Vector3 = start.lerp(end, t)

        # Sample terrain height at this position
        var terrain_height: float = terrain_generator.get_height_at(pos.x, pos.z)

        # Calculate road height with sufficient clearance above terrain
        # This ensures roads are always visible regardless of terrain irregularities
        var road_height: float = terrain_height + max(min_clearance, adaptive_clearance)

        # Additional check: if this is a bridge (over water), ensure proper clearance
        var sea_level: float = float(params.get("sea_level", 20.0))
        if terrain_height < sea_level - 1.0:  # If over water
            var water_clearance: float = float(params.get("bridge_clearance", 8.0))
            road_height = max(road_height, sea_level + water_clearance)

        pos.y = road_height

        path[i] = pos

    return path

## Detect water crossings in a path
func _detect_water_crossings_in_path(path: PackedVector3Array, params: Dictionary) -> Array:
    var water_crossings: Array = []
    var sea_level: float = float(params.get("sea_level", 20.0))
    
    if path.size() < 2:
        return water_crossings
    
    var in_water: bool = false
    var crossing_start_idx: int = -1
    
    for i in range(path.size()):
        var pos: Vector3 = path[i]
        var height: float = terrain_generator.get_height_at(pos.x, pos.z)
        
        var is_water: bool = height < (sea_level - 1.0)  # Allow 1m buffer
        
        if is_water and not in_water:
            # Start of water crossing
            crossing_start_idx = i
            in_water = true
        elif not is_water and in_water:
            # End of water crossing
            water_crossings.append({
                "start_idx": crossing_start_idx,
                "end_idx": i - 1,
                "start_pos": path[crossing_start_idx],
                "end_pos": path[i - 1]
            })
            in_water = false
            crossing_start_idx = -1
    
    # Handle crossing that extends to end of path
    if in_water and crossing_start_idx >= 0:
        water_crossings.append({
            "start_idx": crossing_start_idx,
            "end_idx": path.size() - 1,
            "start_pos": path[crossing_start_idx],
            "end_pos": path[-1]
        })
    
    return water_crossings

## Split path by water crossings
func _split_path_by_water_crossings(path: PackedVector3Array, water_crossings: Array, original_segment: Dictionary) -> Array:
    var segments: Array = []
    var current_start_idx: int = 0
    
    for crossing in water_crossings:
        var water_start_idx: int = crossing.start_idx
        var water_end_idx: int = crossing.end_idx
        
        # Add land segment before water crossing
        if water_start_idx > current_start_idx:
            var land_path: PackedVector3Array = _extract_path_segment(path, current_start_idx, water_start_idx - 1)
            if land_path.size() >= 2:
                segments.append({
                    "path": land_path,
                    "width": original_segment.width,
                    "type": original_segment.type,
                    "from": land_path[0],
                    "to": land_path[-1],
                    "is_bridge": false
                })

        # Add bridge for water crossing
        var bridge_path: PackedVector3Array = _extract_path_segment(path, water_start_idx, water_end_idx)
        if bridge_path.size() >= 2:
            segments.append({
                "path": bridge_path,
                "width": original_segment.width,
                "type": original_segment.type,
                "from": bridge_path[0],
                "to": bridge_path[-1],
                "is_bridge": true
            })

        # Update start index for next land segment
        current_start_idx = water_end_idx

    # Add final land segment after last water crossing
    if current_start_idx < path.size() - 1:
        var remaining_path: PackedVector3Array = _extract_path_segment(path, current_start_idx, path.size() - 1)
        if remaining_path.size() >= 2:
            segments.append({
                "path": remaining_path,
                "width": original_segment.width,
                "type": original_segment.type,
                "from": remaining_path[0],
                "to": remaining_path[-1],
                "is_bridge": false
            })

    return segments

## Extract a segment of a path
func _extract_path_segment(full_path: PackedVector3Array, start_idx: int, end_idx: int) -> PackedVector3Array:
    var segment: PackedVector3Array = PackedVector3Array()
    
    var clamped_start: int = clamp(start_idx, 0, full_path.size() - 1)
    var clamped_end: int = clamp(end_idx, clamped_start, full_path.size() - 1)
    
    for i in range(clamped_start, clamped_end + 1):
        segment.append(full_path[i])
    
    return segment

## Create tessellated road mesh using EnhancedRoadGeometryGenerator with adaptive subdivision
func create_tessellated_road_mesh(path: PackedVector3Array, width: float, road_type: String, material: Material = null) -> MeshInstance3D:
    if path.size() < 2:
        return null

    # Use the EnhancedRoadGeometryGenerator for proper tessellated rendering with adaptive subdivision
    var geometry_generator = load("res://scripts/world/enhanced_road_geometry_generator.gd").new()
    if terrain_generator:
        geometry_generator.set_terrain_generator(terrain_generator)

    # Determine LOD level and subdivision tolerance based on road type
    var lod_level: int = 0
    var subdivision_tolerance: float = 2.0  # Default tolerance
    match road_type:
        "highway":
            lod_level = 2
            subdivision_tolerance = 3.0  # Highway can have slightly more tolerance
        "arterial":
            lod_level = 1
            subdivision_tolerance = 2.5
        "local":
            lod_level = 0
            subdivision_tolerance = 1.5  # Local roads need more precision
        "bridge":
            lod_level = 1  # Bridges need good detail
            subdivision_tolerance = 2.0

    # Generate road mesh with validated height adjustment to ensure no part goes under terrain
    var road_mesh: MeshInstance3D = geometry_generator.generate_road_mesh_with_adaptive_subdivision(path, width, material, lod_level, subdivision_tolerance)

    # Validate the entire path to ensure no part of the road goes under terrain (with performance monitoring)
    if road_mesh != null and terrain_generator != null:
        print_verbose("   🛣️ Validating road path for terrain collision avoidance...")
        var start_time = Time.get_ticks_usec()

        var validated_path: PackedVector3Array = geometry_generator._validate_and_adjust_path_heights(path, width, 1)  # Use basic validation level

        var end_time = Time.get_ticks_usec()
        var duration_ms = (end_time - start_time) / 1000.0
        print_verbose("   🛣️ Path validation completed in %.2f ms" % duration_ms)

        # Regenerate the mesh with validated path if needed
        if validated_path != path:
            print_verbose("   🛣️ Regenerating road mesh with validated path...")
            road_mesh = geometry_generator.generate_road_mesh_with_adaptive_subdivision(validated_path, width, material, lod_level, subdivision_tolerance)

    return road_mesh

## Create bridge mesh with proper road connection
func create_bridge_mesh(start_pos: Vector3, end_pos: Vector3, width: float, material: Material = null) -> MeshInstance3D:
    # Use the BridgeManager for proper bridge creation with road continuity
    var bridge_manager = load("res://scripts/world/bridge_manager.gd").new()
    if terrain_generator:
        bridge_manager.set_terrain_generator(terrain_generator)
    if world_context:
        bridge_manager.set_world_context(world_context)

    return bridge_manager.create_bridge(start_pos, end_pos, width, material)