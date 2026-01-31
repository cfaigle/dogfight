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

    # Lead pursuit (rough)
    var pv: Vector3 = Vector3.ZERO
    if _player is RigidBody3D:
        pv = (_player as RigidBody3D).linear_velocity
    var lead = to_p + pv * 0.9
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

    # Limit control inputs to prevent erratic behavior
    in_yaw = clampf(yaw_err * 1.6, -0.8, 0.8)  # Reduced from 1.0 to 0.8
    in_pitch = clampf(pitch_err * 1.5, -0.8, 0.8)  # Reduced from 1.0 to 0.8
    in_roll = clampf(evade, -0.6, 0.6)  # Reduced from 1.0 to 0.6

    # Throttle management - keep enemies closer to player
    # Reduce throttle when too far from player to prevent them from flying away
    var max_comfortable_distance = 1200.0  # Enemies should stay within this distance
    if dist > max_comfortable_distance:
        # Reduce throttle to slow down when too far
        throttle = 0.3
    else:
        # Normal throttle management
        throttle = clampf(0.55 + (dist / 1200.0) * 0.35, 0.4, 0.9)  # Reduced max to 0.9

    # Gun bursts when roughly aligned
    var ang = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
    _shoot_t -= dt
    if ang < 5.5 and dist < 900.0:
        if _shoot_t <= 0.0:
            _shoot_t = randf_range(0.55, 1.1)
        gun_trigger = true
    else:
        gun_trigger = false
