class_name IntersectionGeometryGenerator
extends RefCounted

## Generates proper intersection geometry with shared vertices and smooth connections

# Preload class files to make them available
const RoadGraph = preload("res://scripts/world/road_graph.gd")
const RoadGraphNode = preload("res://scripts/world/road_graph_node.gd")
const RoadGraphEdge = preload("res://scripts/world/road_graph_edge.gd")

var terrain_generator = null

func set_terrain_generator(terrain_gen) -> void:
    terrain_generator = terrain_gen

## Generate intersection geometry for multiple connecting roads
func generate_intersection_geometry(intersection_node_id: String, road_graph, road_widths: Dictionary, material = null) -> MeshInstance3D:
    var intersection_node = road_graph.get_node_by_id(intersection_node_id)
    if not intersection_node:
        return null

    if intersection_node.connected_edges.size() < 2:
        # Not actually an intersection, just return null
        return null

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Collect all incoming road directions and widths
    var road_data: Array = []

    for edge_id in intersection_node.connected_edges:
        var edge = road_graph.get_edge_by_id(edge_id)
        if edge:
            var other_node_id: String = edge.get_other_node_id(intersection_node_id)
            if other_node_id != "":
                var other_node = road_graph.get_node_by_id(other_node_id)
                if other_node:
                    var direction: Vector3 = (other_node.position - intersection_node.position).normalized()
                    var width: float = road_widths.get(edge_id, 8.0)  # Default to 8m if not specified

                    road_data.append({
                        "direction": direction,
                        "width": width,
                        "edge_id": edge_id
                    })

    # Sort road data by angle to process in circular order
    road_data.sort_custom(func(a, b):
        var angle_a: float = atan2(a.direction.x, a.direction.z)
        var angle_b: float = atan2(b.direction.x, b.direction.z)
        return angle_a < angle_b
    )
    
    # Generate intersection polygon
    var intersection_vertices: PackedVector3Array = _create_intersection_polygon(intersection_node.position, road_data)
    
    # Create the intersection surface
    _create_intersection_surface(st, intersection_vertices, intersection_node.position.y, material)
    
    # Add connecting road segments that blend into the intersection
    for i in range(road_data.size()):
        var road_info = road_data[i]
        var next_road_info = road_data[(i + 1) % road_data.size()]
        
        # Create transition geometry between roads
        _create_transition_geometry(st, intersection_node.position, road_info, next_road_info)
    
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.mesh = st.commit()
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    
    return mesh_instance

## Create the main intersection polygon based on incoming roads
func _create_intersection_polygon(center: Vector3, road_data: Array) -> PackedVector3Array:
    var vertices: PackedVector3Array = PackedVector3Array()
    
    # For each road, calculate the entry point into the intersection
    for i in range(road_data.size()):
        var current_road = road_data[i]
        var next_road = road_data[(i + 1) % road_data.size()]
        
        # Calculate the angle bisector between this road and the next
        var current_dir: Vector3 = current_road.direction
        var next_dir: Vector3 = next_road.direction
        
        # Calculate perpendicular vectors for road width
        var current_right: Vector3 = current_dir.cross(Vector3.UP).normalized() * (current_road.width / 2.0)
        var next_right: Vector3 = next_dir.cross(Vector3.UP).normalized() * (next_road.width / 2.0)
        
        # Calculate corner points of the intersection
        var corner_point: Vector3 = center + current_right - next_right
        vertices.append(corner_point)

    return vertices

## Create the flat surface of the intersection
func _create_intersection_surface(surface_tool: SurfaceTool, vertices: PackedVector3Array, center_y: float, material):
    if vertices.size() < 3:
        return
    
    # Triangulate the polygon (simple fan triangulation for convex polygons)
    var center_pos: Vector3 = Vector3(0, 0, 0)
    for v in vertices:
        center_pos += v
    center_pos /= float(vertices.size())
    
    # Adjust Y coordinate to match terrain height at center
    if terrain_generator != null and terrain_generator.has_method("get_height_at"):
        center_pos.y = terrain_generator.get_height_at(center_pos.x, center_pos.z) + 0.5  # Consistent offset with other roads
    else:
        center_pos.y = center_y + 0.1
    
    # Create triangles using fan triangulation
    for i in range(vertices.size()):
        var v1: Vector3 = vertices[i]
        var v2: Vector3 = vertices[(i + 1) % vertices.size()]
        
        # Use Y coordinates as provided by the road system
        # The road system should have already adjusted these to follow terrain properly
        # Just ensure they're slightly above terrain for visual purposes
        if terrain_generator != null and terrain_generator.has_method("get_height_at"):
            var h1 = terrain_generator.get_height_at(v1.x, v1.z)
            var h2 = terrain_generator.get_height_at(v2.x, v2.z)
            # Use the provided Y coordinates but ensure they're above terrain
            v1.y = max(h1 + 0.1, v1.y)
            v2.y = max(h2 + 0.1, v2.y)
        else:
            # Fallback to original behavior
            v1.y = center_y + 0.1
            v2.y = center_y + 0.1
        
        # Create triangle: center -> v1 -> v2
        surface_tool.set_normal(Vector3.UP)
        surface_tool.set_uv(Vector2(0.5, 0.5))
        surface_tool.add_vertex(center_pos)
        
        surface_tool.set_normal(Vector3.UP)
        surface_tool.set_uv(Vector2(0, 1))
        surface_tool.add_vertex(v1)
        
        surface_tool.set_normal(Vector3.UP)
        surface_tool.set_uv(Vector2(1, 1))
        surface_tool.add_vertex(v2)

## Create transition geometry between two connecting roads
func _create_transition_geometry(surface_tool: SurfaceTool, center: Vector3, road1: Dictionary, road2: Dictionary):
    # Calculate the transition area between two roads
    var dir1: Vector3 = road1.direction
    var dir2: Vector3 = road2.direction
    var width1: float = road1.width
    var width2: float = road2.width
    
    # Calculate perpendicular vectors
    var right1: Vector3 = dir1.cross(Vector3.UP).normalized() * (width1 / 2.0)
    var right2: Vector3 = dir2.cross(Vector3.UP).normalized() * (width2 / 2.0)
    
    # Calculate transition points
    var p1: Vector3 = center + right1
    var p2: Vector3 = center - right2
    var p3: Vector3 = center + right1 * 0.7 + dir1 * min(width1, width2) * 0.5
    var p4: Vector3 = center - right2 * 0.7 + dir2 * min(width1, width2) * 0.5
    
    # Use Y coordinates as provided by the road system
    # The road system should have already adjusted these to follow terrain properly
    # Just ensure they're slightly above terrain for visual purposes
    if terrain_generator != null and terrain_generator.has_method("get_height_at"):
        var h1 = terrain_generator.get_height_at(p1.x, p1.z)
        var h2 = terrain_generator.get_height_at(p2.x, p2.z)
        var h3 = terrain_generator.get_height_at(p3.x, p3.z)
        var h4 = terrain_generator.get_height_at(p4.x, p4.z)
        # Use the provided Y coordinates but ensure they're above terrain
        p1.y = max(h1 + 0.1, p1.y)
        p2.y = max(h2 + 0.1, p2.y)
        p3.y = max(h3 + 0.1, p3.y)
        p4.y = max(h4 + 0.1, p4.y)
    else:
        # Fallback to original behavior
        p1.y = center.y + 0.1
        p2.y = center.y + 0.1
        p3.y = center.y + 0.1
        p4.y = center.y + 0.1
    
    # Create transition quad
    surface_tool.set_normal(Vector3.UP)
    surface_tool.add_vertex(p1)
    surface_tool.add_vertex(p3)
    surface_tool.add_vertex(p4)
    
    surface_tool.set_normal(Vector3.UP)
    surface_tool.add_vertex(p1)
    surface_tool.add_vertex(p4)
    surface_tool.add_vertex(p2)

## Helper function to add a triangle to the surface tool
func _add_triangle(surface_tool: SurfaceTool, v1: Vector3, v2: Vector3, v3: Vector3):
    surface_tool.set_normal(Vector3.UP)
    surface_tool.set_uv(Vector2(0, 0))
    surface_tool.add_vertex(v1)
    
    surface_tool.set_normal(Vector3.UP)
    surface_tool.set_uv(Vector2(0.5, 1))
    surface_tool.add_vertex(v2)
    
    surface_tool.set_normal(Vector3.UP)
    surface_tool.set_uv(Vector2(1, 0))
    surface_tool.add_vertex(v3)