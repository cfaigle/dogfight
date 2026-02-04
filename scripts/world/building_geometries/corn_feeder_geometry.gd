class_name CornFeederGeometry
extends RefCounted

## Creates corn feeder geometry with elevated bin on legs and funnel bottom

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Feeder parameters
    var bin_height: float = rng.randf_range(8.0, 12.0)
    var bin_radius: float = rng.randf_range(2.5, 4.0)
    var leg_height: float = rng.randf_range(4.0, 6.0)
    var leg_thickness: float = 0.3
    var funnel_height: float = rng.randf_range(2.0, 3.0)
    var top_cone_height: float = rng.randf_range(1.5, 2.5)
    var sides: int = rng.randi_range(12, 16)

    var bin_bottom_y: float = leg_height
    var bin_top_y: float = bin_bottom_y + bin_height
    var funnel_bottom_y: float = leg_height - funnel_height
    var funnel_opening_radius: float = 0.5

    # Create 4 legs at corners
    var leg_positions: Array = [
        Vector3(bin_radius * 0.6, 0, bin_radius * 0.6),
        Vector3(-bin_radius * 0.6, 0, bin_radius * 0.6),
        Vector3(-bin_radius * 0.6, 0, -bin_radius * 0.6),
        Vector3(bin_radius * 0.6, 0, -bin_radius * 0.6)
    ]

    for leg_pos in leg_positions:
        _add_box(st, leg_pos, leg_pos + Vector3(leg_thickness, leg_height, leg_thickness))

    # Create inverted funnel (cone pointing down)
    _add_inverted_cone(st, funnel_bottom_y, bin_bottom_y,
                       funnel_opening_radius, bin_radius, sides)

    # Create main bin (straight cylinder)
    _add_cylinder(st, bin_bottom_y, bin_top_y, bin_radius, sides)

    # Create top cone (rain protection)
    _add_cone(st, bin_top_y, bin_top_y + top_cone_height,
              bin_radius * 1.1, sides)

    # Optional: Add ladder on one leg (60% chance)
    if rng.randf() < 0.6:
        var ladder_leg: Vector3 = leg_positions[0]
        _add_simple_ladder(st, ladder_leg, leg_height, bin_height * 0.8, leg_thickness)

    # Finalize mesh
    st.generate_normals()
    var mesh := st.commit()

    # Material (rusty farm equipment red-brown)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.65, 0.35, 0.25)
    mat.metallic = 0.5
    mat.roughness = 0.7
    mesh.surface_set_material(0, mat)

    return mesh

# Helper: Create straight cylinder
static func _add_cylinder(st: SurfaceTool, y_bottom: float, y_top: float,
                           radius: float, sides: int) -> void:
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * radius
        var z1: float = sin(angle1) * radius
        var x2: float = cos(angle2) * radius
        var z2: float = sin(angle2) * radius

        var v0 := Vector3(x1, y_bottom, z1)
        var v1 := Vector3(x2, y_bottom, z2)
        var v2 := Vector3(x2, y_top, z2)
        var v3 := Vector3(x1, y_top, z1)

        st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
        st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v3)

# Helper: Create cone pointing up (from base_radius to point)
static func _add_cone(st: SurfaceTool, base_y: float, peak_y: float,
                      base_radius: float, sides: int) -> void:
    var peak := Vector3(0, peak_y, 0)

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * base_radius
        var z1: float = sin(angle1) * base_radius
        var x2: float = cos(angle2) * base_radius
        var z2: float = sin(angle2) * base_radius

        var base_v1 := Vector3(x1, base_y, z1)
        var base_v2 := Vector3(x2, base_y, z2)

        # Counter-clockwise winding for outward normals
        st.add_vertex(peak); st.add_vertex(base_v1); st.add_vertex(base_v2)

# Helper: Create inverted cone (funnel - wider at top, narrow at bottom)
static func _add_inverted_cone(st: SurfaceTool, bottom_y: float, top_y: float,
                                bottom_radius: float, top_radius: float, sides: int) -> void:
    var bottom_center := Vector3(0, bottom_y, 0)

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Top edge (wide opening connecting to bin)
        var x1_top: float = cos(angle1) * top_radius
        var z1_top: float = sin(angle1) * top_radius
        var x2_top: float = cos(angle2) * top_radius
        var z2_top: float = sin(angle2) * top_radius

        var top_v1 := Vector3(x1_top, top_y, z1_top)
        var top_v2 := Vector3(x2_top, top_y, z2_top)

        # Taper to point at bottom (funnel) - counter-clockwise for outward normals
        st.add_vertex(bottom_center); st.add_vertex(top_v2); st.add_vertex(top_v1)

# Helper: Simple ladder on leg
static func _add_simple_ladder(st: SurfaceTool, leg_base: Vector3, leg_height: float,
                                ladder_height: float, leg_thickness: float) -> void:
    var ladder_width: float = 0.3
    var ladder_thick: float = 0.08

    # Position ladder on side of leg
    var ladder_x: float = leg_base.x + leg_thickness
    var ladder_z_center: float = leg_base.z + leg_thickness * 0.5

    # Two vertical rails running up the leg
    _add_box(st, Vector3(ladder_x, 0, ladder_z_center - ladder_width * 0.5),
              Vector3(ladder_x + ladder_thick, leg_height + ladder_height,
                      ladder_z_center - ladder_width * 0.5 + ladder_thick))
    _add_box(st, Vector3(ladder_x, 0, ladder_z_center + ladder_width * 0.5 - ladder_thick),
              Vector3(ladder_x + ladder_thick, leg_height + ladder_height,
                      ladder_z_center + ladder_width * 0.5))

# Helper: Add box/rectangular prism
static func _add_box(st: SurfaceTool, min_corner: Vector3, max_corner: Vector3) -> void:
    # 8 corners of box
    var v000 := Vector3(min_corner.x, min_corner.y, min_corner.z)
    var v001 := Vector3(min_corner.x, min_corner.y, max_corner.z)
    var v010 := Vector3(min_corner.x, max_corner.y, min_corner.z)
    var v011 := Vector3(min_corner.x, max_corner.y, max_corner.z)
    var v100 := Vector3(max_corner.x, min_corner.y, min_corner.z)
    var v101 := Vector3(max_corner.x, min_corner.y, max_corner.z)
    var v110 := Vector3(max_corner.x, max_corner.y, min_corner.z)
    var v111 := Vector3(max_corner.x, max_corner.y, max_corner.z)

    # 6 faces (12 triangles)
    # Front (+X)
    st.add_vertex(v100); st.add_vertex(v101); st.add_vertex(v111)
    st.add_vertex(v100); st.add_vertex(v111); st.add_vertex(v110)
    # Back (-X)
    st.add_vertex(v001); st.add_vertex(v000); st.add_vertex(v010)
    st.add_vertex(v001); st.add_vertex(v010); st.add_vertex(v011)
    # Right (+Z)
    st.add_vertex(v101); st.add_vertex(v001); st.add_vertex(v011)
    st.add_vertex(v101); st.add_vertex(v011); st.add_vertex(v111)
    # Left (-Z)
    st.add_vertex(v000); st.add_vertex(v100); st.add_vertex(v110)
    st.add_vertex(v000); st.add_vertex(v110); st.add_vertex(v010)
    # Top (+Y)
    st.add_vertex(v010); st.add_vertex(v110); st.add_vertex(v111)
    st.add_vertex(v010); st.add_vertex(v111); st.add_vertex(v011)
    # Bottom (-Y)
    st.add_vertex(v001); st.add_vertex(v101); st.add_vertex(v100)
    st.add_vertex(v001); st.add_vertex(v100); st.add_vertex(v000)
