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

    # Tiny camera kick so shooting feels physical.
    if is_player:
        Game.add_camera_shake(0.18)

    # Get a convergence / aim point if the owner provides it.
    var aim_point: Vector3 = Vector3.ZERO
    if p != null and (p as Node).has_method("gun_aim_point"):
        var ap = (p as Node).call("gun_aim_point", range)
        if typeof(ap) == TYPE_VECTOR3:
            aim_point = ap
        else:
            aim_point = global_position + aim_dir * range
    else:
        aim_point = global_position + aim_dir * range

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

    for m in _muzzles:
        var origin: Vector3 = (m as Node3D).global_position
        var dir: Vector3 = (aim_point - origin).normalized()
        dir = _apply_spread(dir, deg_to_rad(spread_deg))

        var to = origin + dir * range
        var query = PhysicsRayQueryParameters3D.create(origin, to)
        query.exclude = exclude_rids
        query.collide_with_areas = true
        query.collide_with_bodies = true
        var hit = space.intersect_ray(query)

        var hit_pos = to
        var did_hit := false
        if hit and hit.has("position"):
            hit_pos = hit["position"]
            did_hit = true
            var collider = hit.get("collider")
            _apply_damage_to_collider(collider, damage)

        _spawn_tracer(origin, hit_pos, is_player)
        _spawn_muzzle_flash(origin, dir, is_player)

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
    # Intersections commonly hit the Area3D hitbox; walk up to find Plane.apply_damage().
    var n = obj as Node
    while n:
        if n.has_method("apply_damage"):
            n.apply_damage(dmg)
            return
        n = n.get_parent()

func _spawn_tracer(a: Vector3, b: Vector3, is_player: bool) -> void:
    if tracer_scene:
        var t = tracer_scene.instantiate()
        get_tree().current_scene.add_child(t)
        t.global_position = a
        if t.has_method("setup"):
            t.setup(a, b, tracer_life)
        if t.has_method("set_color"):
            var c: Color = Color(1.0, 0.78, 0.25, 1.0) if is_player else Color(1.0, 0.42, 0.12, 1.0)
            t.set_color(c)

func _spawn_muzzle_flash(origin, dir: Vector3 = Vector3.ZERO, scale_mul: float = 1.0) -> void:
    # Accept either a muzzle Node3D or a world-space Vector3 position.
    if not is_inside_tree():
        return
    var root := get_tree().current_scene
    if root == null:
        return
    var flash := MeshInstance3D.new()
    flash.mesh = _flash_mesh
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.75, 0.35)
    mat.emission_energy_multiplier = 2.0
    flash.material_override = mat
    flash.scale = Vector3.ONE * (0.8 * scale_mul)
    root.add_child(flash)

    if origin is Node3D:
        var n: Node3D = origin
        if not is_instance_valid(n) or not n.is_inside_tree():
            flash.queue_free()
            return
        flash.global_transform = n.global_transform
    elif origin is Vector3:
        flash.global_position = origin
        # Orient along dir if provided (otherwise random).
        if dir.length() > 0.001:
            # Build a basis that looks along dir.
            var fwd := dir.normalized()
            var up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
            var right := up.cross(fwd).normalized()
            up = fwd.cross(right).normalized()
            flash.global_basis = Basis(right, up, fwd)
    else:
        flash.queue_free()
        return

    # Random micro-rotation for variety
    flash.rotate_object_local(Vector3.RIGHT, deg_to_rad(randf_range(-8.0, 8.0)))
    flash.rotate_object_local(Vector3.UP, deg_to_rad(randf_range(-8.0, 8.0)))
    flash.rotate_object_local(Vector3.FORWARD, deg_to_rad(randf_range(-180.0, 180.0)))

    var t := get_tree().create_timer(0.045)
    t.timeout.connect(func():
        if is_instance_valid(flash):
            flash.queue_free()
    )
func _spawn_impact_spark(pos: Vector3) -> void:
    # Small “spark pop” at impact. Uses the existing explosion effect at low intensity.
    var e := ExplosionScript.new()
    get_tree().current_scene.add_child(e)
    e.global_position = pos
    e.radius = 1.8
    e.intensity = 0.25
    e.life = 0.55

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
