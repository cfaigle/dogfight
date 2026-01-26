extends Node3D

const AutoDestructScript = preload("res://scripts/components/auto_destruct.gd")

@export var life = 1.2
@export var radius = 4.5
@export var intensity = 1.0

var _t = 0.0
var _light: OmniLight3D

func _ready() -> void:
    # Particles
    var p = GPUParticles3D.new()
    p.amount = int(120 * intensity)
    p.lifetime = life * 0.85
    p.one_shot = true
    p.explosiveness = 0.85
    p.randomness = 0.55

    var mat = ParticleProcessMaterial.new()
    mat.direction = Vector3(0,1,0)
    mat.spread = 180.0
    mat.initial_velocity_min = 6.0 * intensity
    mat.initial_velocity_max = 22.0 * intensity
    mat.gravity = Vector3(0, -9.8, 0)
    mat.scale_min = 0.15
    mat.scale_max = 0.55
    mat.color = Color(1.0, 0.5, 0.9, 1.0)
    mat.color_ramp = _make_ramp()
    p.process_material = mat

    add_child(p)
    p.emitting = true

    # Flash light
    _light = OmniLight3D.new()
    _light.light_energy = 8.0 * intensity
    _light.omni_range = radius * 2.0
    _light.light_color = Color(1.0, 0.7, 1.0, 1.0)
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
