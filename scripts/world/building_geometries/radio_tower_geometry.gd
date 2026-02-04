class_name RadioTowerGeometry
extends RefCounted

## Creates a radio tower geometry with lattice structure and stackable segments

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Tower parameters with variation
    var num_segments: int = rng.randi_range(4, 8)
    var total_height: float = rng.randf_range(30.0, 60.0)
    var segment_height: float = total_height / num_segments
    var base_width: float = max(plot.lot_width * 0.3, 3.0)
    var top_width: float = base_width * rng.randf_range(0.55, 0.7)  # 55-70% taper
    var beam_thickness: float = rng.randf_range(0.4, 0.6)  # 3-4x thicker for arcade visibility

    # Generate each segment with linear taper
    for seg_idx in range(num_segments):
        var y_bottom = seg_idx * segment_height
        var y_top = (seg_idx + 1) * segment_height
        var t = float(seg_idx) / float(num_segments)
        var width_bottom = lerp(base_width, top_width, t)
        var width_top = lerp(base_width, top_width, t + (1.0 / num_segments))

        _add_tower_segment(st, y_bottom, y_top, width_bottom, width_top, beam_thickness)

    # Add antennas at top
    _add_four_cardinal_antennas(st, total_height, top_width, beam_thickness, rng)

    # Finalize
    st.generate_normals()
    var mesh = st.commit()

    # Material (bright aviation orange/red for arcade visibility)
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.3, 0.0)  # Bright aviation orange/red
    mat.metallic = 0.3  # Reduced - less reliant on reflections
    mat.roughness = 0.8  # Increased - catches more diffuse light
    mesh.surface_set_material(0, mat)

    # Store tower metadata for collision and damage systems
    mesh.set_meta("tower_height", total_height)
    mesh.set_meta("tower_base_width", base_width)
    mesh.set_meta("tower_top_width", top_width)

    return mesh

## Add a rectangular beam from point A to point B
static func _add_beam(st: SurfaceTool, start: Vector3, end: Vector3, thickness: float) -> void:
    var direction = (end - start).normalized()
    var length = start.distance_to(end)

    # Calculate perpendicular vectors for beam cross-section
    var up = Vector3.UP
    if abs(direction.dot(up)) > 0.99:  # Vertical beam case
        up = Vector3.FORWARD
    var right = direction.cross(up).normalized() * thickness * 0.5
    var forward = direction.cross(right).normalized() * thickness * 0.5

    # 8 corners of rectangular prism
    var corners = [
        start + right + forward,   # 0: bottom-right-front
        start - right + forward,   # 1: bottom-left-front
        start - right - forward,   # 2: bottom-left-back
        start + right - forward,   # 3: bottom-right-back
        end + right + forward,     # 4: top-right-front
        end - right + forward,     # 5: top-left-front
        end - right - forward,     # 6: top-left-back
        end + right - forward      # 7: top-right-back
    ]

    # 6 faces (12 triangles) with counter-clockwise winding
    # Front face
    _add_quad(st, corners[0], corners[1], corners[5], corners[4])
    # Back face
    _add_quad(st, corners[3], corners[7], corners[6], corners[2])
    # Right face
    _add_quad(st, corners[3], corners[0], corners[4], corners[7])
    # Left face
    _add_quad(st, corners[2], corners[6], corners[5], corners[1])
    # Bottom face
    _add_quad(st, corners[3], corners[2], corners[1], corners[0])
    # Top face
    _add_quad(st, corners[4], corners[5], corners[6], corners[7])

## Add a quad (two triangles) with counter-clockwise winding
static func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
    # Triangle 1: v0-v1-v2
    st.add_vertex(v0)
    st.add_vertex(v1)
    st.add_vertex(v2)
    # Triangle 2: v0-v2-v3
    st.add_vertex(v0)
    st.add_vertex(v2)
    st.add_vertex(v3)

## Create one stackable lattice segment with cross-bracing
static func _add_tower_segment(st: SurfaceTool, y_bottom: float, y_top: float,
                                width_bottom: float, width_top: float, thickness: float) -> void:
    var hwb = width_bottom * 0.5  # Half-width bottom
    var hwt = width_top * 0.5     # Half-width top

    # Four corner verticals (East, West, North, South)
    _add_beam(st, Vector3(hwb, y_bottom, 0), Vector3(hwt, y_top, 0), thickness)
    _add_beam(st, Vector3(-hwb, y_bottom, 0), Vector3(-hwt, y_top, 0), thickness)
    _add_beam(st, Vector3(0, y_bottom, hwb), Vector3(0, y_top, hwt), thickness)
    _add_beam(st, Vector3(0, y_bottom, -hwb), Vector3(0, y_top, -hwt), thickness)

    # Cross-bracing Plane 1 (N-S lattice, diagonal X pattern)
    # X from NE to SW and NW to SE
    _add_beam(st, Vector3(hwb, y_bottom, hwb), Vector3(-hwt, y_top, -hwt), thickness * 0.8)
    _add_beam(st, Vector3(-hwb, y_bottom, hwb), Vector3(hwt, y_top, -hwt), thickness * 0.8)

    # Cross-bracing Plane 2 (E-W lattice, diagonal X pattern)
    # X from NE to SW and SE to NW (perpendicular plane)
    _add_beam(st, Vector3(hwb, y_bottom, -hwb), Vector3(-hwt, y_top, hwt), thickness * 0.8)
    _add_beam(st, Vector3(hwb, y_bottom, hwb), Vector3(-hwt, y_top, -hwt), thickness * 0.8)

## Add four cardinal-direction antennas (N, E, S, W)
static func _add_four_cardinal_antennas(st: SurfaceTool, tower_height: float,
                                         tower_width: float, beam_thickness: float,
                                         rng: RandomNumberGenerator) -> void:
    var antenna_length = tower_width * rng.randf_range(1.3, 1.8)
    var antenna_thickness = beam_thickness * 0.9
    var antenna_height = tower_height + 2.0

    # Central mounting pole (vertical)
    _add_beam(st, Vector3(0, tower_height, 0), Vector3(0, antenna_height, 0), beam_thickness * 0.8)

    # Four directions: East, West, North, South
    var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]

    for dir in directions:
        # Horizontal antenna beam extending in cardinal direction
        var start = Vector3(dir.x * tower_width * 0.3, antenna_height, dir.z * tower_width * 0.3)
        var end = start + dir * antenna_length
        _add_beam(st, start, end, antenna_thickness)

        # Antenna dish (flat panel) at end
        _add_antenna_dish(st, end + Vector3(0, 0.3, 0), dir, antenna_thickness * 2.5)

## Create flat rectangular antenna dish facing given direction
static func _add_antenna_dish(st: SurfaceTool, center: Vector3, facing: Vector3, size: float) -> void:
    # Calculate right and up vectors perpendicular to facing direction
    var up = Vector3.UP
    if abs(facing.dot(up)) > 0.99:
        up = Vector3.FORWARD
    var right = facing.cross(up).normalized() * size * 0.5
    var dish_up = right.cross(facing).normalized() * size * 0.3  # Rectangular (wider than tall)

    # Four corners of rectangular panel
    var v0 = center + right + dish_up
    var v1 = center - right + dish_up
    var v2 = center - right - dish_up
    var v3 = center + right - dish_up

    # Front face (facing direction)
    _add_quad(st, v0, v1, v2, v3)
    # Back face (double-sided)
    _add_quad(st, v3, v2, v1, v0)
