class_name DetailComponent
extends BuildingComponentBase

## Generates decorative building details
## Includes cornices, quoins, string courses, pediments, brackets, dentils

func get_required_params() -> Array[String]:
    return ["footprint", "height", "floors"]

func get_optional_params() -> Dictionary:
    return {
        "floor_height": 3.0,
        "detail_intensity": 0.5,  # 0.0 = minimal, 1.0 = ornate
        "detail_scale": 1.0,
        "add_cornice": true,
        "add_string_courses": true,
        "add_quoins": true,
        "add_dentils": false,
        "add_brackets": false
    }

func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    var footprint: PackedVector2Array = params["footprint"]
    var height: float = params["height"]
    var floors: int = params["floors"]
    var floor_height: float = params.get("floor_height", height / float(floors))
    var intensity: float = params["detail_intensity"]
    var scale: float = params["detail_scale"]

    # Add cornice at roofline
    if params.get("add_cornice", true):
        _add_cornice(st, footprint, height, scale, intensity)

    # Add string courses between floors (for ornate buildings)
    if params.get("add_string_courses", true) and intensity > 0.4:
        for floor in range(1, floors):
            var y = floor * floor_height
            _add_string_course(st, footprint, y, scale * 0.5)

    # Add quoins at corners (for ornate buildings)
    if params.get("add_quoins", true) and intensity > 0.6:
        _add_corner_quoins(st, footprint, height, scale)

    # Add dentils under cornice (for very ornate buildings)
    if params.get("add_dentils", false) and intensity > 0.8:
        _add_dentils(st, footprint, height - scale * 0.1, scale * 0.3)

    # Add brackets under eaves (for certain styles)
    if params.get("add_brackets", false) and intensity > 0.7:
        _add_brackets(st, footprint, height, scale)

## Add cornice (decorative horizontal band at roofline)
func _add_cornice(st: SurfaceTool, footprint: PackedVector2Array,
                  height: float, scale: float, intensity: float) -> void:
    var cornice_height = 0.3 * scale
    var cornice_depth = 0.2 * scale * (1.0 + intensity)

    var point_count = footprint.size()

    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        # Calculate wall direction and normal
        var wall_dir = (p1 - p0).normalized()
        var wall_normal = Vector2(-wall_dir.y, wall_dir.x)

        # Create cornice profile
        var base_3d_0 = Vector3(p0.x, height - cornice_height, p0.y)
        var base_3d_1 = Vector3(p1.x, height - cornice_height, p1.y)

        var top_inner_0 = Vector3(p0.x, height, p0.y)
        var top_inner_1 = Vector3(p1.x, height, p1.y)

        var top_outer_0 = Vector3(p0.x + wall_normal.x * cornice_depth,
                                  height,
                                  p0.y + wall_normal.y * cornice_depth)
        var top_outer_1 = Vector3(p1.x + wall_normal.x * cornice_depth,
                                  height,
                                  p1.y + wall_normal.y * cornice_depth)

        # Create cornice faces
        # Vertical face
        add_quad(st, base_3d_0, base_3d_1, top_inner_1, top_inner_0)

        # Horizontal overhang (bottom)
        add_quad(st, top_inner_0, top_inner_1, top_outer_1, top_outer_0)

        # Outer face (decorative edge)
        var outer_bottom_0 = top_outer_0 - Vector3.UP * cornice_height * 0.5
        var outer_bottom_1 = top_outer_1 - Vector3.UP * cornice_height * 0.5
        add_quad(st, outer_bottom_0, outer_bottom_1, top_outer_1, top_outer_0)

## Add string course (horizontal band between floors)
func _add_string_course(st: SurfaceTool, footprint: PackedVector2Array,
                        y: float, scale: float) -> void:
    var course_height = 0.15 * scale
    var course_depth = 0.08 * scale

    var point_count = footprint.size()

    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        var wall_dir = (p1 - p0).normalized()
        var wall_normal = Vector2(-wall_dir.y, wall_dir.x)

        # Create string course profile (simple projecting band)
        var bottom_0 = Vector3(p0.x, y - course_height * 0.5, p0.y)
        var bottom_1 = Vector3(p1.x, y - course_height * 0.5, p1.y)

        var top_0 = Vector3(p0.x + wall_normal.x * course_depth,
                            y + course_height * 0.5,
                            p0.y + wall_normal.y * course_depth)
        var top_1 = Vector3(p1.x + wall_normal.x * course_depth,
                            y + course_height * 0.5,
                            p1.y + wall_normal.y * course_depth)

        # Simple sloped face
        add_quad(st, bottom_0, bottom_1, top_1, top_0)

## Add quoins (decorative corner stones)
func _add_corner_quoins(st: SurfaceTool, footprint: PackedVector2Array,
                        height: float, scale: float) -> void:
    var quoin_size = 0.3 * scale
    var quoin_depth = 0.1 * scale
    var quoin_spacing = 0.6 * scale

    # Add quoins at each corner
    for i in range(footprint.size()):
        var corner = footprint[i]
        var prev = footprint[(i - 1 + footprint.size()) % footprint.size()]
        var next = footprint[(i + 1) % footprint.size()]

        # Calculate corner angle
        var edge_in = (corner - prev).normalized()
        var edge_out = (next - corner).normalized()

        var normal_in = Vector2(-edge_in.y, edge_in.x)
        var normal_out = Vector2(-edge_out.y, edge_out.x)

        # Place alternating quoins up the corner
        var quoin_count = int(height / quoin_spacing)
        for j in range(quoin_count):
            var y = j * quoin_spacing

            # Alternate between two sides
            var use_in_side = (j % 2) == 0

            if use_in_side:
                _create_quoin_block(st, corner, edge_in, normal_in,
                                    y, quoin_size, quoin_depth)
            else:
                _create_quoin_block(st, corner, -edge_out, normal_out,
                                    y, quoin_size, quoin_depth)

## Create a single quoin block
func _create_quoin_block(st: SurfaceTool, corner: Vector2, direction: Vector2,
                         normal: Vector2, y: float, size: float, depth: float) -> void:
    # Quoin extends along wall and projects outward
    var base_corner = Vector3(corner.x, y, corner.y)

    var p0 = base_corner
    var p1 = base_corner + Vector3(direction.x, 0, direction.y) * size
    var p2 = base_corner + Vector3(direction.x + normal.x * depth, 0,
                                   direction.y + normal.y * depth) * size
    var p3 = base_corner + Vector3(normal.x * depth, 0, normal.y * depth)

    var p0_top = p0 + Vector3.UP * size
    var p1_top = p1 + Vector3.UP * size
    var p2_top = p2 + Vector3.UP * size
    var p3_top = p3 + Vector3.UP * size

    # Front face
    add_quad(st, p0, p1, p1_top, p0_top)
    # Side face
    add_quad(st, p1, p2, p2_top, p1_top)
    # Top face
    add_quad(st, p0_top, p1_top, p2_top, p3_top)

## Add dentils (small rectangular blocks under cornice)
func _add_dentils(st: SurfaceTool, footprint: PackedVector2Array,
                  y: float, scale: float) -> void:
    var dentil_width = 0.15 * scale
    var dentil_height = 0.2 * scale
    var dentil_depth = 0.1 * scale
    var dentil_spacing = 0.3 * scale

    var point_count = footprint.size()

    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        var wall_dir = (p1 - p0).normalized()
        var wall_normal = Vector2(-wall_dir.y, wall_dir.x)
        var wall_length = p0.distance_to(p1)

        # Place dentils along wall
        var dentil_count = int(wall_length / dentil_spacing)
        for j in range(dentil_count):
            var t = (j + 0.5) / float(dentil_count)
            var dentil_pos = p0.lerp(p1, t)

            # Create dentil block
            var base = Vector3(dentil_pos.x, y, dentil_pos.y)

            var half_width = dentil_width * 0.5
            var dir_3d = Vector3(wall_dir.x, 0, wall_dir.y)
            var normal_3d = Vector3(wall_normal.x, 0, wall_normal.y)

            var corners = [
                base - dir_3d * half_width,
                base + dir_3d * half_width,
                base + dir_3d * half_width + normal_3d * dentil_depth,
                base - dir_3d * half_width + normal_3d * dentil_depth
            ]

            var corners_top = []
            for corner in corners:
                corners_top.append(corner + Vector3.UP * dentil_height)

            # Create dentil faces
            # Front
            add_quad(st, corners[0], corners[1], corners_top[1], corners_top[0])
            # Side
            add_quad(st, corners[1], corners[2], corners_top[2], corners_top[1])
            # Bottom
            add_quad(st, corners[0], corners[1], corners[2], corners[3])

## Add brackets under eaves
func _add_brackets(st: SurfaceTool, footprint: PackedVector2Array,
                   height: float, scale: float) -> void:
    var bracket_width = 0.3 * scale
    var bracket_height = 0.5 * scale
    var bracket_depth = 0.4 * scale
    var bracket_spacing = 2.0 * scale

    var point_count = footprint.size()

    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        var wall_dir = (p1 - p0).normalized()
        var wall_normal = Vector2(-wall_dir.y, wall_dir.x)
        var wall_length = p0.distance_to(p1)

        # Place brackets along wall
        var bracket_count = max(1, int(wall_length / bracket_spacing))
        for j in range(bracket_count):
            var t = (j + 1.0) / (bracket_count + 1.0)
            var bracket_pos = p0.lerp(p1, t)

            _create_bracket(st, bracket_pos, wall_dir, wall_normal,
                            height, bracket_width, bracket_height, bracket_depth)

## Create a single bracket
func _create_bracket(st: SurfaceTool, position: Vector2, wall_dir: Vector2,
                     wall_normal: Vector2, height: float, width: float,
                     bracket_height: float, depth: float) -> void:
    var base_y = height - bracket_height

    var dir_3d = Vector3(wall_dir.x, 0, wall_dir.y)
    var normal_3d = Vector3(wall_normal.x, 0, wall_normal.y)

    var base = Vector3(position.x, base_y, position.y)

    # Bracket profile: tapers from wall to eave
    var half_width = width * 0.5

    # Bottom points (at wall)
    var bottom_left = base - dir_3d * half_width
    var bottom_right = base + dir_3d * half_width

    # Top points (at eave, wider and projecting)
    var top_left = base + Vector3.UP * bracket_height - dir_3d * half_width * 0.8 + normal_3d * depth
    var top_right = base + Vector3.UP * bracket_height + dir_3d * half_width * 0.8 + normal_3d * depth

    # Front face (visible from below)
    add_quad(st, bottom_left, bottom_right, top_right, top_left)

    # Side faces
    var back_left = bottom_left
    var back_right = bottom_right
    var back_top_left = top_left - normal_3d * depth * 0.5
    var back_top_right = top_right - normal_3d * depth * 0.5

    # Left side
    add_quad(st, back_left, bottom_left, top_left, back_top_left)
    # Right side
    add_quad(st, bottom_right, back_right, back_top_right, top_right)

## Add pediment (triangular decoration above door or window)
## This would typically be called by door/window components, not in bulk generation
func create_pediment(st: SurfaceTool, center: Vector3, width: float,
                     height: float, depth: float, style: String = "triangular") -> void:
    match style:
        "triangular":
            _create_triangular_pediment(st, center, width, height, depth)
        "segmental":
            _create_segmental_pediment(st, center, width, height, depth)
        "broken":
            _create_broken_pediment(st, center, width, height, depth)

func _create_triangular_pediment(st: SurfaceTool, center: Vector3,
                                 width: float, height: float, depth: float) -> void:
    var half_w = width * 0.5
    var peak = center + Vector3.UP * height

    var left = center - Vector3.RIGHT * half_w
    var right = center + Vector3.RIGHT * half_w

    # Front face
    var normal = Vector3(0, 0, 1)
    st.set_normal(normal)
    st.set_uv(Vector2(0, 0))
    st.add_vertex(left)

    st.set_normal(normal)
    st.set_uv(Vector2(1, 0))
    st.add_vertex(right)

    st.set_normal(normal)
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(peak)

func _create_segmental_pediment(st: SurfaceTool, center: Vector3,
                                width: float, height: float, depth: float) -> void:
    # Arch shape pediment
    var segments = 12
    var half_w = width * 0.5

    for i in range(segments):
        var angle1 = PI + (i / float(segments)) * PI
        var angle2 = PI + ((i + 1) / float(segments)) * PI

        var x1 = cos(angle1) * half_w
        var y1 = sin(angle1) * height
        var x2 = cos(angle2) * half_w
        var y2 = sin(angle2) * height

        var p1 = center + Vector3(x1, y1, 0)
        var p2 = center + Vector3(x2, y2, 0)

        # Create thin segment
        var normal = Vector3(0, 0, 1)
        st.set_normal(normal)
        st.add_vertex(p1)
        st.set_normal(normal)
        st.add_vertex(p2)
        st.set_normal(normal)
        st.add_vertex(center)

func _create_broken_pediment(st: SurfaceTool, center: Vector3,
                              width: float, height: float, depth: float) -> void:
    # Pediment with gap in center (often has urn or finial)
    var gap_width = width * 0.2
    var half_w = width * 0.5
    var peak_height = height

    var left_base = center - Vector3.RIGHT * half_w
    var left_peak = center - Vector3.RIGHT * gap_width * 0.5 + Vector3.UP * peak_height
    var right_peak = center + Vector3.RIGHT * gap_width * 0.5 + Vector3.UP * peak_height
    var right_base = center + Vector3.RIGHT * half_w

    # Left triangle
    var normal = Vector3(0, 0, 1)
    st.set_normal(normal)
    st.add_vertex(left_base)
    st.set_normal(normal)
    st.add_vertex(center - Vector3.RIGHT * gap_width * 0.5)
    st.set_normal(normal)
    st.add_vertex(left_peak)

    # Right triangle
    st.set_normal(normal)
    st.add_vertex(center + Vector3.RIGHT * gap_width * 0.5)
    st.set_normal(normal)
    st.add_vertex(right_base)
    st.set_normal(normal)
    st.add_vertex(right_peak)
