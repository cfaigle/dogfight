extends Node3D
var _a = Vector3.ZERO
var _b = Vector3.ZERO
var _life = 0.15  # Extended life for better visibility
var _t = 0.0

var _mesh_instance: MeshInstance3D = null
var _width: float = 1.0  # Increased width for better visibility

func _ready() -> void:
    # Ensure we have a valid mesh instance
    if _mesh_instance == null:
        _mesh_instance = MeshInstance3D.new()
        add_child(_mesh_instance)

    # Create a thicker line using an ImmediateMesh approach
    var immediate_mesh = ImmediateMesh.new()
    _mesh_instance.mesh = immediate_mesh

    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.85, 0.3, 1.0)  # More vibrant yellow-orange
    mat.emission_energy = 5.0  # Even brighter emission
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)  # More vibrant albedo
    # Add double-sided rendering to make tracer visible from all angles
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    _mesh_instance.material_override = mat

func setup(a: Vector3, b: Vector3, life: float) -> void:
    print("DEBUG: Tracer setup() called with a=", a, " b=", b, " life=", life)
    _a = a
    _b = b
    _life = life

    # Set the global position to the start point
    global_position = a

    # Calculate relative end point for the mesh
    var relative_b = b - a
    _rebuild(relative_b)

func set_color(c: Color) -> void:
    if _mesh_instance and _mesh_instance.material_override:
        var m := _mesh_instance.material_override as StandardMaterial3D
        m.emission = c
        m.albedo_color = c

func _process(dt: float) -> void:
    _t += dt
    if _t >= _life:
        queue_free()
        return
    # Fade out effect
    if _mesh_instance and _mesh_instance.material_override:
        var m = _mesh_instance.material_override as StandardMaterial3D
        var k = 1.0 - (_t / _life)
        m.albedo_color.a = 0.8 * k
        m.emission_energy = 3.0 * k

func _rebuild(relative_direction: Vector3) -> void:
    print("DEBUG: Tracer _rebuild() called - relative_direction:", relative_direction)
    if _mesh_instance == null:
        printerr("ERROR: _mesh_instance is null in tracer _rebuild()")
        return
    var immediate_mesh = _mesh_instance.mesh as ImmediateMesh
    if immediate_mesh == null:
        printerr("ERROR: ImmediateMesh is null in tracer")
        return
    immediate_mesh.clear_surfaces()
    print("DEBUG: Cleared surfaces, creating tracer mesh...")

    # Create a thicker line using a rectangle approach for better visibility
    var direction = relative_direction
    var length = direction.length()
    print("DEBUG: Direction: ", direction, " Length: ", length)
    if length > 0:
        var forward = direction.normalized()
        var right = forward.cross(Vector3.UP).normalized()
        if right.length() < 0.001:  # Handle case where forward is parallel to UP
            right = forward.cross(Vector3.RIGHT).normalized()
            if right.length() < 0.001:  # Handle case where forward is parallel to RIGHT
                right = Vector3.RIGHT
        right = right.normalized()
        print("DEBUG: Forward: ", forward, " Right: ", right)

        # Create a wider line by drawing a rectangle
        var half_width = _width * 0.5
        var offset = right * half_width
        print("DEBUG: Half width: ", half_width, " Offset: ", offset)

        # Create a rectangular shape (two triangles forming a rectangle)
        var start1 = Vector3.ZERO - offset
        var start2 = Vector3.ZERO + offset
        var end1 = direction - offset
        var end2 = direction + offset
        print("DEBUG: start1: ", start1, " start2: ", start2, " end1: ", end1, " end2: ", end2)

        # Begin surface with proper primitive type
        immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

        # Triangle 1: start1 -> end1 -> start2
        immediate_mesh.surface_add_vertex(start1)
        immediate_mesh.surface_add_vertex(end1)
        immediate_mesh.surface_add_vertex(start2)

        # Triangle 2: start2 -> end1 -> end2
        immediate_mesh.surface_add_vertex(start2)
        immediate_mesh.surface_add_vertex(end1)
        immediate_mesh.surface_add_vertex(end2)

        immediate_mesh.surface_end()
        print("DEBUG: Tracer mesh created successfully")
    else:
        # If length is 0, create a small point
        immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
        var point = Vector3.ZERO
        immediate_mesh.surface_add_vertex(point)
        immediate_mesh.surface_add_vertex(point + Vector3(0.1, 0, 0))
        immediate_mesh.surface_add_vertex(point + Vector3(0, 0.1, 0))
        immediate_mesh.surface_end()
        print("DEBUG: Created point tracer for zero-length")
