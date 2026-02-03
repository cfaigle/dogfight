extends "res://effects/particle_effect_base.gd"

const TEX_DUST := preload("res://effects/textures/dust.png")

func _ready() -> void:
    lifetime = 0.9
    _spawn_dust_puff()
    _spawn_grit()
    super._ready()

func _spawn_dust_puff() -> void:
    var p := GPUParticles3D.new()
    p.amount = 50
    p.lifetime = 0.3
    p.one_shot = true
    p.explosiveness = 0.5
    p.randomness = 0.90
    p.visibility_aabb = AABB(Vector3(-120, -40, -120), Vector3(240, 150, 240))

    p.draw_pass_1 = _make_quad(TEX_DUST)

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 60.0
    mat.initial_velocity_min = 8.0
    mat.initial_velocity_max = 25.0
    mat.gravity = Vector3(0, -6.5, 0)
    mat.damping_min = 0.8
    mat.damping_max = 2.0
    mat.scale_min = 1.75
    mat.scale_max = 4.0
    mat.angle_min = -180.0
    mat.angle_max = 180.0
    mat.angular_velocity_min = -45.0
    mat.angular_velocity_max = 45.0
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 0.55
    mat.color_ramp = _ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _spawn_grit() -> void:
    var p := GPUParticles3D.new()
    p.amount = 20
    p.lifetime = 0.3
    p.one_shot = true
    p.explosiveness = 0.5
    p.randomness = 0.85
    p.visibility_aabb = AABB(Vector3(-100, -40, -100), Vector3(200, 120, 200))

    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.3, 0.3, 0.3)
    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.albedo_color = Color(0.25, 0.20, 0.15, 1.0)
    mesh.material = sm
    p.draw_pass_1 = mesh

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 75.0
    mat.initial_velocity_min = 15.0
    mat.initial_velocity_max = 40.0
    mat.gravity = Vector3(0, -18.0, 0)
    mat.damping_min = 0.5
    mat.damping_max = 1.2
    mat.scale_min = 1.0
    mat.scale_max = 2.5
    mat.angular_velocity_min = -250.0
    mat.angular_velocity_max = 250.0
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 0.45
    mat.color_ramp = _ramp_grit()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _make_quad(tex: Texture2D) -> QuadMesh:
    var q := QuadMesh.new()
    q.size = Vector2(1.0, 1.0)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    m.albedo_texture = tex
    m.albedo_color = Color(1, 1, 1, 1)
    q.material = m
    return q

func _ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.85, 0.72, 0.55, 0.55))
    g.add_point(0.25, Color(0.65, 0.52, 0.35, 0.35))
    g.add_point(0.80, Color(0.40, 0.32, 0.22, 0.10))
    g.add_point(1.0, Color(0.30, 0.26, 0.20, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t

func _ramp_grit() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.35, 0.28, 0.20, 0.90))
    g.add_point(0.60, Color(0.30, 0.25, 0.18, 0.55))
    g.add_point(1.0, Color(0.25, 0.22, 0.18, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
