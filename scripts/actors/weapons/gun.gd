extends Node3D

var _flash_mesh: QuadMesh = QuadMesh.new()

@export var defs: Resource
# Keep this as a plain Array for maximum compatibility across GDScript versions.
@export var muzzle_paths: Array = []
@export var owner_hitbox_path: NodePath = NodePath("Hitbox")
@export var tracer_scene: PackedScene

var _muzzles: Array = []  # Array of Node3D muzzle points (resolved from muzzle_paths)

const AutoDestructScript = preload("res://scripts/components/auto_destruct.gd")
const ExplosionScript = preload("res://scripts/fx/explosion.gd")

var cooldown = 0.075
var heat_per_shot = 0.055
var damage = 10.0
var range = 1600.0
var spread_deg = 0.35
var tracer_life = 0.065

var _t = 0.0
var heat = 0.0 # 0..1

func _ready() -> void:
    if muzzle_paths.is_empty():
        # These paths are resolved relative to our parent (Plane), see fire().
        muzzle_paths = [NodePath("Muzzles/Left"), NodePath("Muzzles/Right")]
    if defs:
        _apply(defs.gun)
    # Muzzle flash quad (initialized here to avoid top-level statements).
    if _flash_mesh == null:
        _flash_mesh = QuadMesh.new()
    _flash_mesh.size = Vector2(0.9, 0.45)

func _process(dt: float) -> void:
    _t = max(_t - dt, 0.0)
    heat = max(heat - dt * 0.25, 0.0)

func can_fire() -> bool:
    return _t <= 0.0 and heat < 0.98

func fire(aim_dir: Vector3) -> void:
    if not can_fire():
        return

    _t = cooldown
    heat = min(heat + heat_per_shot, 1.0)

    # Decide if this is the player's gun (duck-typed + safe).
    var is_player := false
    var p := get_parent()
    if p and p is Node and (p as Node).is_in_group("player"):
        is_player = true

    # Enhanced camera shake so shooting feels more impactful.
    if is_player:
        Game.add_camera_shake(0.35)  # Increased from 0.18 to 0.35 for more noticeable effect

    # Get a convergence / aim point if the owner provides it.
    var aim_point: Vector3 = Vector3.ZERO

    # Check if target lock is enabled in settings
    var target_lock_enabled: bool = true
    if Game.settings.has("enable_target_lock"):
        target_lock_enabled = bool(Game.settings.get("enable_target_lock", true))

    if p != null and (p as Node).has_method("gun_aim_point") and target_lock_enabled:
        var ap = (p as Node).call("gun_aim_point", range)
        if typeof(ap) == TYPE_VECTOR3:
            # Check if the target is reasonably close to the player to avoid aiming at distant objects
            var distance_to_target = (ap - global_position).length()
            var max_target_distance = range * 0.8  # Only aim at targets within 80% of our range

            # Target lock enabled - use calculated aim point
            if distance_to_target <= max_target_distance:
                aim_point = ap
            else:
                # Target is too far, aim straight ahead instead
                # Calculate forward direction from the parent plane
                if p.has_method("get_forward"):
                    var forward_dir = (p as Node).call("get_forward")
                    aim_point = global_position + forward_dir * range
                else:
                    aim_point = global_position + aim_dir * range
        else:
            # Calculate forward direction from the parent plane
            if p.has_method("get_forward"):
                var forward_dir = (p as Node).call("get_forward")
                aim_point = global_position + forward_dir * range
            else:
                aim_point = global_position + aim_dir * range
    else:
        # Either no gun_aim_point method or target lock is disabled, aim straight ahead
        # Calculate forward direction from the parent plane
        if p and p.has_method("get_forward"):
            var forward_dir = (p as Node).call("get_forward")
            aim_point = global_position + forward_dir * range
            if randf() < 0.05:  # Print every ~5% of shots when in free-fire mode
                print("DEBUG: Free-fire mode. Forward dir: ", forward_dir, " Aim point: ", aim_point)
        else:
            aim_point = global_position + aim_dir * range

    # Aim point calculated - ready to fire

    # Raycast from each muzzle toward the convergence point.
    var space = get_world_3d().direct_space_state
    var exclude_rids: Array[RID] = []
    var hb = _resolve_owner_hitbox()
    if hb:
        exclude_rids.append(hb.get_rid())

    # Resolve muzzle nodes from configured paths (relative to the owning plane).
    _muzzles.clear()
    if p and p is Node:
        for mp in muzzle_paths:
            var mn: Node3D = (p as Node).get_node_or_null(mp) as Node3D
            if mn != null:
                _muzzles.append(mn)
    if _muzzles.is_empty():
        # Fall back to firing from this node if muzzle points are missing.
        _muzzles.append(self)

    # Processing muzzles for firing

    for m in _muzzles:
        var origin: Vector3 = (m as Node3D).global_position
        var dir: Vector3 = (aim_point - origin).normalized()
        dir = _apply_spread(dir, deg_to_rad(spread_deg))

        var to = origin + dir * range
        var query = PhysicsRayQueryParameters3D.create(origin, to)
        query.exclude = exclude_rids
        # Explicitly set collision mask to hit all layers - default is 0 which hits nothing
        query.collision_mask = 4294967295  # All 32 layers enabled
        query.collide_with_areas = true
        query.collide_with_bodies = true

        var hit = space.intersect_ray(query)

        var hit_pos = to
        var did_hit := false
        if hit and hit.size() > 0:  # Check if hit dictionary has any content
            if hit.has("position"):
                hit_pos = hit.position
                did_hit = true
                var collider = hit.collider
                print("COLLISION DEBUG: Raycast hit detected at: ", hit_pos, " collider: ", collider.name if collider else "null")
                _apply_damage_to_collider(collider, damage)
            else:
                print("COLLISION DEBUG: Raycast hit but no position - using endpoint: ", to)
        else:
            print("COLLISION DEBUG: Raycast hit nothing, using endpoint: ", to)

        _spawn_tracer(origin, hit_pos, is_player)
        _spawn_muzzle_flash((m as Node3D), dir, 0.8)

        if did_hit:
            _spawn_impact_spark(hit_pos)
            if is_player:
                GameEvents.hit_confirmed.emit(1.0)

func _resolve_owner_hitbox() -> CollisionObject3D:
    # Look for owner hitbox relative to our parent (Plane).
    var p = get_parent()
    if p and p is Node:
        var hb = p.get_node_or_null(owner_hitbox_path)
        if hb and hb is CollisionObject3D:
            return hb
    return null

func _apply_damage_to_collider(obj: Object, dmg: float) -> void:
    if obj == null:
        return

    print("COLLISION DEBUG: Attempting to apply damage to: ", obj.name if obj and obj.has_method("name") else "null", " class: ", obj.get_class() if obj else "null")

    # Intersections commonly hit an Area3D hitbox; walk up to find a parent with apply_damage().
    var n := obj as Node
    while n:
        if n.has_method("apply_damage"):
            # Prefer DamageManager if present and compatible, otherwise call apply_damage directly.
            if Engine.has_singleton("DamageManager"):
                var dm := Engine.get_singleton("DamageManager")
                if dm and dm.has_method("apply_damage_to_object"):
                    print("COLLISION DEBUG: Found apply_damage on: ", n.name, " - applying damage via DamageManager")
                    dm.call("apply_damage_to_object", n, dmg, "bullet")
                    return
            print("COLLISION DEBUG: Applied damage directly to: ", n.name)
            n.call("apply_damage", dmg)
            return
        n = n.get_parent()

    print("COLLISION DEBUG: No apply_damage method found in parent chain")
    print("DEBUG: No node with apply_damage method found in parent chain")

func _spawn_tracer(a: Vector3, b: Vector3, is_player: bool) -> void:
    if tracer_scene:
        var t = tracer_scene.instantiate()
        var root = get_tree().root
        if root:
            root.add_child(t)
            t.add_to_group("tracers")
            if t.has_method("setup"):
                t.setup(a, b, tracer_life)
            if t.has_method("set_color"):
                var c: Color = Color(1.0, 0.78, 0.25, 1.0) if is_player else Color(1.0, 0.42, 0.12, 1.0)
                t.set_color(c)

func _spawn_muzzle_flash(muzzle_node: Variant, dir: Vector3 = Vector3.ZERO, scale_mul: float = 1.0) -> void:
    # Accept either a muzzle Node3D or a world-space Vector3 position.
    if not is_inside_tree():
        return
    var root := get_tree().root
    if root == null:
        return

    # Create a more dynamic muzzle flash using particles for better arcade feel
    var flash_particles := GPUParticles3D.new()
    flash_particles.name = "MuzzleFlash"
    flash_particles.add_to_group("muzzle_flashes")
    root.add_child(flash_particles)

    # Configure particle system
    flash_particles.emitting = true
    flash_particles.amount = 150  # Much more particles for better visibility
    flash_particles.lifetime = 0.8  # Much longer lifetime for better visibility
    flash_particles.one_shot = true
    flash_particles.speed_scale = 8.0  # Much faster particles
    flash_particles.explosiveness = 0.8  # More spread
    flash_particles.randomness = 0.95  # More randomness

    # Particle material
    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 0, 1)  # Forward direction
    mat.initial_velocity_min = 800.0  # Much faster particles
    mat.initial_velocity_max = 1500.0  # Much faster particles
    mat.angular_velocity_min = -3000.0
    mat.angular_velocity_max = 3000.0
    mat.scale_min = 2.0  # Much larger particles
    mat.scale_max = 5.0  # Much larger particles
    mat.flatness = 0.8  # Make particles more billboard-like

    # Color ramp for fiery effect
    var color_ramp := Gradient.new()
    color_ramp.add_point(0.0, Color(1.0, 1.0, 0.9, 1.0))  # Bright yellow-white
    color_ramp.add_point(0.2, Color(1.0, 0.9, 0.5, 0.95))  # Yellow-orange
    color_ramp.add_point(0.5, Color(1.0, 0.6, 0.2, 0.9))  # Orange-red
    color_ramp.add_point(0.8, Color(1.0, 0.3, 0.1, 0.7))  # Red-orange
    color_ramp.add_point(1.0, Color(0.9, 0.15, 0.1, 0.0))  # Fade to transparent red

    var color_ramp_tex := GradientTexture1D.new()
    color_ramp_tex.gradient = color_ramp
    mat.color_ramp = color_ramp_tex

    # Make particles more emissive/bright
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
    mat.emission_point_count = 1

    # Ensure particles are bright and visible
#    mat.emission_enabled = true
#    mat.emission_intensity = 10.0  # Very bright muzzle flash

    flash_particles.process_material = mat

    # Position and orient the particle system
    if muzzle_node is Node3D:
        var n: Node3D = muzzle_node
        if not is_instance_valid(n) or not n.is_inside_tree():
            flash_particles.queue_free()
            return
        flash_particles.global_transform = n.global_transform
    elif muzzle_node is Vector3:
        flash_particles.global_position = muzzle_node
        # Orient along dir if provided
        if dir.length() > 0.001:
            var fwd := dir.normalized()
            var up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
            var right := up.cross(fwd).normalized()
            up = fwd.cross(right).normalized()
            flash_particles.global_basis = Basis(right, up, fwd)
    else:
        flash_particles.queue_free()
        return

    # Scale the flash
    flash_particles.scale = Vector3.ONE * (scale_mul * 12.0)  # Much larger scale for more impact

    # Auto-cleanup after lifetime
    var t := get_tree().create_timer(flash_particles.lifetime * 2.0)
    t.timeout.connect(func():
        if is_instance_valid(flash_particles):
            flash_particles.queue_free()
    )

func _spawn_impact_spark(pos: Vector3) -> void:
    # Big, impressive "spark pop" at impact. Uses the existing explosion effect at high intensity.
    var e := ExplosionScript.new()
    var root = get_tree().root
    if root:
        e.add_to_group("impact_sparks")
        root.add_child(e)
        e.global_position = pos
        e.radius = 25.0  # Much larger radius for better visibility
        e.intensity = 5.0  # Much more intense for better impact
        e.life = 2.0  # Longer duration for better visibility

func _apply_spread(dir: Vector3, spread_rad: float) -> Vector3:
    if spread_rad <= 0.0:
        return dir
    # Random small rotation around a random axis.
    var axis = dir.cross(Vector3.UP)
    if axis.length() < 0.001:
        axis = dir.cross(Vector3.RIGHT)
    axis = axis.normalized()
    var a = randf_range(-spread_rad, spread_rad)
    return dir.rotated(axis, a).normalized()

func _apply(d: Dictionary) -> void:
    damage = d.get("damage", damage)
    range = d.get("range", range)
    cooldown = d.get("cooldown", cooldown)
    heat_per_shot = d.get("heat_per_shot", heat_per_shot)
    spread_deg = d.get("spread_deg", spread_deg)
    tracer_life = d.get("tracer_life", tracer_life)