class_name GrainSiloGeometry
extends RefCounted

## Creates grain silo geometry with stackable cylinders and dome top

static func create(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Silo parameters
    var num_cylinders: int = rng.randi_range(1, 3)
    var cylinder_height: float = rng.randf_range(12.0, 18.0)
    var total_height: float = num_cylinders * cylinder_height
    var radius: float = rng.randf_range(3.0, 5.0)
    var dome_height: float = radius * 0.6
    var sides: int = 16

    # Create stacked cylinders
    for i in range(num_cylinders):
        var y_bottom: float = i * cylinder_height
        var y_top: float = (i + 1) * cylinder_height
        _add_cylinder(st, y_bottom, y_top, radius, sides)

    # Add dome top (simplified as cone)
    _add_dome_top(st, total_height, radius, dome_height, sides)

    # Optional: Add ladder (70% chance)
    if rng.randf() < 0.7:
        _add_ladder(st, total_height * 0.8, radius)

    # Finalize mesh
    st.generate_normals()
    var mesh := st.commit()

    # Material (metallic silver/aluminum)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.75, 0.75, 0.8)
    mat.metallic = 0.9
    mat.roughness = 0.3
    mesh.surface_set_material(0, mat)

    return mesh

# Helper: Create straight cylinder between two Y levels
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

        # Two triangles forming quad
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

# Helper: Create dome top (simplified as cone)
static func _add_dome_top(st: SurfaceTool, base_y: float, radius: float,
                          dome_height: float, sides: int) -> void:
    var peak := Vector3(0, base_y + dome_height, 0)

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * radius
        var z1: float = sin(angle1) * radius
        var x2: float = cos(angle2) * radius
        var z2: float = sin(angle2) * radius

        var base_v1 := Vector3(x1, base_y, z1)
        var base_v2 := Vector3(x2, base_y, z2)

        # Triangle to peak (counter-clockwise winding for outward normals)
        st.add_vertex(peak)
        st.add_vertex(base_v1)
        st.add_vertex(base_v2)

# Helper: Create simple ladder
static func _add_ladder(st: SurfaceTool, height: float, silo_radius: float) -> void:
    var ladder_width: float = 0.4
    var ladder_thickness: float = 0.1
    var ladder_x: float = silo_radius

    # Two vertical rails
    _add_box(st, Vector3(ladder_x, 0, -ladder_width * 0.5),
              Vector3(ladder_x + ladder_thickness, height, -ladder_width * 0.5 + 0.08))
    _add_box(st, Vector3(ladder_x, 0, ladder_width * 0.5 - 0.08),
              Vector3(ladder_x + ladder_thickness, height, ladder_width * 0.5))

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
