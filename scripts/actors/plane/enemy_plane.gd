extends "res://scripts/actors/plane/plane.gd"
# Simple AI:
# - lead pursuit toward player
# - periodic evasive rolls
# - gun-only (WW2)

var _player: Node3D
var _evade_t: float = 0.0
var _shoot_t: float = 0.0

func _ready() -> void:
    is_player = false
    super()
    throttle = 0.7
    add_to_group("enemies")

func set_player(p: Node) -> void:
    _player = p as Node3D

func _physics_process(dt: float) -> void:
    if _player == null or not is_instance_valid(_player):
        return

    # Debug: Track enemy position occasionally
    if randf() < 0.01:  # Print every ~1% of frames
        print("DEBUG: Enemy at position: ", global_position, " Player at: ", _player.global_position)

    var f = get_forward()
    var to_p = _player.global_position - global_position
    var dist = to_p.length()
    if dist < 1.0:
        return

    # Lead pursuit (more aggressive)
    var pv: Vector3 = Vector3.ZERO
    if _player is RigidBody3D:
        pv = (_player as RigidBody3D).linear_velocity
    var lead = to_p + pv * 0.7  # Reduced lead time to make pursuit more direct
    var aim = lead.normalized()

    # Desired yaw/pitch errors.
    var right = get_right()
    var up = get_up()

    var yaw_err = right.dot(aim)
    var pitch_err = up.dot(aim)

    _evade_t -= dt
    if _evade_t <= 0.0:
        _evade_t = randf_range(1.2, 2.6)

    # Gentle evasive roll bias
    var evade = sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.22

    # More aggressive pursuit controls
    in_yaw = clampf(yaw_err * 2.0, -1.0, 1.0)  # Increased sensitivity to turn toward target
    in_pitch = clampf(pitch_err * 1.8, -1.0, 1.0)  # Increased sensitivity to turn toward target
    in_roll = clampf(evade, -0.6, 0.6)  # Reduced from 1.0 to 0.6

    # Throttle management - more aggressive pursuit
    var desired_dist = 400.0  # Desired distance to player
    var dist_factor = clampf((dist - desired_dist) / desired_dist, -0.5, 1.0)
    throttle = clampf(0.6 + dist_factor * 0.4, 0.3, 1.0)

    # Prevent enemies from flying away by checking if they're moving away from player
    var prev_player_pos = _player.global_position - pv * dt  # Approximate previous position
    var prev_to_p = prev_player_pos - global_position
    var prev_dist = prev_to_p.length()

    # If enemy is moving away from player, increase turn aggressiveness
    if dist > prev_dist + 1.0:  # If getting further away significantly
        in_yaw = clampf(yaw_err * 2.5, -1.0, 1.0)  # Even more aggressive turning
        in_pitch = clampf(pitch_err * 2.2, -1.0, 1.0)  # Even more aggressive pitching
        throttle = min(throttle, 0.8)  # Slightly reduce throttle if moving away

    # Gun bursts when roughly aligned
    var ang = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
    _shoot_t -= dt
    if ang < 5.5 and dist < 900.0:
        if _shoot_t <= 0.0:
            _shoot_t = randf_range(0.55, 1.1)
        gun_trigger = true
    else:
        gun_trigger = false
