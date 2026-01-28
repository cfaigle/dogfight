extends Node3D
var _a = Vector3.ZERO
var _b = Vector3.ZERO
var _life = 0.08  # Extended life for better visibility
var _t = 0.0

var _mesh_instance: MeshInstance3D
var _width: float = 0.3  # Increased width for better visibility

func _ready() -> void:
    _mesh_instance = MeshInstance3D.new()
    add_child(_mesh_instance)

    # Create a thicker line using a cylinder-like approach
    _mesh_instance.mesh = ImmediateMesh.new()
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.85, 0.3, 1.0)  # More vibrant yellow-orange
    mat.emission_energy = 3.0  # Brighter emission
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(1.0, 0.7, 0.2, 0.9)  # More vibrant albedo
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y  # Face camera for better visibility
    _mesh_instance.material_override = mat

func setup(a: Vector3, b: Vector3, life: float) -> void:
    _a = a
    _b = b
    _life = life
    _rebuild()

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

func _rebuild() -> void:
    if _mesh_instance == null:
        return
    var im = _mesh_instance.mesh as ImmediateMesh
    im.clear_surfaces()

    # Create a thicker line using a rectangle approach for better visibility
    var direction = _b - _a
    var length = direction.length()
    if length > 0:
        var forward = direction.normalized()
        var right = forward.cross(Vector3.UP).normalized()
        if right.length() < 0.001:  # Handle case where forward is parallel to UP
            right = Vector3.RIGHT
        right = right.normalized()

        # Create a wider line by drawing a rectangle
        var half_width = _width * 0.5
        var offset = right * half_width

        im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

        # Define vertices for a thick line (rectangle)
        var start1 = _a - offset - global_position
        var start2 = _a + offset - global_position
        var end1 = _b - offset - global_position
        var end2 = _b + offset - global_position

        # Triangle 1
        im.surface_add_vertex(start1)
        im.surface_add_vertex(end1)
        im.surface_add_vertex(start2)

        # Triangle 2
        im.surface_add_vertex(start2)
        im.surface_add_vertex(end1)
        im.surface_add_vertex(end2)

        im.surface_end()
