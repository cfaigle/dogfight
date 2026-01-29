class_name RoadGraphNode
extends RefCounted

## Represents a point in the road network (intersection, junction, or significant point)

var position: Vector3
var id: String
var connected_edges: Array  # Edges connected to this node (using IDs to avoid circular refs)
var is_intersection: bool = false
var is_terminus: bool = false  # Dead-end or settlement connection point

func _init(pos: Vector3, node_id: String = ""):
    position = pos
    id = node_id if node_id != "" else "node_%d" % randi()
    connected_edges = []

func add_connection(edge_id: String) -> void:
    if not connected_edges.has(edge_id):
        connected_edges.append(edge_id)

func remove_connection(edge_id: String) -> void:
    connected_edges.erase(edge_id)