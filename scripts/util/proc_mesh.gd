extends Node
# Low-poly fighter generated in code (no external assets).
# Returns ArrayMesh with a single surface.

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    var n = Plane(a, b, c).normal
    st.set_normal(n); st.add_vertex(a)
    st.set_normal(n); st.add_vertex(b)
    st.set_normal(n); st.add_vertex(c)

static func make_fighter_mesh(scale: float = 1.0) -> ArrayMesh:
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Simple “dart” fuselage + wings.
    # Coordinate system: forward = -Z, up = +Y, right = +X
    var s = scale

    # Points
    var nose = Vector3(0, 0, -2.6) * s
    var tail = Vector3(0, 0, 2.2) * s
    var top  = Vector3(0, 0.35, 0.3) * s
    var belly= Vector3(0, -0.25, 0.5) * s
    var lw_tip = Vector3(-2.1, 0.0, 0.2) * s
    var rw_tip = Vector3( 2.1, 0.0, 0.2) * s
    var lw_back= Vector3(-1.1, 0.0, 1.2) * s
    var rw_back= Vector3( 1.1, 0.0, 1.2) * s
    var fin_top= Vector3(0, 0.95, 1.55) * s
    # Helpers

    # Fuselage sides
    _tri(st, nose, top, rw_tip)
    _tri(st, nose, rw_tip, belly)
    _tri(st, nose, belly, lw_tip)
    _tri(st, nose, lw_tip, top)

    # Rear fuselage
    _tri(st, tail, rw_back, top)
    _tri(st, tail, top, lw_back)
    _tri(st, tail, belly, rw_back)
    _tri(st, tail, lw_back, belly)

    # Wings
    _tri(st, rw_tip, rw_back, top)
    _tri(st, lw_back, lw_tip, top)
    _tri(st, rw_tip, belly, rw_back)
    _tri(st, lw_back, belly, lw_tip)

    # Vertical fin
    _tri(st, fin_top, tail, top)
    _tri(st, fin_top, top, tail) # double-sided

    st.generate_normals()
    st.index()
    var mesh = st.commit()
    return mesh
