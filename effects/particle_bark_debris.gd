extends "res://effects/particle_effect_base.gd"

func _ready() -> void:
    lifetime = 1.0
    _spawn_bark()
    super._ready()

func _spawn_bark() -> void:
    var p := GPUParticles3D.new()
    p.amount = 6
    p.lifetime = 0.6
    p.one_shot = true
    p.explosiveness = 0.98
    p.randomness = 0.85
    p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 70, 80))

    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.06, 0.03, 0.09)

    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.albedo_color = Color(0.22, 0.15, 0.10, 1.0)
    mesh.material = sm
    p.draw_pass_1 = mesh

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 175.0
    mat.initial_velocity_min = 5.0
    mat.initial_velocity_max = 16.0
    mat.gravity = Vector3(0, -22.0, 0)
    mat.damping_min = 0.15
    mat.damping_max = 1.1
    mat.scale_min = 0.75
    mat.scale_max = 1.6
    mat.angular_velocity_min = -900.0
    mat.angular_velocity_max = 900.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 1.0

    mat.color_ramp = _ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.30, 0.22, 0.15, 1.0))
    g.add_point(0.7, Color(0.22, 0.15, 0.10, 0.85))
    g.add_point(1.0, Color(0.12, 0.08, 0.05, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
