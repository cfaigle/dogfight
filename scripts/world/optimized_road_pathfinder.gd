class_name OptimizedRoadPathfinder
extends RefCounted

## Optimized pathfinding algorithms specifically designed for road networks

# Preload class files to make them available
const RoadGraph = preload("res://scripts/world/road_graph.gd")
const RoadGraphNode = preload("res://scripts/world/road_graph_node.gd")

var road_graph = null
var heuristic_factor: float = 1.0  # Factor to adjust heuristic influence

func set_road_graph(graph: RoadGraph) -> void:
    road_graph = graph

## Find shortest path using A* algorithm optimized for road networks
func find_path_astar(start_node: RoadGraphNode, end_node: RoadGraphNode, params: Dictionary = {}) -> Array:
    if road_graph == null:
        return []

    if start_node == null or end_node == null:
        return []

    if start_node == end_node:
        return [start_node]

    # Initialize data structures
    var open_set: Array = []  # Will store [f_score, node_id] pairs
    var open_set_lookup: Dictionary = {}  # node_id -> f_score for quick lookup
    var came_from: Dictionary = {}  # node_id -> previous node_id

    var g_score: Dictionary = {}  # Cost from start to node
    var f_score: Dictionary = {}  # Estimated total cost through node
    
    # Initialize scores
    g_score[start_node.id] = 0.0
    f_score[start_node.id] = heuristic_distance(start_node, end_node) * heuristic_factor
    
    # Add start node to open set
    open_set.append([f_score[start_node.id], start_node.id])
    open_set_lookup[start_node.id] = f_score[start_node.id]
    
    var max_iterations: int = int(params.get("max_iterations", 10000))
    var iteration_count: int = 0
    
    while open_set.size() > 0 and iteration_count < max_iterations:
        iteration_count += 1
        
        # Sort open set by f_score (ascending) and get node with lowest f_score
        open_set.sort_custom(func(a, b): return a[0] < b[0])
        var current_item = open_set[0]
        var current_node_id: String = current_item[1]
        var current_node: RoadGraphNode = road_graph.nodes.get(current_node_id)
        
        if current_node == null:
            open_set.pop_front()
            if open_set_lookup.has(current_node_id):
                open_set_lookup.erase(current_node_id)
            continue
        
        # Remove current from open set
        open_set.pop_front()
        if open_set_lookup.has(current_node_id):
            open_set_lookup.erase(current_node_id)
        
        # Check if we reached the destination
        if current_node == end_node:
            return _reconstruct_path(came_from, current_node, start_node)
        
        # Explore neighbors
        for edge in current_node.connected_edges:
            var neighbor_node: RoadGraphNode = edge.get_other_node(current_node)
            if neighbor_node == null:
                continue
            
            # Calculate tentative g_score
            var current_g: float = g_score.get(current_node.id, INF)
            var edge_cost: float = _calculate_edge_cost(edge, params)
            var tentative_g: float = current_g + edge_cost
            
            var neighbor_g: float = g_score.get(neighbor_node.id, INF)
            
            if tentative_g < neighbor_g:
                # This path to neighbor is better than any previous one
                came_from[neighbor_node.id] = current_node.id
                g_score[neighbor_node.id] = tentative_g
                f_score[neighbor_node.id] = tentative_g + heuristic_distance(neighbor_node, end_node) * heuristic_factor
                
                # Add neighbor to open set if not already there
                if not open_set_lookup.has(neighbor_node.id):
                    open_set.append([f_score[neighbor_node.id], neighbor_node.id])
                    open_set_lookup[neighbor_node.id] = f_score[neighbor_node.id]
                else:
                    # Update the f_score in the open set
                    for i in range(open_set.size()):
                        if open_set[i][1] == neighbor_node.id:
                            open_set[i][0] = f_score[neighbor_node.id]
                            break
    
    # No path found
    return []

## Calculate cost for traversing an edge with various factors
func _calculate_edge_cost(edge: RoadGraphEdge, params: Dictionary = {}) -> float:
    var base_cost: float = edge.length
    
    # Get vehicle-specific parameters if provided
    var vehicle_type: String = params.get("vehicle_type", "standard")
    var avoid_highways: bool = params.get("avoid_highways", false)
    var avoid_tolls: bool = params.get("avoid_tolls", false)
    
    # Road type penalties
    match edge.road_type:
        "highway":
            if avoid_highways:
                base_cost *= 2.0  # Avoid highways if requested
            else:
                base_cost *= 0.8  # Prefer highways (faster travel)
        "arterial":
            base_cost *= 1.0  # Standard cost
        "local":
            base_cost *= 1.2  # Slightly slower roads
        "access":
            base_cost *= 1.5  # Slow access roads
    
    # Width consideration (wider roads may be faster)
    if edge.width > 12.0:
        base_cost *= 0.9  # Wide roads are slightly preferred
    elif edge.width < 6.0:
        base_cost *= 1.1  # Narrow roads are slightly penalized
    
    # Add toll cost if applicable
    if avoid_tolls and edge.road_type == "toll_road":
        base_cost *= 3.0  # Heavy penalty for toll roads if avoiding them
    
    return base_cost

## Heuristic function for A* (Euclidean distance)
func heuristic_distance(node_a: RoadGraphNode, node_b: RoadGraphNode) -> float:
    return node_a.position.distance_to(node_b.position)

## Reconstruct path from came_from dictionary
func _reconstruct_path(came_from: Dictionary, current: RoadGraphNode, start: RoadGraphNode) -> Array:
    var path: Array = [current]
    var current_id: String = current.id
    
    while came_from.has(current_id):
        var prev_id: String = came_from[current_id]
        var prev_node: RoadGraphNode = road_graph.nodes.get(prev_id)
        
        if prev_node == null:
            break
            
        path.insert(0, prev_node)  # Add to front of array
        
        if prev_node == start:
            break
            
        current_id = prev_id
    
    return path

## Find path using Dijkstra's algorithm (unweighted shortest path)
func find_path_dijkstra(start_node: RoadGraphNode, end_node: RoadGraphNode, params: Dictionary = {}) -> Array:
    if road_graph == null:
        return []
    
    if start_node == null or end_node == null:
        return []
    
    if start_node == end_node:
        return [start_node]
    
    # Initialize data structures
    var unvisited: Dictionary = {}  # node_id -> node
    var distances: Dictionary = {}  # node_id -> distance
    var previous: Dictionary = {}   # node_id -> previous node_id
    
    # Initialize distances
    for node in road_graph.nodes.values():
        distances[node.id] = INF
        unvisited[node.id] = node
        previous[node.id] = null
    
    distances[start_node.id] = 0.0
    
    var max_iterations: int = int(params.get("max_iterations", 10000))
    var iteration_count: int = 0
    
    while unvisited.size() > 0 and iteration_count < max_iterations:
        iteration_count += 1
        
        # Find unvisited node with smallest distance
        var current_node: RoadGraphNode = null
        var min_distance: float = INF
        
        for node_id in unvisited.keys():
            var distance: float = distances.get(node_id, INF)
            if distance < min_distance:
                min_distance = distance
                current_node = unvisited[node_id]
        
        if current_node == null or current_node == end_node:
            break
        
        # Remove current node from unvisited
        unvisited.erase(current_node.id)
        
        # Check all neighbors
        for edge in current_node.connected_edges:
            var neighbor_node: RoadGraphNode = edge.get_other_node(current_node)
            if neighbor_node == null or not unvisited.has(neighbor_node.id):
                continue
            
            var edge_cost: float = _calculate_edge_cost(edge, params)
            var alt_distance: float = distances[current_node.id] + edge_cost
            
            if alt_distance < distances[neighbor_node.id]:
                distances[neighbor_node.id] = alt_distance
                previous[neighbor_node.id] = current_node.id
    
    # Reconstruct path
    var path: Array = []
    var current_path_node: RoadGraphNode = end_node
    
    while current_path_node != null:
        path.push_front(current_path_node)
        var prev_id: String = previous.get(current_path_node.id, null)
        if prev_id == null:
            break
        current_path_node = road_graph.nodes.get(prev_id)
    
    if path.size() > 0 and path[0] == start_node:
        return path
    else:
        return []  # No path found

## Find multiple alternative paths between two points
func find_multiple_paths(start_node: RoadGraphNode, end_node: RoadGraphNode, num_paths: int = 3, params: Dictionary = {}) -> Array:
    var all_paths: Array = []

    # Find the first path using standard A*
    var first_path: Array = find_path_astar(start_node, end_node, params)
    if first_path.size() == 0:
        return all_paths

    all_paths.append(first_path)

    # Find additional paths by temporarily removing edges from previous paths
    for i in range(1, num_paths):
        # Create a temporary graph with some edges from previous paths penalized
        var temp_params: Dictionary = params.duplicate()
        temp_params["penalized_edges"] = _get_path_edges(all_paths[i-1])

        var alt_path: Array = find_path_astar(start_node, end_node, temp_params)
        if alt_path.size() > 0:
            all_paths.append(alt_path)
        else:
            break  # No more alternative paths found

    return all_paths

## Get all edges in a path
func _get_path_edges(path: Array) -> Array[String]:
    var edge_ids: Array[String] = []
    
    for i in range(path.size() - 1):
        var node_a: RoadGraphNode = path[i]
        var node_b: RoadGraphNode = path[i + 1]
        
        # Find the edge between these nodes
        for edge in node_a.connected_edges:
            if edge.get_other_node(node_a) == node_b:
                edge_ids.append(edge.id)
                break
    
    return edge_ids

## Find path optimized for specific criteria
func find_path_by_criteria(start_node: RoadGraphNode, end_node: RoadGraphNode,
                          criteria: String = "shortest", params: Dictionary = {}) -> Array:
    var custom_params: Dictionary = params.duplicate()
    
    # Adjust parameters based on criteria
    match criteria:
        "shortest":
            # Standard shortest path (already implemented)
            return find_path_astar(start_node, end_node, custom_params)
        "fastest":
            # Prioritize highways and wide roads
            custom_params["prioritize_highways"] = true
            custom_params["prefer_wide_roads"] = true
            return find_path_astar(start_node, end_node, custom_params)
        "safest":
            # Avoid narrow roads and prefer well-maintained roads
            custom_params["avoid_narrow_roads"] = true
            custom_params["avoid_unsafe_roads"] = true
            return find_path_astar(start_node, end_node, custom_params)
        "scenic":
            # Prefer routes with nice scenery (would require scenic value data)
            custom_params["prefer_scenic_routes"] = true
            return find_path_astar(start_node, end_node, custom_params)
        _:
            # Default to shortest path
            return find_path_astar(start_node, end_node, custom_params)

## Precompute paths for common routes to improve performance
func precompute_common_routes(routes: Array[Dictionary], params: Dictionary = {}) -> Dictionary:
    var precomputed_paths: Dictionary = {}
    
    for route in routes:
        var start_pos: Vector3 = route.get("start", Vector3.ZERO)
        var end_pos: Vector3 = route.get("end", Vector3.ZERO)
        
        if start_pos == Vector3.ZERO or end_pos == Vector3.ZERO:
            continue
        
        # Find corresponding nodes
        var start_node: RoadGraphNode = road_graph.get_nearest_node(start_pos, 50.0)
        var end_node: RoadGraphNode = road_graph.get_nearest_node(end_pos, 50.0)
        
        if start_node != null and end_node != null:
            var path: Array[RoadGraphNode] = find_path_astar(start_node, end_node, params)
            var route_key: String = "%s_to_%s" % [start_pos, end_pos]
            precomputed_paths[route_key] = path
    
    return precomputed_paths

## Optimize path for real-time vehicle navigation
func optimize_path_for_navigation(path: Array, vehicle_specs: Dictionary = {}) -> Array[Vector3]:
    var optimized_path: Array[Vector3] = []
    
    if path.size() == 0:
        return optimized_path
    
    # Add start point
    optimized_path.append(path[0].position)
    
    # Process intermediate points
    for i in range(1, path.size() - 1):
        var current_node: RoadGraphNode = path[i]
        var prev_node: RoadGraphNode = path[i - 1]
        var next_node: RoadGraphNode = path[i + 1]
        
        # Calculate direction changes
        var prev_direction: Vector3 = (current_node.position - prev_node.position).normalized()
        var next_direction: Vector3 = (next_node.position - current_node.position).normalized()
        
        var angle_change: float = prev_direction.angle_to(next_direction)
        
        # Add point based on turn severity and vehicle specs
        var min_turn_radius: float = float(vehicle_specs.get("min_turn_radius", 5.0))
        var add_intermediate: bool = abs(angle_change) > deg_to_rad(15.0) or min_turn_radius < 10.0
        
        if add_intermediate:
            optimized_path.append(current_node.position)
    
    # Add end point
    if path.size() > 1:
        optimized_path.append(path[-1].position)
    
    return optimized_path

## Get path statistics
func get_path_statistics(path: Array) -> Dictionary:
    var stats: Dictionary = {
        "total_distance": 0.0,
        "num_intersections": 0,
        "num_turns": 0,
        "elevation_gain": 0.0,
        "elevation_loss": 0.0,
        "road_types": {}
    }
    
    if path.size() < 2:
        return stats
    
    # Calculate total distance and other stats
    for i in range(path.size() - 1):
        var node_a: RoadGraphNode = path[i]
        var node_b: RoadGraphNode = path[i + 1]
        
        # Find connecting edge to get distance
        var edge: RoadGraphEdge = road_graph.get_edge_between(node_a, node_b)
        if edge != null:
            stats.total_distance += edge.length
            
            # Count road types
            var road_type: String = edge.road_type
            if stats.road_types.has(road_type):
                stats.road_types[road_type] += edge.length
            else:
                stats.road_types[road_type] = edge.length
        
        # Check for significant direction changes (potential turns)
        if i > 0 and i < path.size() - 1:
            var prev_direction: Vector3 = (node_a.position - path[i-1].position).normalized()
            var next_direction: Vector3 = (node_b.position - node_a.position).normalized()
            
            var angle_change: float = abs(prev_direction.angle_to(next_direction))
            if angle_change > deg_to_rad(30.0):  # More than 30-degree turn
                stats.num_turns += 1
    
    # Count intersections (nodes with more than 2 connections)
    for node in path:
        if node.connected_edges.size() > 2:
            stats.num_intersections += 1
    
    # Calculate elevation changes
    var prev_elevation: float = path[0].position.y
    for i in range(1, path.size()):
        var current_elevation: float = path[i].position.y
        var elevation_diff: float = current_elevation - prev_elevation
        
        if elevation_diff > 0:
            stats.elevation_gain += elevation_diff
        else:
            stats.elevation_loss += abs(elevation_diff)
        
        prev_elevation = current_elevation
    
    return stats