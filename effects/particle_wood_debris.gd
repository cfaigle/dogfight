extends "res://effects/particle_effect_base.gd"

func _ready() -> void:
    lifetime = 3.0
    _spawn_splinters()
    super._ready()

func _spawn_splinters() -> void:
    var p := GPUParticles3D.new()
    p.amount = 50
    p.lifetime = 1.0
    p.one_shot = true
    p.explosiveness = 0.97
    p.randomness = 0.85
    p.visibility_aabb = AABB(Vector3(-150, -100, -150), Vector3(300, 250, 300))

    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.4, 0.4, 1.5)

    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.albedo_color = Color(0.45, 0.30, 0.18, 1.0)
    mesh.material = sm
    p.draw_pass_1 = mesh

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 180.0
    mat.initial_velocity_min = 20.0
    mat.initial_velocity_max = 55.0
    mat.gravity = Vector3(0, -24.0, 0)
    mat.damping_min = 0.05
    mat.damping_max = 0.75
    mat.scale_min = 2.5
    mat.scale_max = 6.0
    mat.angular_velocity_min = -820.0
    mat.angular_velocity_max = 820.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 1.0

    mat.color_ramp = _ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.62, 0.43, 0.26, 1.0))
    g.add_point(0.65, Color(0.45, 0.30, 0.18, 0.85))
    g.add_point(1.0, Color(0.25, 0.18, 0.12, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
