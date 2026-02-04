extends "res://effects/particle_effect_base.gd"

const TEX_LEAF := preload("res://effects/textures/leaf.png")

func _ready() -> void:
    lifetime = 1.0
    _spawn_leaves()
    super._ready()

func _spawn_leaves() -> void:
    var p := GPUParticles3D.new()
    p.amount = 15
    p.lifetime = 1.0
    p.one_shot = true
    p.explosiveness = 0.3
    p.randomness = 0.92
    p.speed_scale = 1.5
    p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))

    p.draw_pass_1 = _make_quad(TEX_LEAF)

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 170.0
    mat.initial_velocity_min = 10.0
    mat.initial_velocity_max = 30.0

    # "Wind" + gentle fall.
    mat.gravity = Vector3(1.2, -2.6, 0.8)
    mat.damping_min = 0.5
    mat.damping_max = 1.8

    mat.scale_min = 1.5
    mat.scale_max = 4.0
    mat.angle_min = -180.0
    mat.angle_max = 180.0
    mat.angular_velocity_min = -520.0
    mat.angular_velocity_max = 520.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 1.2

    mat.color_ramp = _ramp()
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
    g.add_point(0.0, Color(0.55, 0.80, 0.45, 0.95))
    g.add_point(0.45, Color(0.70, 0.80, 0.35, 0.85))
    g.add_point(0.85, Color(0.65, 0.55, 0.25, 0.45))
    g.add_point(1.0, Color(0.40, 0.30, 0.15, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
