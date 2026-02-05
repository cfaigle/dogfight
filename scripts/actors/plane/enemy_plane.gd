extends "res://scripts/actors/plane/plane.gd"
# Simple enemy AI (WW2):
# - Pursuit / break-turn behavior (won't "extend away forever")
# - Bank + pull to actually curve the flight path
# - Short gun bursts when aligned

var _player: Node3D
var _evade_t: float = 0.0
var _shoot_t: float = 0.0
var _last_dist: float = 0.0
var _dist_increasing_time: float = 0.0

# Last known lateral side of target in LOCAL space.
# +1 => target on local +X (right). -1 => target on local -X (left).
var _turn_dir: float = 1.0

func _ready() -> void:
    is_player = false
    super()
    throttle = 0.75
    add_to_group("enemies")

func set_player(p: Node) -> void:
    _player = p as Node3D

func _physics_process(dt: float) -> void:
    if _player == null or not is_instance_valid(_player):
        return

    # Let the base plane weapon logic aim at the player when firing.
    set_target(_player)

    var f: Vector3 = get_forward()
    var to_p: Vector3 = _player.global_position - global_position
    var dist: float = to_p.length()
    if dist < 1.0:
        return

    # Lead pursuit: predict where the player will be
    var player_velocity: Vector3 = Vector3.ZERO
    if _player is RigidBody3D:
        player_velocity = _player.linear_velocity

    # Time-to-intercept estimation (simplified)
    var our_speed: float = linear_velocity.length()
    var time_to_intercept: float = dist / maxf(our_speed, 50.0)  # Prevent division by zero
    var predicted_position: Vector3 = _player.global_position + player_velocity * time_to_intercept

    # Blend between pure pursuit and lead pursuit based on distance
    var lead_factor: float = clampf(dist / 800.0, 0.0, 1.0)  # 0% at 0 units, 100% at 800+ units
    var target_position: Vector3 = lerp(_player.global_position, predicted_position, lead_factor)

    var to_intercept: Vector3 = target_position - global_position
    dist = to_intercept.length()  # Recalculate distance to intercept point
    if dist < 1.0:
        return

    var aim: Vector3 = to_intercept / dist

    # Local-space direction to target (Godot local: +X right, +Y up, -Z forward).
    var aim_local: Vector3 = global_transform.basis.transposed() * aim

    # Update remembered turn direction when we have a clear left/right component.
    if absf(aim_local.x) > 0.04:
        _turn_dir = signf(aim_local.x)

    # Signed yaw angle: + => target on the right (local +X), - => left.
    var yaw_ang: float = atan2(aim_local.x, -aim_local.z)

    # Evasion wobble
    _evade_t -= dt
    if _evade_t <= 0.0:
        _evade_t = randf_range(1.2, 2.6)
    var evade: float = sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.22

    # Detect "player behind us" and force a committed break-turn.
    # NOTE: In this flight model, +in_yaw tends to yaw LEFT (right-hand rule about +Y).
    # So to yaw RIGHT we generally want negative in_yaw.
    var forward_dot: float = f.dot(aim)  # +1 ahead, -1 behind
    var behind: bool = forward_dot < -0.25 or aim_local.z > 0.25

    # Detect if we're not closing distance despite pursuing
    var dist_is_increasing: bool = false
    if _last_dist > 0.0 and dist > _last_dist + 5.0:  # Distance increased by 5+ units
        _dist_increasing_time += dt
        if _dist_increasing_time > 1.5:  # Distance increasing for 1.5+ seconds
            dist_is_increasing = true
    else:
        _dist_increasing_time = 0.0
    _last_dist = dist

    # Modify behind condition to include "not closing" detection
    var behind_modified: bool = behind or dist_is_increasing

    if behind_modified:
        # Hard break turn: bank + pull + bleed a little speed so we stop extending forever.
        in_roll = clampf(_turn_dir * 1.0 + evade, -1.0, 1.0)
        in_yaw = -_turn_dir  # invert for this model's yaw sign
        in_pitch = 0.55      # pull to keep lift during the bank
        throttle = 0.65      # don't "run away"
    else:
        # Normal pursuit: bank into the turn; add small coordinated yaw.
        # Distance-based gain multiplier: increase aggressiveness when far from target
        var desired_dist: float = 450.0
        var distance_gain: float = 1.0
        if dist > desired_dist:
            # Gradually increase steering gain from 1.0x to 3.0x as distance increases
            distance_gain = clampf(1.0 + (dist - desired_dist) / 500.0, 1.0, 3.0)

        var yaw_gain: float = 1.4 * distance_gain
        in_yaw = clampf(-yaw_ang * yaw_gain, -1.0, 1.0)

        var desired_bank_cmd: float = clampf(yaw_ang / deg_to_rad(bank_max_deg) * distance_gain, -1.0, 1.0)
        in_roll = clampf(desired_bank_cmd + evade, -1.0, 1.0)

        # Enforce minimum bank angle to ensure adequate turn rate when pursuing
        if not behind and dist > desired_dist * 1.2:  # Only when far away
            var min_bank: float = 0.15  # Minimum ~8-9 degree bank
            if absf(in_roll) < min_bank and absf(yaw_ang) > deg_to_rad(2.0):
                # Preserve sign but enforce minimum magnitude
                in_roll = signf(in_roll) * maxf(absf(in_roll), min_bank)

        # Pitch toward target, plus a bit of "lift hold" when banked (prevents altitude loss).
        var lift_hold: float = absf(in_roll) * deg_to_rad(12.0)
        var desired_pitch: float = asin(clampf(aim.y, -1.0, 1.0)) + lift_hold
        in_pitch = clampf(desired_pitch / deg_to_rad(pitch_max_deg), -1.0, 1.0)

        # Throttle: keep a minimum so we don't stall in close-in fights.
        var dist_factor: float = clampf((dist - desired_dist) / desired_dist, -0.3, 0.8)

        # Reduce throttle when pursuit geometry is unfavorable (small angle, large distance)
        var angle_factor: float = 1.0
        var ang_to_target: float = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
        if dist > desired_dist * 1.5 and ang_to_target < 30.0:
            # We're far away but pointed nearly at target - reduce speed to tighten turn
            angle_factor = clampf(ang_to_target / 30.0, 0.5, 1.0)  # 0.5x at 0°, 1.0x at 30°+

        throttle = clampf((0.70 + dist_factor * 0.25) * angle_factor, 0.50, 0.95)

    # Debug: Track enemy position and controls (rarely)
    if randf() < 0.01:
        var ang_dbg: float = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
        print("DEBUG: Enemy at position: ", global_position, " Player at: ", _player.global_position)
        print("DEBUG: Distance: ", dist, " Aim: ", aim, " Forward: ", f, " Angle: ", ang_dbg)
        print("DEBUG: Controls - Yaw: ", in_yaw, " Pitch: ", in_pitch, " Roll: ", in_roll, " Throttle: ", throttle, " Behind: ", behind)

    # Gun bursts when roughly aligned
    var ang: float = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
    _shoot_t -= dt
    if ang < 15.0 and dist < 900.0:
        if _shoot_t <= 0.0:
            _shoot_t = randf_range(0.55, 1.1)
        gun_trigger = true
    else:
        gun_trigger = false

    super(dt)
