extends Area3D

@export var hit_radius = 3.0

const ExplosionScript = preload("res://scripts/fx/explosion.gd")

var source: Node
var target: Node
var locked = false

var damage = 85.0
var speed = 260.0
var turn_rate = 4.5
var accel = 260.0
var life = 10.0

var vel = Vector3.ZERO
var _t = 0.0
var _spin = 0.0
var _trail: GPUParticles3D
var _light: OmniLight3D

func _ready() -> void:
    monitoring = true
    connect("area_entered", Callable(self, "_on_area_entered"))
    connect("body_entered", Callable(self, "_on_body_entered"))

    _spin = randf_range(-6.0, 6.0)
    _setup_visual()
    _setup_trail()

func arm(p_source: Node, p_target: Node, p_locked: bool, cfg: Dictionary) -> void:
    source = p_source
    target = p_target
    locked = p_locked
    damage = cfg.get("damage", damage)
    speed = cfg.get("speed", speed)
    turn_rate = cfg.get("turn_rate", turn_rate)
    accel = cfg.get("accel", accel)
    life = cfg.get("life", life)
    var f = (-global_transform.basis.z).normalized()
    vel = f * (speed * 0.6)

func _physics_process(dt: float) -> void:
    _t += dt
    if _t >= life:
        _explode()
        return

    # Tiny spin so missiles feel “alive”.
    rotate_object_local(Vector3.FORWARD, _spin * dt)

    # Guidance
    var desired = (-global_transform.basis.z).normalized()
    if locked and is_instance_valid(target):
        var to_t = (target.global_position - global_position)
        var dist = max(to_t.length(), 0.01)
        var tti = clamp(dist / max(speed, 1.0), 0.05, 0.9)

        # Duck-typed velocity lead (works for our Plane nodes, but doesn't require global classes)
        var target_vel = Vector3.ZERO
        var v = target.get("vel")
        if v is Vector3:
            target_vel = v

        desired = (target.global_position + target_vel * tti - global_position).normalized()

    # Turn towards desired
    var f = (-global_transform.basis.z).normalized()
    var axis = f.cross(desired)
    var s = axis.length()
    if s > 0.0001:
        axis = axis / s
        var ang = asin(clamp(s, 0.0, 1.0))
        var max_turn = turn_rate * dt
        var use_ang = min(ang, max_turn)
        global_transform.basis = Basis(axis, use_ang) * global_transform.basis

    # Accelerate forward
    f = (-global_transform.basis.z).normalized()
    vel = vel.move_toward(f * speed, accel * dt)
    global_position += vel * dt

func _on_area_entered(a: Area3D) -> void:
    if a == self:
        return
    if source and (a == source or a.get_parent() == source):
        return
    _hit(a)

func _on_body_entered(b: Node) -> void:
    if source and (b == source or (b is Node and b.get_parent() == source)):
        return
    _hit(b)

func _hit(obj: Object) -> void:
    _apply_damage_to_collider(obj, damage)
    _explode()

func _apply_damage_to_collider(obj: Object, dmg: float) -> void:
    if obj == null:
        return
    var n = obj as Node
    while n:
        if n.has_method("apply_damage"):
            # Apply damage using the new damage system if available
            if Engine.has_singleton("DamageManager"):
                var damage_manager = Engine.get_singleton("DamageManager")
                damage_manager.apply_damage_to_object(n, dmg, "missile")
            else:
                # Fallback to original damage application
                n.apply_damage(dmg)
            return
        n = n.get_parent()

func _explode() -> void:
    if get_tree() == null:
        queue_free()
        return

    var explosion_pos = global_position

    var e := ExplosionScript.new()
    get_tree().current_scene.add_child(e)
    e.global_position = explosion_pos
    e.radius = hit_radius
    e.intensity = 1.55

    # Add missile explosion effects (check settings for debugging)
    if Game.settings.get("enable_missile_effects", true):
        _create_missile_explosion_effects(explosion_pos)

    # A little kick if the player's missile explodes near camera.
    if source and source is Node and (source as Node).is_in_group("player"):
        Game.add_camera_shake(0.28)

    queue_free()

func _setup_visual() -> void:
    var v = get_node_or_null("Visual")
    if v and v is MeshInstance3D:
        var mi := v as MeshInstance3D
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.emission_enabled = true
        mat.emission = Color(1.0, 0.25, 0.75, 1.0)
        mat.emission_energy_multiplier = 2.25
        mat.albedo_color = Color(0.25, 0.05, 0.18, 1.0)
        mi.material_override = mat

    _light = OmniLight3D.new()
    _light.light_color = Color(1.0, 0.25, 0.75, 1.0)
    _light.light_energy = 2.4
    _light.omni_range = 18.0
    add_child(_light)

func _setup_trail() -> void:
    _trail = GPUParticles3D.new()
    _trail.one_shot = false
    _trail.amount = 120
    _trail.lifetime = 0.55
    _trail.explosiveness = 0.0
    _trail.randomness = 0.65
    _trail.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))

    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 0, 1) # “backwards” in local space (-Z forward)
    mat.spread = 25.0
    mat.initial_velocity_min = 4.0
    mat.initial_velocity_max = 10.0
    mat.gravity = Vector3(0, -2.0, 0)
    mat.scale_min = 0.12
    mat.scale_max = 0.30
    mat.damping_min = 1.0
    mat.damping_max = 2.0
    mat.color = Color(1.0, 0.35, 0.8, 0.75)
    mat.color_ramp = _make_ramp()

    _trail.process_material = mat
    add_child(_trail)
    _trail.emitting = true

func _make_ramp() -> GradientTexture1D:
    var g := Gradient.new()
    g.add_point(0.0, Color(1.0, 0.55, 0.95, 0.65))
    g.add_point(0.5, Color(1.0, 0.25, 0.75, 0.30))
    g.add_point(1.0, Color(0.2, 0.0, 0.35, 0.0))
    var t := GradientTexture1D.new()
    t.gradient = g
    return t

## Create missile explosion effects
func _create_missile_explosion_effects(pos: Vector3) -> void:
    var root = get_tree().root
    if not root:
        return

    # Spawn smoke particle effect
    var smoke_scene = load("res://effects/particle_smoke.tscn")
    if smoke_scene:
        var smoke = smoke_scene.instantiate()
        root.add_child(smoke)
        smoke.global_position = pos
        get_tree().create_timer(4.0).timeout.connect(
            func():
                if is_instance_valid(smoke):
                    smoke.queue_free()
        , CONNECT_ONE_SHOT)

    # Spawn debris particle effect
    var debris_scene = load("res://effects/particle_debris.tscn")
    if debris_scene:
        var debris = debris_scene.instantiate()
        root.add_child(debris)
        debris.global_position = pos
        get_tree().create_timer(4.0).timeout.connect(
            func():
                if is_instance_valid(debris):
                    debris.queue_free()
        , CONNECT_ONE_SHOT)

    # Spawn sparks particle effect
    var sparks_scene = load("res://effects/particle_sparks.tscn")
    if sparks_scene:
        var sparks = sparks_scene.instantiate()
        root.add_child(sparks)
        sparks.global_position = pos
        get_tree().create_timer(4.0).timeout.connect(
            func():
                if is_instance_valid(sparks):
                    sparks.queue_free()
        , CONNECT_ONE_SHOT)

    # Play explosion sound
    var explosion_sound = load("res://sounds/explosion.wav")
    if explosion_sound:
        var audio_player = AudioStreamPlayer3D.new()
        audio_player.stream = explosion_sound
        audio_player.volume_db = 10.0
        audio_player.unit_size = 150.0
        audio_player.max_polyphony = 8  # Allow multiple simultaneous explosions
        root.add_child(audio_player)
        audio_player.global_position = pos
        audio_player.play()
        audio_player.finished.connect(func():
            if is_instance_valid(audio_player):
                audio_player.queue_free()
        , CONNECT_ONE_SHOT)
