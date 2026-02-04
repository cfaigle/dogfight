extends "res://effects/particle_effect_base.gd"

const TEX_SPARK := preload("res://effects/textures/spark.png")

var _light: OmniLight3D
var _t := 0.0

func _ready() -> void:
    lifetime = 0.95
    _spawn_sparks()
    _spawn_flash_light()
    super._ready()

func _process(dt: float) -> void:
    _t += dt
    if _light:
        # Quick fade so it reads as a bright spark pop.
        _light.light_energy = lerp(_light.light_energy, 0.0, 1.0 - exp(-20.0 * dt))

func _spawn_sparks() -> void:
    var p := GPUParticles3D.new()
    p.amount = 250
    p.lifetime = 1.2
    p.one_shot = true
    p.explosiveness = 1.0
    p.randomness = 0.95
    p.speed_scale = 1.8
    p.visibility_aabb = AABB(Vector3(-120, -120, -120), Vector3(240, 240, 240))

    p.draw_pass_1 = _make_quad(TEX_SPARK)

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 1, 0)
    mat.spread = 180.0
    mat.initial_velocity_min = 25.0
    mat.initial_velocity_max = 65.0
    mat.gravity = Vector3(0, -22.0, 0)
    mat.damping_min = 0.2
    mat.damping_max = 0.9
    mat.scale_min = 0.8
    mat.scale_max = 2.5
    mat.angle_min = -180.0
    mat.angle_max = 180.0
    mat.angular_velocity_min = -1400.0
    mat.angular_velocity_max = 1400.0

    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
    mat.emission_point_count = 1

    mat.color_ramp = _ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

func _spawn_flash_light() -> void:
    _light = OmniLight3D.new()
    _light.light_color = Color(1.0, 0.65, 0.20, 1.0)
    _light.light_energy = 20.0
    _light.omni_range = 50.0
    add_child(_light)

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
    m.emission_enabled = true
    m.emission = Color(1.0, 0.65, 0.25, 1.0)
    m.emission_energy_multiplier = 8.0
    q.material = m
    return q

func _ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(1.0, 0.95, 0.75, 1.0))
    g.add_point(0.2, Color(1.0, 0.65, 0.20, 0.95))
    g.add_point(0.7, Color(1.0, 0.30, 0.10, 0.35))
    g.add_point(1.0, Color(0.5, 0.15, 0.10, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t
