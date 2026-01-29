class_name RoadNavigationSystem
extends RefCounted

## Converts road data to navigable graph structure and provides pathfinding for vehicles

var road_graph: RoadGraph = null
var terrain_generator = null

func _init():
    road_graph = RoadGraph.new()

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

## Convert existing road data to navigable graph structure
func convert_road_data_to_graph(road_segments: Array, intersection_points: Array = []) -> RoadGraph:
    road_graph.clear()
    
    # Create nodes for all unique positions in road segments
    var position_to_node_id: Dictionary = {}
    
    # Process all road segments to create nodes and edges
    for segment in road_segments:
        if not segment is Dictionary:
            continue
            
        var start_pos: Vector3 = segment.get("from", Vector3.ZERO)
        var end_pos: Vector3 = segment.get("to", Vector3.ZERO)
        var road_type: String = segment.get("type", "local")
        var width: float = segment.get("width", 8.0)
        
        if start_pos == Vector3.ZERO or end_pos == Vector3.ZERO:
            continue
        
        # Create or get nodes for start and end positions
        var start_node_id: String = _get_or_create_node_id(start_pos, position_to_node_id)
        var end_node_id: String = _get_or_create_node_id(end_pos, position_to_node_id)
        
        # Create edge between nodes
        var edge_id: String = road_graph.add_edge(start_node_id, end_node_id, road_type, width)
        
        # Set waypoints if available
        if segment.has("path") and segment.path is PackedVector3Array:
            var edge: RoadGraphEdge = road_graph.get_edge_by_id(edge_id)
            if edge:
                edge.set_waypoints(segment.path)
    
    # Process intersection points to ensure they're represented as nodes
    for intersection_pos in intersection_points:
        if intersection_pos is Vector3:
            _get_or_create_node_id(intersection_pos, position_to_node_id)
    
    return road_graph

## Helper function to get or create a node ID for a position
func _get_or_create_node_id(position: Vector3, position_to_node_dict: Dictionary) -> String:
    # Check if we already have a node at this position (with some tolerance)
    for existing_pos in position_to_node_dict.keys():
        if existing_pos.distance_to(position) < 1.0:  # 1m tolerance
            return position_to_node_dict[existing_pos]
    
    # Create new node
    var new_node_id: String = road_graph.add_node(position)
    position_to_node_dict[position] = new_node_id
    return new_node_id

## Add a new road segment to the navigation graph
func add_road_segment(start_pos: Vector3, end_pos: Vector3, road_type: String = "local",
                      width: float = 8.0, waypoints: PackedVector3Array = PackedVector3Array()) -> void:
    var start_node_id: String = road_graph.get_nearest_node_id(start_pos, 2.0)
    if start_node_id == "":
        start_node_id = road_graph.add_node(start_pos)
    
    var end_node_id: String = road_graph.get_nearest_node_id(end_pos, 2.0)
    if end_node_id == "":
        end_node_id = road_graph.add_node(end_pos)
    
    var edge_id: String = road_graph.add_edge(start_node_id, end_node_id, road_type, width)
    
    if waypoints != null:
        var edge: RoadGraphEdge = road_graph.get_edge_by_id(edge_id)
        if edge:
            edge.set_waypoints(waypoints)

## Find the shortest path between two points using the road network
func find_path(start_pos: Vector3, end_pos: Vector3) -> Array:
    var start_node_id: String = road_graph.get_nearest_node_id(start_pos, 50.0)
    var end_node_id: String = road_graph.get_nearest_node_id(end_pos, 50.0)
    
    if start_node_id == "" or end_node_id == "":
        # If we can't find nearby road nodes, return empty path
        return []
    
    # Get path through the road graph
    var graph_path: Array = road_graph.get_shortest_path(start_node_id, end_node_id)
    
    if graph_path.is_empty():
        return []
    
    # Convert graph path to world positions
    var world_path: Array = []
    for node_id in graph_path:
        var node: RoadGraphNode = road_graph.get_node_by_id(node_id)
        if node:
            world_path.append(node.position)
    
    return world_path

## Get nearby roads for a position
func get_nearby_roads(center_pos: Vector3, radius: float) -> Array:
    var nearby_node_ids: Array = road_graph.get_nodes_within_radius(center_pos, radius)
    var nearby_roads: Array = []
    
    for node_id in nearby_node_ids:
        var node: RoadGraphNode = road_graph.get_node_by_id(node_id)
        if node:
            for edge_id in node.connected_edges:
                if not nearby_roads.has(edge_id):
                    nearby_roads.append(edge_id)
    
    return nearby_roads

## Get road information at a specific position
func get_road_at_position(pos: Vector3, tolerance: float = 10.0) -> Dictionary:
    var nearby_node_ids: Array = road_graph.get_nodes_within_radius(pos, tolerance)

    for node_id in nearby_node_ids:
        var node: RoadGraphNode = road_graph.get_node_by_id(node_id)
        if node and node.position.distance_to(pos) <= tolerance:
            # Return information about roads connected to this node
            var road_info: Dictionary = {
                "position": node.position,
                "connected_roads": []
            }

            for edge_id in node.connected_edges:
                var edge: RoadGraphEdge = road_graph.get_edge_by_id(edge_id)
                if edge:
                    var connected_info: Dictionary = {
                        "road_type": edge.road_type,
                        "width": edge.width,
                        "length": edge.length,
                        "connected_node_id": edge.get_other_node_id(node_id)
                    }
                    road_info.connected_roads.append(connected_info)

            return road_info

    return {}

## Get navigation statistics
func get_navigation_stats() -> Dictionary:
    var stats: Dictionary = {
        "total_nodes": road_graph.get_all_node_ids().size(),
        "total_edges": road_graph.get_all_edge_ids().size(),
        "connected_components": _count_connected_components(),
        "avg_node_degree": _calculate_avg_node_degree()
    }
    
    return stats

## Count connected components in the graph
func _count_connected_components() -> int:
    var visited: Dictionary = {}
    var components: int = 0
    
    for node_id in road_graph.get_all_node_ids():
        if not visited.has(node_id):
            _mark_connected_component(node_id, visited)
            components += 1
    
    return components

## Mark all nodes in a connected component as visited
func _mark_connected_component(start_node_id: String, visited_dict: Dictionary) -> void:
    var queue: Array = [start_node_id]
    visited_dict[start_node_id] = true
    
    while queue.size() > 0:
        var current_node_id: String = queue.pop_front()
        var current_node: RoadGraphNode = road_graph.get_node_by_id(current_node_id)
        
        if current_node:
            for edge_id in current_node.connected_edges:
                var edge: RoadGraphEdge = road_graph.get_edge_by_id(edge_id)
                if edge:
                    var other_node_id: String = edge.get_other_node_id(current_node_id)
                    if other_node_id != "" and not visited_dict.has(other_node_id):
                        visited_dict[other_node_id] = true
                        queue.append(other_node_id)

## Calculate average node degree (average number of connections per node)
func _calculate_avg_node_degree() -> float:
    var node_ids: Array = road_graph.get_all_node_ids()
    if node_ids.size() == 0:
        return 0.0
    
    var total_degree: int = 0
    for node_id in node_ids:
        var node: RoadGraphNode = road_graph.get_node_by_id(node_id)
        if node:
            total_degree += node.connected_edges.size()
    
    return float(total_degree) / float(node_ids.size())

## Check if a path exists between two points
func has_path(start_pos: Vector3, end_pos: Vector3) -> bool:
    var start_node_id: String = road_graph.get_nearest_node_id(start_pos, 50.0)
    var end_node_id: String = road_graph.get_nearest_node_id(end_pos, 50.0)
    
    if start_node_id == "" or end_node_id == "":
        return false
    
    var path: Array = road_graph.get_shortest_path(start_node_id, end_node_id)
    return not path.is_empty()

## Get the closest road node to a position
func get_closest_road_node_id(pos: Vector3) -> String:
    return road_graph.get_nearest_node_id(pos, INF)  # No distance limit