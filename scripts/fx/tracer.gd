extends Node3D
var _a = Vector3.ZERO
var _b = Vector3.ZERO
var _life = 9999.0  # Permanent tracer for debugging - will stay in scene forever
var _t = 0.0

var _mesh_instance: MeshInstance3D = null
var _width: float = 5.0  # Default width (player tracers)

func _ready() -> void:
    # Ensure we have a valid mesh instance
    if _mesh_instance == null:
        _mesh_instance = MeshInstance3D.new()
        add_child(_mesh_instance)

    # Create a crossed-ribbon tracer using an ImmediateMesh approach
    var immediate_mesh = ImmediateMesh.new()
    _mesh_instance.mesh = immediate_mesh

    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.85, 0.3, 1.0)  # More vibrant yellow-orange
    mat.emission_energy_multiplier = 50.0  # Extremely bright emission for better visibility
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)  # More vibrant albedo
    # Add double-sided rendering to make tracer visible from all angles
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    _mesh_instance.material_override = mat

func setup(a: Vector3, b: Vector3, life: float) -> void:
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

func set_width(width: float) -> void:
    _width = width
    # Rebuild the mesh with new width
    if _a != Vector3.ZERO or _b != Vector3.ZERO:
        var relative_b = _b - _a
        _rebuild(relative_b)

func _process(dt: float) -> void:
    _t += dt
    # Don't destroy tracer for debugging - keep it in the scene permanently
    if _t >= _life:
         queue_free()
         return
    # Keep emission energy constant since tracer is permanent
    if _mesh_instance and _mesh_instance.material_override:
        var m = _mesh_instance.material_override as StandardMaterial3D
        # Keep full brightness since tracer is permanent
        m.emission_energy_multiplier = 50.0  # Maintain maximum brightness

func _rebuild(relative_direction: Vector3) -> void:
    if _mesh_instance == null:
        printerr("ERROR: _mesh_instance is null in tracer _rebuild()")
        return
    var immediate_mesh = _mesh_instance.mesh as ImmediateMesh
    if immediate_mesh == null:
        printerr("ERROR: ImmediateMesh is null in tracer")
        return
    immediate_mesh.clear_surfaces()
    # print("DEBUG: Cleared surfaces, creating tracer mesh...")

    # Create a crossed-ribbon tracer for better visibility from all angles
    var direction = relative_direction
    var length = direction.length()
    # print("DEBUG: Direction: ", direction, " Length: ", length)
    if length > 0:
        var forward = direction.normalized()

        # Create two perpendicular ribbons to form a cross
        var right = forward.cross(Vector3.UP).normalized()
        if right.length() < 0.001:  # Handle case where forward is parallel to UP
            right = forward.cross(Vector3.RIGHT).normalized()
            if right.length() < 0.001:  # Handle case where forward is parallel to RIGHT
                right = Vector3.RIGHT
        right = right.normalized()

        var up = forward.cross(right).normalized()
        # print("DEBUG: Forward: ", forward, " Right: ", right, " Up: ", up)

        # Create first ribbon (along right direction)
        var half_width = _width * 0.5
        var offset1 = right * half_width

        # Create a rectangular shape (two triangles forming a rectangle)
        var start1_1 = Vector3.ZERO - offset1
        var start1_2 = Vector3.ZERO + offset1
        var end1_1 = direction - offset1
        var end1_2 = direction + offset1

        # Create second ribbon (along up direction)
        var offset2 = up * half_width
        var start2_1 = Vector3.ZERO - offset2
        var start2_2 = Vector3.ZERO + offset2
        var end2_1 = direction - offset2
        var end2_2 = direction + offset2

        # Begin surface with proper primitive type
        immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

        # First ribbon triangles
        # Triangle 1: start1_1 -> end1_1 -> start1_2
        immediate_mesh.surface_add_vertex(start1_1)
        immediate_mesh.surface_add_vertex(end1_1)
        immediate_mesh.surface_add_vertex(start1_2)

        # Triangle 2: start1_2 -> end1_1 -> end1_2
        immediate_mesh.surface_add_vertex(start1_2)
        immediate_mesh.surface_add_vertex(end1_1)
        immediate_mesh.surface_add_vertex(end1_2)

        # Second ribbon triangles
        # Triangle 3: start2_1 -> end2_1 -> start2_2
        immediate_mesh.surface_add_vertex(start2_1)
        immediate_mesh.surface_add_vertex(end2_1)
        immediate_mesh.surface_add_vertex(start2_2)

        # Triangle 4: start2_2 -> end2_1 -> end2_2
        immediate_mesh.surface_add_vertex(start2_2)
        immediate_mesh.surface_add_vertex(end2_1)
        immediate_mesh.surface_add_vertex(end2_2)

        immediate_mesh.surface_end()
    else:
        # If length is 0, create a small point
        immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
        var point = Vector3.ZERO
        immediate_mesh.surface_add_vertex(point)
        immediate_mesh.surface_add_vertex(point + Vector3(0.1, 0, 0))
        immediate_mesh.surface_add_vertex(point + Vector3(0, 0.1, 0))
        immediate_mesh.surface_end()
        print("DEBUG: Created point tracer for zero-length")
