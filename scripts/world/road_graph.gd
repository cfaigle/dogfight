class_name RoadGraph
extends RefCounted

## Main graph structure for the road network

# Preload class files to make them available
const RoadGraphNode = preload("res://scripts/world/road_graph_node.gd")
const RoadGraphEdge = preload("res://scripts/world/road_graph_edge.gd")

var nodes: Dictionary  # id -> RoadGraphNode
var edges: Dictionary  # id -> RoadGraphEdge
var node_positions: Dictionary  # Vector3 (rounded) -> RoadGraphNode id for spatial lookup

var _next_node_id: int = 0
var _next_edge_id: int = 0

func _init():
    nodes = {}
    edges = {}
    node_positions = {}

func add_node(position: Vector3, snap_distance: float = 5.0):  # Returns node ID
    # Check if there's already a node at this position (with snapping)
    var snapped_pos: Vector3 = _snap_to_existing_position(position, snap_distance)
    var existing_node_id: String = _get_node_id_at_position(snapped_pos)

    if existing_node_id != "":
        # Return existing node at this position
        return existing_node_id

    # Create new node
    var node_id: String = "node_%d" % _next_node_id
    _next_node_id += 1

    var new_node = RoadGraphNode.new(position, node_id)
    nodes[node_id] = new_node
    node_positions[snapped_pos] = node_id

    return node_id

func add_edge(node_a_id: String, node_b_id: String, road_type: String = "local", width: float = 8.0):  # Returns edge ID
    # Check if an edge already exists between these nodes
    var existing_edge_id: String = get_edge_id_between(node_a_id, node_b_id)
    if existing_edge_id != "":
        return existing_edge_id

    # Create new edge
    var edge_id: String = "edge_%d" % _next_edge_id
    _next_edge_id += 1

    var new_edge = RoadGraphEdge.new(node_a_id, node_b_id, edge_id)
    new_edge.road_type = road_type
    new_edge.width = width

    edges[edge_id] = new_edge

    # Add edge to both nodes' connection lists
    var node_a = nodes.get(node_a_id)
    var node_b = nodes.get(node_b_id)
    if node_a:
        node_a.add_connection(edge_id)
    if node_b:
        node_b.add_connection(edge_id)

    return edge_id

func get_edge_id_between(node_a_id: String, node_b_id: String) -> String:
    for edge_id in edges.keys():
        var edge = edges[edge_id]
        if (edge.node_a_id == node_a_id and edge.node_b_id == node_b_id) or \
           (edge.node_a_id == node_b_id and edge.node_b_id == node_a_id):
            return edge_id
    return ""

func remove_node(node_id: String) -> void:
    var node: RoadGraphNode = nodes.get(node_id)
    if not node:
        return
    
    # Remove all edges connected to this node first
    var edges_to_remove: Array = []
    for edge_id in edges.keys():
        var edge: RoadGraphEdge = edges[edge_id]
        if edge.node_a_id == node_id or edge.node_b_id == node_id:
            edges_to_remove.append(edge_id)
    
    for edge_id in edges_to_remove:
        remove_edge(edge_id)
    
    # Remove node from collections
    nodes.erase(node_id)
    
    # Find and remove from node_positions
    for pos in node_positions.keys():
        if node_positions[pos] == node_id:
            node_positions.erase(pos)
            break

func remove_edge(edge_id: String) -> void:
    var edge = edges.get(edge_id)
    if not edge:
        return

    # Remove edge from nodes' connection lists
    var node_a = nodes.get(edge.node_a_id)
    var node_b = nodes.get(edge.node_b_id)
    if node_a:
        node_a.remove_connection(edge_id)
    if node_b:
        node_b.remove_connection(edge_id)

    # Remove edge from collection
    edges.erase(edge_id)

func get_nearest_node_id(position: Vector3, max_distance: float = 50.0) -> String:
    var closest_node_id: String = ""
    var closest_dist: float = max_distance

    for node_id in nodes.keys():
        var node = nodes[node_id]
        var dist: float = position.distance_to(node.position)
        if dist < closest_dist:
            closest_dist = dist
            closest_node_id = node_id

    return closest_node_id

func get_node_by_id(node_id: String):
    return nodes.get(node_id)

func get_edge_by_id(edge_id: String):
    return edges.get(edge_id)

func get_nodes_within_radius(center: Vector3, radius: float) -> Array:
    var result: Array = []

    for node_id in nodes.keys():
        var node = nodes[node_id]
        if center.distance_to(node.position) <= radius:
            result.append(node_id)

    return result

func get_shortest_path(start_node_id: String, end_node_id: String) -> Array:  # Returns array of node IDs
    # Simple implementation of Dijkstra's algorithm for shortest path
    if not nodes.has(start_node_id) or not nodes.has(end_node_id):
        return []
    
    if start_node_id == end_node_id:
        return [start_node_id]
    
    # Initialize distances and previous nodes
    var distances: Dictionary = {}
    var previous: Dictionary = {}
    var unvisited: Array = []
    
    for node_id in nodes.keys():
        distances[node_id] = INF
        previous[node_id] = ""
        unvisited.append(node_id)
    
    distances[start_node_id] = 0.0
    
    while unvisited.size() > 0:
        # Find unvisited node with smallest distance
        var current: String = ""
        var min_distance: float = INF
        
        for node_id in unvisited:
            if distances[node_id] < min_distance:
                min_distance = distances[node_id]
                current = node_id
        
        if current == end_node_id or current == "" or distances[current] == INF:
            break
        
        unvisited.erase(current)
        
        # Check neighbors
        var current_node = nodes.get(current)
        if current_node:
            for edge_id in current_node.connected_edges:
                var edge = edges.get(edge_id)
                if not edge:
                    continue

                var neighbor_id: String = edge.get_other_node_id(current)
                if neighbor_id == "":
                    continue

                var neighbor_node = nodes.get(neighbor_id)
                if not neighbor_node:
                    continue

                var alt_distance: float = distances[current] + edge.length
                if alt_distance < distances[neighbor_id]:
                    distances[neighbor_id] = alt_distance
                    previous[neighbor_id] = current
    
    # Reconstruct path
    var path: Array = []
    var current_path_node: String = end_node_id
    
    while current_path_node != "":
        path.push_front(current_path_node)
        current_path_node = previous[current_path_node]
    
    if path.size() > 0 and path[0] == start_node_id:
        return path
    else:
        return []  # No path found

func _snap_to_existing_position(position: Vector3, snap_distance: float) -> Vector3:
    # Round position to grid for spatial lookup
    var grid_size: float = snap_distance / 2.0
    var grid_x: int = int(round(position.x / grid_size))
    var grid_z: int = int(round(position.z / grid_size))
    
    return Vector3(grid_x * grid_size, position.y, grid_z * grid_size)

func _get_node_id_at_position(position: Vector3) -> String:
    return node_positions.get(position, "")

func get_all_node_ids() -> Array:
    return nodes.keys()

func get_all_edge_ids() -> Array:
    return edges.keys()

func clear() -> void:
    nodes.clear()
    edges.clear()
    node_positions.clear()
    _next_node_id = 0
    _next_edge_id = 0