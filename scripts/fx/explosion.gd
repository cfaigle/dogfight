extends Node3D

const AutoDestructScript = preload("res://scripts/components/auto_destruct.gd")

@export var life = 1.0
@export var radius = 15.0
@export var intensity = 1.0

var _t = 0.0
var _light: OmniLight3D

func _ready() -> void:
    # Particles - reduced from 300 to 100 base for GPU performance
    var p = GPUParticles3D.new()
    p.amount = int(100 * intensity)  # Reduced from 300 to prevent GPU overload
    p.lifetime = life * 0.85
    p.one_shot = true
    p.explosiveness = 0.9
    p.randomness = 0.65
    p.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))

    var mat = ParticleProcessMaterial.new()
    mat.direction = Vector3(0,1,0)
    mat.spread = 180.0
    mat.initial_velocity_min = 15.0 * intensity
    mat.initial_velocity_max = 45.0 * intensity
    mat.gravity = Vector3(0, -9.8, 0)
    mat.scale_min = 1.5
    mat.scale_max = 4.5
    mat.color = Color(1.0, 0.5, 0.9, 1.0)
    mat.color_ramp = _make_ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

    # Flash light - much brighter and larger for arcade feel!
    _light = OmniLight3D.new()
    _light.light_energy = 25.0 * intensity
    _light.omni_range = radius * 4.0
    _light.light_color = Color(1.0, 0.7, 0.3, 1.0)
    add_child(_light)

    # Self-destruct
    var ad = AutoDestructScript.new()
    ad.life = life
    add_child(ad)

func _process(dt: float) -> void:
    _t += dt
    if _light:
        _light.light_energy = lerp(_light.light_energy, 0.0, 1.0 - exp(-10.0 * dt))

func _make_ramp() -> GradientTexture1D:
    var g = Gradient.new()
    g.add_point(0.0, Color(1.0, 0.95, 0.80, 1.0))
    g.add_point(0.25, Color(1.0, 0.55, 0.15, 0.90))
    g.add_point(0.65, Color(0.22, 0.16, 0.12, 0.40))
    g.add_point(1.0, Color(0.05, 0.05, 0.05, 0.0))
    var t = GradientTexture1D.new()
    t.gradient = g
    return t
