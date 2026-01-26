extends Node3D
var _a = Vector3.ZERO
var _b = Vector3.ZERO
var _life = 0.06
var _t = 0.0

var _mesh_instance: MeshInstance3D

func _ready() -> void:
    _mesh_instance = MeshInstance3D.new()
    add_child(_mesh_instance)
    _mesh_instance.mesh = ImmediateMesh.new()
    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.78, 0.25, 1.0)
    mat.emission_energy = 2.5
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(0.2, 1.0, 0.9, 0.8)
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
    # Fade
    if _mesh_instance and _mesh_instance.material_override:
        var m = _mesh_instance.material_override as StandardMaterial3D
        var k = 1.0 - (_t / _life)
        m.albedo_color.a = 0.7 * k
        m.emission_energy = 2.5 * k

func _rebuild() -> void:
    if _mesh_instance == null:
        return
    var im = _mesh_instance.mesh as ImmediateMesh
    im.clear_surfaces()
    im.surface_begin(Mesh.PRIMITIVE_LINES)
    im.surface_add_vertex(_a - global_position)
    im.surface_add_vertex(_b - global_position)
    im.surface_end()
