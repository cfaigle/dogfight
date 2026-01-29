class_name RoadGraphEdge
extends RefCounted

## Represents a road segment connecting two nodes in the road network

var node_a_id: String
var node_b_id: String
var id: String
var road_type: String  # "highway", "arterial", "local", etc.
var width: float
var length: float
var is_bidirectional: bool = true
var waypoints: PackedVector3Array  # Points along the road segment for curves
var terrain_adapted: bool = false  # Whether the road has been adapted to terrain

func _init(start_node_id: String, end_node_id: String, edge_id: String = ""):
    node_a_id = start_node_id
    node_b_id = end_node_id
    id = edge_id if edge_id != "" else "edge_%d" % randi()
    road_type = "local"
    width = 8.0
    length = 0.0  # Will be calculated later
    is_bidirectional = true
    waypoints = PackedVector3Array()

func get_other_node_id(current_node_id: String) -> String:
    if current_node_id == node_a_id:
        return node_b_id
    elif current_node_id == node_b_id:
        return node_a_id
    else:
        return ""

func set_waypoints(new_waypoints: PackedVector3Array) -> void:
    waypoints = new_waypoints
    # Recalculate length
    length = calculate_length()

func calculate_length() -> float:
    var total_length: float = 0.0
    var all_points: PackedVector3Array = get_waypoint_positions()
    for i in range(all_points.size() - 1):
        total_length += all_points[i].distance_to(all_points[i + 1])
    return total_length

func get_waypoint_positions() -> PackedVector3Array:
    var positions: PackedVector3Array = PackedVector3Array()
    # This would be filled by the road system with actual positions
    # For now, returning empty - will be populated when the edge is fully defined
    return positions