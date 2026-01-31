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

    # Simple direct pursuit without complex lead prediction
    var aim = to_p.normalized()

    # Calculate the errors between current forward direction and desired direction
    var current_forward = get_forward()  # Current forward direction (-Z)
    var current_up = get_up()  # Current up direction (Y)
    var current_right = get_right()  # Current right direction (X)

    # Calculate yaw and pitch errors using dot products (simpler and more reliable)
    var yaw_error = current_right.dot(aim)  # Positive if target is to the right
    var pitch_error = current_up.dot(aim)   # Positive if target is above

    # Calculate the angle between current forward and desired aim direction
    var angle_to_target = acos(clampf(current_forward.dot(aim), -1.0, 1.0))

    # If the enemy is pointing significantly away from the target, apply maximum control
    if angle_to_target > deg_to_rad(30.0):  # If more than 30 degrees off (more aggressive)
        in_yaw = sign(yaw_error) * 0.9  # Near-maximum deflection
        in_pitch = sign(pitch_error) * 0.9  # Near-maximum deflection
    elif angle_to_target > deg_to_rad(15.0):  # If more than 15 degrees off
        in_yaw = sign(yaw_error) * 0.7  # Medium deflection
        in_pitch = sign(pitch_error) * 0.7  # Medium deflection
    else:
        # Apply controls based on errors - make them extremely aggressive when close to target direction
        in_yaw = clampf(yaw_error * 4.0, -1.0, 1.0)  # High sensitivity
        in_pitch = clampf(pitch_error * 4.0, -1.0, 1.0)  # High sensitivity

    # Add some evasive maneuvering
    _evade_t -= dt
    if _evade_t <= 0.0:
        _evade_t = randf_range(1.2, 2.6)

    var evade = sin(Time.get_ticks_msec() / 1000.0 * 2.2) * 0.3
    in_roll = clampf(evade, -0.6, 0.6)

    # Throttle based on distance to player
    var desired_dist = 400.0  # Desired distance to player
    var dist_factor = clampf((dist - desired_dist) / desired_dist, -0.5, 1.0)
    throttle = clampf(0.6 + dist_factor * 0.4, 0.3, 1.0)

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
