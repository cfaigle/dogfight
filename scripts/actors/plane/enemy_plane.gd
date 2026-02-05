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
    var dist: float = to_p.length()  # Keep actual distance for all distance-based logic
    if dist < 1.0:
        return

    # Lead pursuit: predict where the player will be
    var player_velocity: Vector3 = Vector3.ZERO
    if _player is RigidBody3D:
        player_velocity = _player.linear_velocity

    # Time-to-intercept estimation (simplified)
    # Cap at 1.5 seconds to prevent aiming at positions too far in the future
    var our_speed: float = linear_velocity.length()
    var time_to_intercept: float = minf(dist / maxf(our_speed, 50.0), 1.5)
    var predicted_position: Vector3 = _player.global_position + player_velocity * time_to_intercept

    # Blend between pure pursuit and lead pursuit based on distance
    # Use less lead at close range, more at long range
    var lead_factor: float = clampf((dist - 400.0) / 1200.0, 0.0, 0.7)  # 0% at <400, 70% max at 1600+
    var target_position: Vector3 = lerp(_player.global_position, predicted_position, lead_factor)

    # Calculate aim direction (but DON'T recalculate dist - keep using actual distance to player!)
    var to_intercept: Vector3 = target_position - global_position
    var aim: Vector3 = to_intercept.normalized()

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
    if _last_dist > 0.0:
        if dist > _last_dist:  # Distance is increasing (any amount)
            _dist_increasing_time += dt
            if _dist_increasing_time > 1.0:  # Distance increasing for 1.0+ seconds
                dist_is_increasing = true
        elif dist < _last_dist - 10.0:  # Distance decreased significantly (10+ units)
            _dist_increasing_time = 0.0  # Reset only on significant decrease
        # else: distance stable or small change - keep timer running
    _last_dist = dist

    # Modify behind condition to include "not closing" detection
    var behind_modified: bool = behind or dist_is_increasing

    if behind_modified:
        # Sprint pursuit: minimize drag and build speed to close distance
        # When far behind, turning hard bleeds energy - instead accelerate in a straight line
        if dist > 800.0:
            # Long range: gentle turn, minimize drag, maximize acceleration
            var gentle_yaw_gain: float = 0.8
            in_yaw = clampf(-yaw_ang * gentle_yaw_gain, -1.0, 1.0)
            var gentle_bank: float = clampf(yaw_ang / deg_to_rad(bank_max_deg) * 0.5, -0.3, 0.3)
            in_roll = clampf(gentle_bank + evade * 0.5, -0.5, 0.5)
            # Minimize pitch to reduce drag and build speed
            var speed_pitch: float = asin(clampf(aim.y, -1.0, 1.0)) * 0.3  # Only 30% of desired pitch
            in_pitch = clampf(speed_pitch / deg_to_rad(pitch_max_deg), -0.3, 0.3)
            throttle = 0.95  # full throttle
        else:
            # Close range: hard break turn to re-engage
            in_roll = clampf(_turn_dir * 1.0 + evade, -1.0, 1.0)
            in_yaw = -_turn_dir  # invert for this model's yaw sign
            in_pitch = 0.45      # moderate pull to maintain energy
            throttle = 0.95      # full throttle
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

        # Speed-dependent pitch limiting to prevent stalls and maintain pursuit speed
        var speed_factor: float = 1.0
        var current_speed: float = our_speed
        var min_safe_speed: float = 30.0  # Minimum safe airspeed

        # Estimate required speed for pursuit (based on distance rate of change)
        # If we're slow relative to closing rate needed, limit pitch to gain speed
        var player_speed: float = player_velocity.length()
        var speed_deficit: float = player_speed - current_speed

        var desired_pitch_before_limiting: float = desired_pitch  # Store for debug

        if current_speed < min_safe_speed:
            # Below safe speed: reduce pitch authority proportionally
            speed_factor = current_speed / min_safe_speed
            # Below stall speed (< 20 m/s): force nose down to recover speed
            if current_speed < 20.0:
                desired_pitch = minf(desired_pitch, -deg_to_rad(5.0))  # Force at least 5° nose down
        elif speed_deficit > 40.0 and dist > 1000.0:
            # Player is much faster (40+ m/s) and far away: prioritize speed over pointing
            # Limit pitch to gain speed - can't catch them if we're too slow
            var max_pitch_for_speed: float = deg_to_rad(15.0)  # Max 15° pitch when speed-limited
            if desired_pitch > max_pitch_for_speed:
                if randf() < 0.01:  # Debug when limiting
                    print("DEBUG SPEED LIMIT: player_speed=", player_speed, " our_speed=", current_speed, " deficit=", speed_deficit)
                    print("DEBUG SPEED LIMIT: desired_pitch_before=", rad_to_deg(desired_pitch_before_limiting), "° limiting to ", rad_to_deg(max_pitch_for_speed), "°")
                desired_pitch = max_pitch_for_speed
                # Reduce pitch authority further if deficit is extreme
                if speed_deficit > 70.0:
                    speed_factor = 0.6  # Reduce to 60% to prioritize acceleration

        in_pitch = clampf((desired_pitch / deg_to_rad(pitch_max_deg)) * speed_factor, -1.0, 1.0)

        # Throttle: keep a minimum so we don't stall in close-in fights.
        var dist_factor: float = clampf((dist - desired_dist) / desired_dist, -0.3, 0.8)
        throttle = clampf(0.70 + dist_factor * 0.25, 0.60, 0.95)

        # Emergency throttle boost when approaching stall speed
        if current_speed < 25.0:
            throttle = 0.95  # Full throttle to recover from stall

    # Debug: Track enemy position and controls (rarely)
    if randf() < 0.01:
        var ang_dbg: float = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
        print("DEBUG [", name, "]: Enemy at position: ", global_position, " Player at: ", _player.global_position)
        print("DEBUG [", name, "]: Distance: ", dist, " Aim: ", aim, " Forward: ", f, " Angle: ", ang_dbg)
        print("DEBUG [", name, "]: Player velocity: ", player_velocity, " Our speed: ", our_speed, " Time to intercept: ", time_to_intercept)
        print("DEBUG [", name, "]: Predicted pos: ", predicted_position, " Lead factor: ", lead_factor, " Target pos: ", target_position)
        print("DEBUG [", name, "]: dist_is_increasing: ", dist_is_increasing, " _dist_increasing_time: ", _dist_increasing_time, " behind_modified: ", behind_modified)
        print("DEBUG [", name, "]: Controls - Yaw: ", in_yaw, " Pitch: ", in_pitch, " Roll: ", in_roll, " Throttle: ", throttle, " Behind: ", behind)

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
