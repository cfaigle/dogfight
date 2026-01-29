class_name RoadSystemManager
extends RefCounted

## Main manager that integrates all road system components

var road_graph: RoadGraph = null
var geometry_generator: RoadGeometryGenerator = null
var intersection_generator: IntersectionGeometryGenerator = null
var terrain_carver: TerrainCarver = null
var elevation_adjuster: RoadElevationAdjuster = null
var navigation_system: RoadNavigationSystem = null

var terrain_generator = null
var world_context = null

func _init():
    road_graph = RoadGraph.new()
    geometry_generator = RoadGeometryGenerator.new()
    intersection_generator = IntersectionGeometryGenerator.new()
    terrain_carver = TerrainCarver.new()
    elevation_adjuster = RoadElevationAdjuster.new()
    navigation_system = RoadNavigationSystem.new()

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen
    
    # Propagate to all components that need it
    if geometry_generator:
        geometry_generator.set_terrain_generator(terrain_gen)
    if intersection_generator:
        intersection_generator.set_terrain_generator(terrain_gen)
    if terrain_carver:
        terrain_carver.set_terrain_generator(terrain_gen)
    if elevation_adjuster:
        elevation_adjuster.set_terrain_generator(terrain_gen)
    if navigation_system:
        navigation_system.set_terrain_generator(terrain_gen)

func set_world_context(world_ctx) -> void:
    world_context = world_ctx
    
    # Propagate to all components that need it
    if elevation_adjuster:
        elevation_adjuster.set_world_context(world_ctx)
    if navigation_system:
        navigation_system.set_world_context(world_ctx)

## Generate a complete road network for a set of settlements
func generate_complete_road_network(settlements: Array, params: Dictionary = {}) -> Dictionary:
    var generation_result: Dictionary = {
        "success": false,
        "road_segments": [],
        "intersections": [],
        "navigation_graph": null,
        "generation_stats": {},
        "errors": []
    }
    
    if settlements.size() < 2:
        generation_result.errors.append("Need at least 2 settlements to generate road network")
        return generation_result
    
    print("🏗️ Starting road network generation for %d settlements" % settlements.size())
    
    # Step 1: Create initial road segments based on settlements
    var road_segments: Array = []
    
    for i in range(settlements.size()):
        for j in range(i + 1, settlements.size()):
            var settlement_a: Dictionary = settlements[i]
            var settlement_b: Dictionary = settlements[j]
            
            var start_pos: Vector3 = settlement_a.get("center", Vector3.ZERO)
            var end_pos: Vector3 = settlement_b.get("center", Vector3.ZERO)
            
            if start_pos != Vector3.ZERO and end_pos != Vector3.ZERO:
                # Determine road type based on settlement sizes
                var road_type: String = _determine_road_type(settlement_a, settlement_b)
                var width: float = _get_road_width_for_type(road_type)
                
                # Create initial road segment
                var segment: Dictionary = {
                    "from": start_pos,
                    "to": end_pos,
                    "type": road_type,
                    "width": width
                }
                
                road_segments.append(segment)
    
    # Step 2: Process each road segment with advanced techniques
    print("⛰️ Processing road segments with terrain integration...")
    var processed_segments: Array = []
    for segment in road_segments:
        var processed_segment: Dictionary = _process_road_segment(segment, params)
        if processed_segment != null:
            processed_segments.append(processed_segment)
    
    # Step 3: Convert to navigable graph
    print("🧭 Converting to navigation graph...")
    var navigation_graph: RoadGraph = navigation_system.convert_road_data_to_graph(processed_segments)
    
    # Step 4: Generate geometry for visualization
    print("📐 Generating road geometry...")
    var geometry_nodes: Array = []
    for segment in processed_segments:
        if segment.get("path", []).size() >= 2:
            var mesh: MeshInstance3D = geometry_generator.generate_road_mesh(
                segment.path, 
                segment.width, 
                _get_material_for_road_type(segment.type)
            )
            if mesh:
                geometry_nodes.append(mesh)
    
    # Prepare final result
    generation_result.success = true
    generation_result.road_segments = processed_segments
    generation_result.navigation_graph = navigation_graph
    # Prepare generation stats
    var stats_dict: Dictionary = {
        "total_segments": processed_segments.size(),
        "total_intersections": 0,  # Would be calculated in a full implementation
        "total_nodes": navigation_graph.get_all_node_ids().size(),
        "total_edges": navigation_graph.get_all_edge_ids().size()
    }
    generation_result.generation_stats = stats_dict
    
    print("✅ Road network generation complete: %d segments, %d nodes, %d edges" % [
        processed_segments.size(),
        navigation_graph.get_all_node_ids().size(),
        navigation_graph.get_all_edge_ids().size()
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
    
    # Adjust elevations to follow terrain properly
    var adjusted_path: PackedVector3Array = elevation_adjuster.adjust_road_elevations(
        path, width, road_type
    )
    
    # Carve terrain to integrate road properly
    terrain_carver.carve_road_terrain(adjusted_path, width, 0.5, 1.5)
    
    # Create the processed segment
    var processed_segment: Dictionary = {
        "from": start_pos,
        "to": end_pos,
        "type": road_type,
        "width": width,
        "path": adjusted_path,
        "length": _calculate_path_length(adjusted_path)
    }
    
    return processed_segment

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

## Get material for road type
func _get_material_for_road_type(road_type: String) -> Material:
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    
    match road_type:
        "highway":
            mat.albedo_color = Color(0.1, 0.1, 0.11)  # Dark gray for highways
            mat.roughness = 0.95
            mat.metallic = 0.0
        "arterial":
            mat.albedo_color = Color(0.12, 0.12, 0.13)  # Medium gray for arterials
            mat.roughness = 0.92
            mat.metallic = 0.0
        "local":
            mat.albedo_color = Color(0.15, 0.15, 0.16)  # Lighter gray for local roads
            mat.roughness = 0.90
            mat.metallic = 0.0
        _:
            mat.albedo_color = Color(0.12, 0.12, 0.13)
            mat.roughness = 0.90
            mat.metallic = 0.0
    
    return mat

## Calculate path length
func _calculate_path_length(path: PackedVector3Array) -> float:
    var length: float = 0.0
    for i in range(path.size() - 1):
        length += path[i].distance_to(path[i + 1])
    return length

## Find path for vehicle navigation
func find_vehicle_path(start_pos: Vector3, end_pos: Vector3, vehicle_specs: Dictionary = {}) -> Array:
    return navigation_system.find_path(start_pos, end_pos)

## Get road network statistics
func get_network_stats() -> Dictionary:
    return navigation_system.get_navigation_stats()