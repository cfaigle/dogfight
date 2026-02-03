extends "res://effects/particle_effect_base.gd"

func _ready() -> void:
    lifetime = 1.5
    _spawn_chunks()
    super._ready()

func _spawn_chunks() -> void:
    var p := GPUParticles3D.new()
    p.amount = 70
    p.lifetime = 1.2
    p.one_shot = true
    p.explosiveness = 0.5
    p.randomness = 0.85
    p.visibility_aabb = AABB(Vector3(-50, -40, -50), Vector3(100, 90, 100))

    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.12, 0.10, 0.18)

    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.albedo_color = Color(0.35, 0.32, 0.28, 1.0)
    mesh.material = sm
    p.draw_pass_1 = mesh

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 175.0
    mat.initial_velocity_min = 6.0
    mat.initial_velocity_max = 18.0
    mat.gravity = Vector3(0, -24.0, 0)
    mat.damping_min = 0.15
    mat.damping_max = 0.9
    mat.scale_min = 0.65
    mat.scale_max = 1.6
    mat.angular_velocity_min = -520.0
    mat.angular_velocity_max = 520.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 1.1

    mat.color_ramp = _ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.50, 0.46, 0.40, 1.0))
    g.add_point(0.55, Color(0.35, 0.32, 0.28, 1.0))
    g.add_point(1.0, Color(0.20, 0.18, 0.16, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
