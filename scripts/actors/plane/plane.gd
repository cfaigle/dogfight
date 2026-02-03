extends RigidBody3D
# NOTE: No class_name here (autoload + class cache friendliness).

const Smooth              = preload("res://scripts/util/smooth.gd")
const ProcMesh            = preload("res://scripts/util/proc_mesh.gd")
const HealthScript        = preload("res://scripts/components/health.gd")
const GunScript           = preload("res://scripts/actors/weapons/gun.gd")
const ExplosionScript     = preload("res://scripts/fx/explosion.gd")
const ENGINE_SOUND        = preload("res://sounds/airplane_prop.wav")

@export var plane_defs: Resource
@export var weapon_defs: Resource
@export var is_player := false

# --- Runtime controls (set by player_plane.gd / enemy_plane.gd) ----------------
var throttle: float = 0.6
var afterburner: bool = false
var in_pitch: float = 0.0  # -1..1 (pull back = +pitch up, implemented in child)
var in_roll: float  = 0.0
var in_yaw: float   = 0.0

var gun_trigger: bool = false
var missile_trigger: bool = false

# Debug/telemetry (HUD pulls these for on-screen control feedback)
var dbg_alpha: float = 0.0
var dbg_beta: float = 0.0
var dbg_q: float = 0.0
var dbg_cl: float = 0.0
var dbg_cd: float = 0.0
var dbg_lift: float = 0.0
var dbg_drag: float = 0.0
var dbg_thrust: float = 0.0


# --- Flight tuning ------------------------------------------------------------
# Units are "Godot-ish meters". This is a "light sim": forces/torques are aero-inspired,
# not a full CFD, but it preserves key concepts (alpha/beta, lift/drag, stability).
var mass_kg: float = 1200.0
var wing_area: float = 18.0     # m^2-ish
var wing_span: float = 11.0     # m-ish (for roll/yaw moments)
var chord: float = 1.7          # m-ish

# Lift/drag model
var cl0: float = 0.18
var cl_alpha: float = 4.6       # per rad
var cl_max: float = 1.35
var cd0: float = 0.030
var cd_alpha2: float = 0.70     # induced drag factor (alpha^2)
var side_beta: float = 2.2      # lateral force per rad

# Stability (aerodynamic moments)
var cm_alpha: float = 1.2       # pitch stability per rad (positive => pitches down with +alpha)
var cn_beta: float  = 1.0       # yaw stability per rad
var cl_beta: float  = 0.25      # roll from sideslip (dihedral-ish)

# Control effectiveness (moments)
var cm_ctrl: float = 1.8
var cn_ctrl: float = 0.9
var cl_ctrl: float = 2.2

# Damping (angular)
var ang_damp: Vector3 = Vector3(2.6, 1.8, 2.2)  # (pitch,yaw,roll) base
var ang_damp_q: float = 0.00250                   # scales with q

@export var bank_max_deg: float = 60.0
@export var pitch_max_deg: float = 25.0
@export var roll_rate_max_deg: float = 140.0
@export var pitch_rate_max_deg: float = 90.0
@export var yaw_rate_max_deg: float = 70.0
@export var bank_p: float = 2.6  # rad/s per rad bank error
@export var pitch_p: float = 2.2 # rad/s per rad pitch error
@export var beta_p: float = 1.4  # rad/s per rad sideslip error
@export var torque_pitch_gain: float = 52000.0
@export var torque_yaw_gain: float = 38000.0
@export var torque_roll_gain: float = 68000.0
@export var torque_pitch_max: float = 80000.0
@export var torque_yaw_max: float = 70000.0
@export var torque_roll_max: float = 90000.0
@export var align_rate: float = 1.8  # 1/s lateral velocity alignment
@export var align_max_accel: float = 22.0


# Engine
var max_thrust: float = 18000.0
var ab_thrust_mul: float = 1.35

# Soft limits
var min_airspeed: float = 22.0     # stall-ish
var max_airspeed: float = 180.0

# FX / components
var _health: Node
var _gun: Node3D
var _missile_launcher: Node
var _target: Node3D = null
var _engine_mat: StandardMaterial3D = null
var _engine_light: OmniLight3D = null
var _visual_root: Node3D = null
var _prop_node: Node3D = null
var _engine_mesh: MeshInstance3D = null
var _engine_audio: AudioStreamPlayer3D = null
var _dbg_t: float = 0.0

func _ready() -> void:
    # Ensure rigidbody is correctly configured.
    freeze = false
    can_sleep = false
    gravity_scale = 1.0
    mass = mass_kg
    linear_damp = 0.02
    angular_damp = 0.05

    # If the scene doesn't provide a collider, add a simple one.
    if get_node_or_null("CollisionShape3D") == null:
        var cs := CollisionShape3D.new()
        cs.name = "CollisionShape3D"
        var cap := CapsuleShape3D.new()
        cap.radius = 1.2
        cap.height = 5.0
        cs.shape = cap
        # Rotate capsule so its axis roughly matches fuselage (Y axis is capsule axis).
        cs.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
        add_child(cs)

    # Health component
    _health = HealthScript.new()
    add_child(_health)
    _health.max_hp = 100.0
    _health.hp = 100.0
    _health.changed.connect(_on_hp_changed)
    _health.died.connect(_on_died)

    # Gun component (WW2 guns)
    _gun = GunScript.new()
    _gun.name = "Gun"
    _gun.tracer_scene = preload("res://scenes/fx/tracer.tscn")
    add_child(_gun)
    if weapon_defs != null and _gun.has_method("apply_defs"):
        _gun.apply_defs(weapon_defs, "gun")
    
    # Add basic muzzle nodes for gun system
    var muzzles = Node3D.new()
    muzzles.name = "Muzzles"
    add_child(muzzles)
    
    var muzzle_left = Node3D.new()
    muzzle_left.name = "Left"
    muzzle_left.position = Vector3(-2.5, 0.5, 3.0)
    muzzles.add_child(muzzle_left)
    
    var muzzle_right = Node3D.new()
    muzzle_right.name = "Right"
    muzzle_right.position = Vector3(2.5, 0.5, 3.0)
    muzzles.add_child(muzzle_right)
    
    # CRITICAL: Set muzzle paths for gun to find these nodes
    _gun.muzzle_paths = [NodePath("Muzzles/Left"), NodePath("Muzzles/Right")]
    
    # Add missile launcher
    _missile_launcher = preload("res://scripts/actors/weapons/missile_launcher.gd").new()
    _missile_launcher.name = "MissileLauncher"
    add_child(_missile_launcher)
    if weapon_defs != null and _missile_launcher.has_method("apply_defs"):
        _missile_launcher.apply_defs(weapon_defs, "missile")
        _missile_launcher.missile_scene = preload("res://scenes/actors/missile.tscn")
    
    # Find engine visual for glow.
    _engine_mat = _find_engine_material()
    _engine_light = _find_engine_light()

    # Setup engine sound
    _engine_audio = AudioStreamPlayer3D.new()
    _engine_audio.stream = ENGINE_SOUND
    _engine_audio.autoplay = false
    _engine_audio.max_distance = 1000.0  # Audible from far away
    _engine_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    _engine_audio.volume_db = -20.0  # Start quieter
    _engine_audio.max_polyphony = 8  # Allow multiple planes to have engine sounds
    add_child(_engine_audio)
    _engine_audio.play()

    # Apply plane definitions if available
    if plane_defs != null:
        _apply_plane_definitions()

    # Give an initial push if we are spawned stationary.
    if linear_velocity.length() < 1.0:
        linear_velocity = get_forward() * 95.0
        _ensure_visual_setup()


func _apply_plane_definitions() -> void:
    if plane_defs == null:
        return

    # Determine which plane config to use (player vs enemy)
    var config_dict: Dictionary
    if is_player:
        config_dict = plane_defs.player
    else:
        config_dict = plane_defs.enemy

    # Apply the plane properties from the definitions
    if config_dict.has("thrust"):
        # Scale the thrust value appropriately (definitions appear to be in simplified units)
        max_thrust = float(config_dict.thrust) * 1000.0  # Scale factor to match original hardcoded values

    if config_dict.has("afterburner_thrust"):
        # The afterburner_thrust in the definitions should represent the total thrust when afterburners are active
        # If the afterburner_thrust value is less than base thrust, it means the values might be reversed
        # In that case, we'll interpret it as: afterburner_thrust = base_thrust + additional_afterburner_thrust
        var base_thrust_unscaled = float(config_dict.thrust) if config_dict.has("thrust") else (max_thrust / 1000.0)
        var afterburner_total_thrust = float(config_dict.afterburner_thrust)

        # If afterburner value is less than base thrust, assume it's the additional thrust
        if afterburner_total_thrust < base_thrust_unscaled:
            # Interpret as additional thrust
            ab_thrust_mul = (base_thrust_unscaled + afterburner_total_thrust) / base_thrust_unscaled
        else:
            # Interpret as total thrust with afterburners
            ab_thrust_mul = afterburner_total_thrust / base_thrust_unscaled
    else:
        # If no afterburner thrust is defined, use a default multiplier
        ab_thrust_mul = 1.35

func set_target(t: Node) -> void:
    _target = t as Node3D

func get_forward() -> Vector3:
    # Godot's forward is -Z.
    return -global_transform.basis.z.normalized()

func get_up() -> Vector3:
    return global_transform.basis.y.normalized()

func get_right() -> Vector3:
    return global_transform.basis.x.normalized()

func apply_damage(amount: float) -> void:
    if _health and is_instance_valid(_health):
        # Apply damage using the new damage system if available
        if Engine.has_singleton("DamageManager"):
            var damage_manager = Engine.get_singleton("DamageManager")
            damage_manager.apply_damage_to_object(self, amount, "collision")
        else:
            # Fallback to original damage application
            _health.apply_damage(amount)

# Implement DamageableObject interface methods
func get_health() -> float:
    if _health and is_instance_valid(_health):
        return _health.hp
    return 0.0

func get_max_health() -> float:
    if _health and is_instance_valid(_health):
        return _health.max_hp
    return 0.0

func is_destroyed() -> bool:
    if _health and is_instance_valid(_health):
        return _health.hp <= 0
    return true

func get_destruction_stage() -> int:
    if _health and is_instance_valid(_health):
        var health_ratio = _health.hp / _health.max_hp
        if health_ratio <= 0.0:
            return 3  # destroyed
        elif health_ratio <= 0.25:
            return 2  # ruined
        elif health_ratio <= 0.5:
            return 1  # damaged
        else:
            return 0  # intact
    return 0

func set_health(new_health: float) -> void:
    if _health and is_instance_valid(_health):
        _health.hp = clamp(new_health, 0.0, _health.max_hp)

func get_object_set() -> String:
    # Planes belong to either "Player" or "Enemy" set
    return "Player" if is_player else "Enemy"

func set_object_set(set_name: String) -> void:
    # For planes, we don't allow changing the set after creation
    print("Warning: Cannot change object set for planes")

func _explode_and_die() -> void:
    var ex := ExplosionScript.new()
    get_tree().current_scene.add_child(ex)
    if ex.has_method("boom"):
        ex.boom(global_position, 1.0)
    queue_free()
    if is_player:
        GameEvents.player_destroyed.emit()
    else:
        GameEvents.enemy_destroyed.emit(self)

func _physics_process(dt: float) -> void:
    # Weapons are game-logic; forces/torques are in _integrate_forces().
    _weapons_step(dt)
    _update_engine_fx(dt)
    _update_engine_sound(dt)
    _update_visual_fx(dt)

    if bool(Game.settings.get("debug_flight", false)) and is_player:
        _dbg_t += dt
        if _dbg_t >= 10.0:
            _dbg_t = 0.0
            var sp = linear_velocity.length()
            print("[FLIGHT JOLT] pos", global_position, " vel", linear_velocity, " spd", sp)

func _signed_angle(a: Vector3, b: Vector3, axis: Vector3) -> float:
    # Signed angle from vector a to b around axis (right-hand rule).
    # Uses atan2 for numerical stability.
    var ax: Vector3 = axis.normalized()
    var cross_ab: Vector3 = a.cross(b)
    return atan2(ax.dot(cross_ab), a.dot(b))

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var b: Basis = state.transform.basis
    var v: Vector3 = state.linear_velocity
    var sp: float = v.length()
    if sp < 0.05:
        # Avoid NaNs.
        v = (-b.z) * 0.1
        sp = 0.1

    # World -> body (local) velocity: use transposed basis for orthonormal transform.
    var v_body: Vector3 = b.transposed() * v

    # In Godot local forward is -Z. Airflow comes from -velocity.
    var fwd_speed: float = max(1.0, -v_body.z)
    var alpha: float = atan2(-v_body.y, fwd_speed)   # +alpha => nose-up relative wind
    var beta: float  = atan2(v_body.x, fwd_speed)    # +beta => wind from right
    # Clamp angles to keep stall/spin math from exploding at very low speed or extreme attitudes.
    alpha = clampf(alpha, deg_to_rad(-35.0), deg_to_rad(35.0))
    beta  = clampf(beta,  deg_to_rad(-25.0), deg_to_rad(25.0))

    # Dynamic pressure (scaled): rho=1.
    var q: float = 0.5 * sp * sp
    var q_ctrl: float = q / (1.0 + q * 0.0012)
    var q_stab: float = q / (1.0 + q * 0.0006)

    # Lift coefficient with simple stall clamp.
    var cl: float = cl0 + cl_alpha * alpha
    var stalled := false
    if absf(cl) > cl_max:
        stalled = true
        cl = signf(cl) * cl_max

    # Drag coefficient grows with alpha^2 and more when stalled.
    var cd: float = cd0 + cd_alpha2 * (alpha * alpha)
    if stalled:
        cd += 0.22 + 0.55 * clampf((absf(alpha) - 0.35) * 2.0, 0.0, 1.0)

    # Side force (damps crab / ties velocity to heading).
    var cy: float = -side_beta * beta

    # Aero forces in BODY axes:
    # +Y is up, +Z is back. Drag acts +Z, thrust acts -Z.
    var lift_n: float = q * wing_area * cl
    var drag_n: float = q * wing_area * cd
    dbg_alpha = alpha
    dbg_beta = beta
    dbg_q = q
    dbg_cl = cl
    dbg_cd = cd
    dbg_lift = lift_n
    dbg_drag = drag_n
    var side_n: float = q * wing_area * cy

    # Lift direction should be perpendicular to relative wind, within the plane's YZ plane.
    # We'll approximate with (up projected perpendicular to v).
    var v_dir: Vector3 = v.normalized()
    var up_b: Vector3 = b.y
    var lift_dir_w: Vector3 = (up_b - v_dir * up_b.dot(v_dir))
    if lift_dir_w.length() < 0.001:
        lift_dir_w = up_b
    lift_dir_w = lift_dir_w.normalized()

    # Drag direction: opposite motion.
    var drag_dir_w: Vector3 = -v_dir

    # Side direction: right projected perpendicular to v (to damp sideslip).
    var right_w: Vector3 = b.x
    var side_dir_w: Vector3 = (right_w - v_dir * right_w.dot(v_dir))
    if side_dir_w.length() < 0.001:
        side_dir_w = right_w
    side_dir_w = side_dir_w.normalized()

    var F_w: Vector3 = lift_dir_w * lift_n + drag_dir_w * drag_n + side_dir_w * side_n
    var F_align_w: Vector3 = Vector3.ZERO
    if align_rate > 0.0 and sp > 5.0:
        # Pull lateral velocity toward the forward axis so it steers cleanly (arcade-ish but stable).
        var fwd_align: Vector3 = (-b.z).normalized()
        var v_fwd: Vector3 = fwd_align * v.dot(fwd_align)
        var v_lat: Vector3 = v - v_fwd
        var accel_lat: Vector3 = -v_lat * align_rate
        var a_len: float = accel_lat.length()
        if a_len > align_max_accel and a_len > 0.0001:
            accel_lat = accel_lat / a_len * align_max_accel
        F_align_w = accel_lat * mass_kg
    F_w += F_align_w


    # Engine thrust along forward
    var t: float = clampf(throttle, 0.0, 1.0)
    var thrust: float = max_thrust * t
    dbg_thrust = thrust
    if afterburner:
        # print("DEBUG: Afterburner active - base thrust: ", thrust, " multiplier: ", ab_thrust_mul)
        thrust *= ab_thrust_mul
    F_w += (-b.z) * thrust

    # Gentle speed cap (prevents runaway) - reduce drag when afterburner is active
    var speed_limit = max_airspeed
    if afterburner:
        speed_limit = max_airspeed * 1.3  # Allow 30% higher speed with afterburner
    
    if sp > speed_limit:
        var excess = sp - speed_limit
        F_w += drag_dir_w * (excess * 220.0)

    # Prevent "brick fall" at ultra-low speed: small forward nudge.
    if sp < min_airspeed:
        F_w += (-b.z) * (min_airspeed - sp) * 220.0

    # Apply force at COM.
    state.apply_central_force(F_w)

    # --- Aerodynamic moments --------------------------------------------------
    var omega_w: Vector3 = state.angular_velocity
    var omega_body: Vector3 = b.transposed() * omega_w

    # Stability moments.
    var pitch_stab = -cm_alpha * alpha
    var yaw_stab   = -cn_beta  * beta
    var roll_stab  = -cl_beta  * beta

    # Control moments (inputs already clamped in [-1,1])
    var pitch_ctrl = cm_ctrl * in_pitch
    var yaw_ctrl   = cn_ctrl * in_yaw
    var roll_ctrl  = cl_ctrl * in_roll

    # Convert to moments; scale with dynamic pressure and geometry.
    var My = 0.0 # yaw about Y

    # Controller-driven body torques (stable, trackpad-friendly).
    # Inputs in_pitch/in_roll are interpreted as *attitude commands* (desired pitch/bank),
    # while in_yaw is a yaw-rate command.
    var up_world: Vector3 = Vector3.UP
    var fwd_w: Vector3 = (-b.z).normalized()
    var up_w: Vector3 = b.y.normalized()

    # Bank (roll) angle relative to the horizon around the forward axis.
    var right_h: Vector3 = fwd_w.cross(up_world)
    if right_h.length() < 0.0001:
        right_h = b.x.normalized()
    else:
        right_h = right_h.normalized()
    var up_ref: Vector3 = right_h.cross(fwd_w).normalized()
    var bank: float = _signed_angle(up_ref, up_w, fwd_w)

    # Pitch angle relative to horizon (nose up positive).
    var pitch: float = asin(clampf(fwd_w.dot(up_world), -1.0, 1.0))

    # Targets (radians).
    var bank_t: float = deg_to_rad(bank_max_deg) * in_roll
    var pitch_t: float = deg_to_rad(pitch_max_deg) * in_pitch

    # Rate commands (radians/sec).
    var roll_rate_cmd: float = clampf((bank_t - bank) * bank_p, -deg_to_rad(roll_rate_max_deg), deg_to_rad(roll_rate_max_deg))
    var pitch_rate_cmd: float = clampf((pitch_t - pitch) * pitch_p, -deg_to_rad(pitch_rate_max_deg), deg_to_rad(pitch_rate_max_deg))
    var yaw_rate_cmd: float = deg_to_rad(yaw_rate_max_deg) * in_yaw - beta * beta_p

    # Current angular velocity in body axes.
    var omega_b: Vector3 = omega_body  # reuse from aero moment section above
    var omega_pitch: float = omega_b.x
    var omega_yaw: float = omega_b.y
    var omega_roll: float = -omega_b.z  # roll about forward (-Z) axis

    # PD-like torque on rates (simple, robust).
    var t_pitch: float = (pitch_rate_cmd - omega_pitch) * torque_pitch_gain
    var t_yaw: float = (yaw_rate_cmd - omega_yaw) * torque_yaw_gain
    var t_roll: float = (roll_rate_cmd - omega_roll) * torque_roll_gain

    t_pitch = clampf(t_pitch, -torque_pitch_max, torque_pitch_max)
    t_yaw = clampf(t_yaw, -torque_yaw_max, torque_yaw_max)
    t_roll = clampf(t_roll, -torque_roll_max, torque_roll_max)

    # Body torque vector: X=pitch (right), Y=yaw (up), -Z=roll (forward).
    var torque_b: Vector3 = Vector3(t_pitch, t_yaw, -t_roll)
    var M_w: Vector3 = b * torque_b
    state.apply_torque(M_w)


func _weapons_step(dt: float) -> void:
    if _gun == null:
        return
    

    if gun_trigger:
        # Aim a bit ahead along forward. If we have a target, aim at it.
        var aim: Vector3
        if _target and is_instance_valid(_target):
            aim = _target.global_position
        else:
            aim = global_position + get_forward() * 1200.0
        if _gun and _gun.has_method("fire"):
            _gun.fire(aim)

    
    # Handle missile firing

    if missile_trigger and _missile_launcher and _missile_launcher.has_method("fire"):
        var target = _target if _target and is_instance_valid(_target) else null
        var locked = target != null  # Simple lock detection

        _missile_launcher.fire(target, locked)

func _find_engine_material() -> StandardMaterial3D:
    # Look for a mesh we can apply a simple emissive material to (engine glow).
    # Supports both layouts:
    #   - Visual/Engine as MeshInstance3D (older)
    #   - Visual/Engine as Node3D with Visual/Engine/EngineMesh as MeshInstance3D (new)
    var mi: MeshInstance3D = null

    mi = get_node_or_null("Visual/Engine/EngineMesh") as MeshInstance3D
    if mi == null:
        mi = get_node_or_null("Visual/Engine") as MeshInstance3D
    if mi == null:
        mi = get_node_or_null("Engine/EngineMesh") as MeshInstance3D
    if mi == null:
        mi = get_node_or_null("Engine") as MeshInstance3D

    if mi != null:
        var mat := StandardMaterial3D.new()
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mat.emission_enabled = true
        mi.material_override = mat
        return mat

    return null

func _find_engine_light() -> OmniLight3D:
    var l := get_node_or_null("EngineLight") as OmniLight3D
    return l

func _ensure_visual_setup() -> void:
    # Create a simple WWII fighter silhouette procedurally so we don't rely on external assets.
    if has_node("Visual"):
        _visual_root = get_node("Visual") as Node3D
        _prop_node = _visual_root.get_node_or_null("Engine/Prop") as Node3D

        # New layout: Engine is a Node3D with an EngineMesh child.
        _engine_mesh = _visual_root.get_node_or_null("Engine/EngineMesh") as MeshInstance3D
        if _engine_mesh == null:
            # Back-compat: Engine itself is a MeshInstance3D.
            _engine_mesh = _visual_root.get_node_or_null("Engine") as MeshInstance3D

        return

    var visual := Node3D.new()
    visual.name = "Visual"
    add_child(visual)
    _visual_root = visual

    # --- Materials ---
    var body_mat := StandardMaterial3D.new()
    body_mat.roughness = 0.95
    body_mat.metallic = 0.02
    body_mat.albedo_color = Color(0.20, 0.28, 0.18) if is_player else Color(0.32, 0.32, 0.34)

    var trim_mat := StandardMaterial3D.new()
    trim_mat.roughness = 0.85
    trim_mat.metallic = 0.05
    trim_mat.albedo_color = Color(0.55, 0.10, 0.10) if is_player else Color(0.10, 0.10, 0.12)

    var canopy_mat := StandardMaterial3D.new()
    canopy_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    canopy_mat.roughness = 0.10
    canopy_mat.metallic = 0.05
    canopy_mat.albedo_color = Color(0.40, 0.65, 0.75, 0.35)

    # --- Fuselage (along -Z forward) ---
    var fuselage := MeshInstance3D.new()
    fuselage.name = "Fuselage"
    var fuselage_mesh := CapsuleMesh.new()
    fuselage_mesh.radius = 0.45
    fuselage_mesh.height = 3.8
    fuselage.mesh = fuselage_mesh
    fuselage.material_override = body_mat
    fuselage.rotation_degrees = Vector3(90.0, 0.0, 0.0)
    visual.add_child(fuselage)

    # --- Engine / nose ---
    var engine := Node3D.new()
    engine.name = "Engine"
    engine.position = Vector3(0.0, 0.0, -2.15)
    visual.add_child(engine)

    var engine_mesh := MeshInstance3D.new()
    engine_mesh.name = "EngineMesh"
    var nose := CylinderMesh.new()
    nose.top_radius = 0.55
    nose.bottom_radius = 0.55
    nose.height = 0.7
    engine_mesh.mesh = nose
    engine_mesh.material_override = trim_mat
    # Rotate only the mesh so Engine's child nodes (prop, etc.) keep their expected axes.
    engine_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
    engine.add_child(engine_mesh)
    _engine_mesh = engine_mesh


    # --- Wings ---
    var wing := MeshInstance3D.new()
    wing.name = "Wing"
    var wing_mesh := BoxMesh.new()
    wing_mesh.size = Vector3(5.1, 0.10, 1.25)
    wing.mesh = wing_mesh
    wing.material_override = body_mat
    wing.position = Vector3(0.0, -0.05, -0.2)
    visual.add_child(wing)

    # Slight dihedral (WW2-ish) by splitting into two halves
    wing.visible = false
    var left_wing := MeshInstance3D.new()
    left_wing.name = "WingL"
    var lw := BoxMesh.new()
    lw.size = Vector3(2.55, 0.10, 1.25)
    left_wing.mesh = lw
    left_wing.material_override = body_mat
    left_wing.position = Vector3(-1.27, -0.05, -0.2)
    left_wing.rotation_degrees = Vector3(0.0, 0.0, -5.0)
    visual.add_child(left_wing)

    var right_wing := MeshInstance3D.new()
    right_wing.name = "WingR"
    var rw := BoxMesh.new()
    rw.size = Vector3(2.55, 0.10, 1.25)
    right_wing.mesh = rw
    right_wing.material_override = body_mat
    right_wing.position = Vector3(1.27, -0.05, -0.2)
    right_wing.rotation_degrees = Vector3(0.0, 0.0, 5.0)
    visual.add_child(right_wing)

    # --- Tailplane ---
    var tail := MeshInstance3D.new()
    tail.name = "Tailplane"
    var tail_mesh := BoxMesh.new()
    tail_mesh.size = Vector3(2.1, 0.08, 0.70)
    tail.mesh = tail_mesh
    tail.material_override = body_mat
    tail.position = Vector3(0.0, 0.05, 1.75)
    visual.add_child(tail)

    # --- Vertical fin ---
    var fin := MeshInstance3D.new()
    fin.name = "Fin"
    var fin_mesh := BoxMesh.new()
    fin_mesh.size = Vector3(0.12, 0.85, 0.75)
    fin.mesh = fin_mesh
    fin.material_override = body_mat
    fin.position = Vector3(0.0, 0.45, 1.95)
    visual.add_child(fin)

    # --- Canopy ---
    var canopy := MeshInstance3D.new()
    canopy.name = "Canopy"
    var can_mesh := SphereMesh.new()
    can_mesh.radius = 0.42
    canopy.mesh = can_mesh
    canopy.material_override = canopy_mat
    canopy.position = Vector3(0.0, 0.35, -0.35)
    canopy.scale = Vector3(1.0, 0.55, 1.25)
    visual.add_child(canopy)

    # --- Propeller ---
    var prop_root := Node3D.new()
    prop_root.name = "Prop"
    engine.add_child(prop_root)
    # Keep the prop in the same *world* spot as before:
    # previously it was a child of a +90° X-rotated Engine, so a local -Z offset became +Y in world.
    # prop_root.position = Vector3(0.0, 0.45, 0.0)
    prop_root.position = Vector3(0.0, 0.0, -0.45)
    var blade_mesh := BoxMesh.new()
    blade_mesh.size = Vector3(0.10, 1.9, 0.10)

    var blade_a := MeshInstance3D.new()
    blade_a.name = "BladeA"
    blade_a.mesh = blade_mesh
    blade_a.material_override = trim_mat
    prop_root.add_child(blade_a)

    var blade_b := MeshInstance3D.new()
    blade_b.name = "BladeB"
    blade_b.mesh = blade_mesh
    blade_b.material_override = trim_mat
    blade_b.rotation_degrees = Vector3(0.0, 0.0, 90.0)
    prop_root.add_child(blade_b)

    _prop_node = prop_root

    # Cache engine FX references against our new nodes.
    _engine_mat = _find_engine_material()
    _engine_light = _find_engine_light()


func _update_visual_fx(dt: float) -> void:
    if _prop_node == null:
        return
    # Spin the prop with airspeed. This is cosmetic, but helps orientation.
    var sp: float = linear_velocity.length()
    _prop_node.rotate_z(dt * clamp(sp * 0.25, 0.0, 35.0))


func _update_engine_fx(dt: float) -> void:
    var col := Color(0.95, 0.55, 0.25)
    if afterburner:
        # More intense orange-red color for afterburner
        col = Color(1.0, 0.3, 0.1)  # Brighter orange-red

    var k: float = clampf(throttle, 0.0, 1.0)
    if afterburner:
        # Much stronger effect with afterburner
        k = 0.8 + 0.8 * k  # Boost from 0.8 to 1.6
    var e: float = lerpf(0.35, 1.25, k)

    if _engine_mat:
        _engine_mat.emission = col
        _engine_mat.emission_energy_multiplier = 1.4 * e
        _engine_mat.albedo_color = col * (0.08 + 0.05 * e)
    if _engine_light:
        _engine_light.light_color = col
        _engine_light.light_energy = 0.6 + 2.6 * e


func _update_engine_sound(dt: float) -> void:
    if not _engine_audio or not is_instance_valid(_engine_audio):
        return

    # Calculate target volume based on throttle
    # Range: -30dB (idle/quiet) to 0dB (full throttle)
    var base_volume = -30.0 + (throttle * 30.0)

    # Boost volume during afterburner
    if afterburner:
        base_volume += 8.0  # +8dB boost

    # Smooth volume changes to avoid clicking
    _engine_audio.volume_db = lerpf(_engine_audio.volume_db, base_volume, dt * 5.0)

    # Calculate pitch based on throttle and airspeed
    # Base pitch: 0.7 (idle) to 1.2 (full throttle)
    var base_pitch = 0.7 + (throttle * 0.5)

    # Additional pitch increase during afterburner
    if afterburner:
        base_pitch *= 1.3  # Higher pitched scream

    # Optional: Add slight pitch variation based on airspeed
    var speed_factor = clampf(linear_velocity.length() / 200.0, 0.0, 1.0)
    var target_pitch = base_pitch + (speed_factor * 0.2)

    # Clamp pitch to reasonable range
    target_pitch = clampf(target_pitch, 0.5, 1.8)

    # Smooth pitch changes
    _engine_audio.pitch_scale = lerpf(_engine_audio.pitch_scale, target_pitch, dt * 3.0)


func _on_hp_changed(_v: float, _max: float) -> void:
    if is_player:
        var frac := 0.0
        if _health.max_hp > 0.0:
            frac = _health.hp / _health.max_hp
        GameEvents.player_health_changed.emit(frac, _health.max_hp)

func _on_died() -> void:
    _explode_and_die()

# Method called by gun to determine aim point
func gun_aim_point(range: float) -> Vector3:
    # Offset aim point to match muzzle height (muzzles are at y=0.5)
    var muzzle_offset := global_transform.basis.y * 0.5
    var aim_origin := global_position + muzzle_offset

    # If we have a target, aim at it; otherwise aim ahead in our forward direction
    if _target and is_instance_valid(_target):
        return _target.global_position
    else:
        return aim_origin + get_forward() * range

# Method to cycle through targets (called by main script)
func _cycle_target() -> void:
    var enemies = get_tree().get_nodes_in_group("enemies")
    if is_player and enemies.size() > 0:
        # Player cycles through enemy targets
        if _target == null or not is_instance_valid(_target):
            _target = enemies[0] as Node3D
        else:
            var current_idx = -1
            for i in range(enemies.size()):
                if enemies[i] == _target:
                    current_idx = i
                    break
            var next_idx = (current_idx + 1) % enemies.size()
            _target = enemies[next_idx] as Node3D
    elif not is_player:
        # Enemy targets player
        var players = get_tree().get_nodes_in_group("player")
        if players.size() > 0:
            _target = players[0] as Node3D

    # Emit event to update HUD
    if is_player and _target != null and is_instance_valid(_target):
        GameEvents.target_changed.emit(_target)
