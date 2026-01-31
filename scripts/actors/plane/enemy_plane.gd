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

    # Let the base plane weapon logic aim at the player when firing.
    set_target(_player)

    # Debug: Track enemy position and controls
    if randf() < 0.01:  # Print every ~1% of frames
        var to_p = _player.global_position - global_position
        var dist = to_p.length()
        var aim = to_p.normalized()
        var f = get_forward()
        var ang = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
        print("DEBUG: Enemy at position: ", global_position, " Player at: ", _player.global_position)
        print("DEBUG: Distance: ", dist, " Aim: ", aim, " Forward: ", f, " Angle: ", ang)
        print("DEBUG: Controls - Yaw: ", in_yaw, " Pitch: ", in_pitch, " Roll: ", in_roll, " Throttle: ", throttle)

    var f = get_forward()
    var to_p = _player.global_position - global_position
    var dist = to_p.length()
    if dist < 1.0:
        return

    # Direction to player in world space.
    var aim: Vector3 = to_p / dist

    # --- IMPORTANT FIX --------------------------------------------------------
    # The old AI used:
    #   yaw_error = right.dot(aim)
    # which becomes ~0 when the player is directly behind the enemy.
    # That means in_yaw ~ 0 -> the enemy never turns around -> it just "extends" away,
    # and the distance-based throttle then makes it accelerate further away.
    #
    # Instead, compute the *signed yaw angle* in local space using atan2 so "behind"
    # correctly produces ~pi radians and forces a hard turn.
    var aim_local: Vector3 = global_transform.basis.transposed() * aim
    var yaw_ang: float = atan2(aim_local.x, -aim_local.z)    # + => target to the right

    # Yaw is a *yaw-rate command* in plane.gd, so drive it from the yaw angle.
    var yaw_gain: float = 1.6
    in_yaw = clampf(yaw_ang * yaw_gain, -1.0, 1.0)

    # Pitch is an *attitude command* (desired pitch relative to horizon). Use the
    # aim vector's vertical angle as the target pitch.
    var desired_pitch: float = asin(clampf(aim.y, -1.0, 1.0))
    in_pitch = clampf(desired_pitch / deg_to_rad(pitch_max_deg), -1.0, 1.0)

    # Bank into the turn (this makes the flight path curve instead of just skidding).
    var desired_bank_cmd: float = clampf(yaw_ang / deg_to_rad(bank_max_deg), -1.0, 1.0)

    # Add some evasive maneuvering
    _evade_t -= dt
    if _evade_t <= 0.0:
        _evade_t = randf_range(1.2, 2.6)

    var evade = sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.22
    in_roll = clampf(desired_bank_cmd + evade, -1.0, 1.0)

    # Throttle: keep it fighty, but don't "run away" when we're pointing away.
    # If the player is mostly behind us, prioritize turning (and keep speed up).
    var forward_dot: float = f.dot(aim)  # +1 = player ahead, -1 = player behind
    if forward_dot < -0.25:
        throttle = 0.95
    else:
        var desired_dist: float = 450.0
        var dist_factor = clampf((dist - desired_dist) / desired_dist, -0.6, 0.8)
        throttle = clampf(0.55 + dist_factor * 0.35, 0.35, 1.0)

    # Gun bursts when roughly aligned
    var ang = rad_to_deg(acos(clampf(f.dot(aim), -1.0, 1.0)))
    _shoot_t -= dt
    if ang < 15.0 and dist < 900.0:  # Increased angle tolerance for shooting
        if _shoot_t <= 0.0:
            _shoot_t = randf_range(0.55, 1.1)
        gun_trigger = true
    else:
        gun_trigger = false

    # Call parent physics process to handle flight dynamics
    super(dt)
