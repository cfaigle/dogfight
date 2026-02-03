extends "res://effects/particle_effect_base.gd"

const TEX_SMOKE := preload("res://effects/textures/smoke.png")

func _ready() -> void:
    lifetime = 1.5  # Reduced for faster cleanup
    # Single layer only - removed wisp layer to reduce GPU load
    _spawn_smoke_layer(30, 2.5, 0.15, 0.70, 3.0, 10.0, Vector3(0.0, 1.0, 0.0), _ramp_main())
    # Second layer commented out - was causing GPU overload
    # _spawn_smoke_layer(30, 2.5, 0.25, 0.85, 3.0, 8.0, Vector3(0.0, 1.3, 0.0), _ramp_wisp())
    super._ready()

func _spawn_smoke_layer(amount: int, life: float, explosiveness: float, randomness: float, scale_min: float, scale_max: float, buoyancy: Vector3, ramp: GradientTexture1D) -> void:
    var p := GPUParticles3D.new()
    p.amount = amount
    p.lifetime = life
    p.one_shot = true
    p.explosiveness = explosiveness
    p.randomness = randomness
    p.visibility_aabb = AABB(Vector3(-150, -50, -150), Vector3(300, 300, 300))

    var quad := _make_quad(TEX_SMOKE)
    p.draw_pass_1 = quad

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 55.0
    mat.initial_velocity_min = 2.0
    mat.initial_velocity_max = 8.0
    mat.gravity = buoyancy
    mat.damping_min = 0.2
    mat.damping_max = 1.1
    mat.scale_min = scale_min
    mat.scale_max = scale_max
    mat.angle_min = -180.0
    mat.angle_max = 180.0
    mat.angular_velocity_min = -18.0
    mat.angular_velocity_max = 18.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    mat.emission_sphere_radius = 0.9

    mat.color_ramp = ramp
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

func _ramp_main() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.10, 0.10, 0.10, 0.35))
    g.add_point(0.30, Color(0.35, 0.35, 0.35, 0.25))
    g.add_point(0.75, Color(0.55, 0.55, 0.55, 0.12))
    g.add_point(1.0, Color(0.75, 0.75, 0.75, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t

func _ramp_wisp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(0.55, 0.55, 0.55, 0.18))
    g.add_point(0.50, Color(0.75, 0.75, 0.75, 0.10))
    g.add_point(1.0, Color(0.90, 0.90, 0.90, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
