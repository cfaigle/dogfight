extends Node3D
class_name SmartBoatMovement

## Smart boat movement with LOD, shore avoidance, and animations
## Designed for 10,000+ boats with performance in mind

@export var boat_type: String = ""
@export var movement_pattern: String = "static"
@export var base_speed: float = 15.0
@export var area_radius: float = 200.0

# Internal state
var _original_position: Vector3
var _current_target: Vector3
var _movement_timer: float = 0.0
var _wander_timer: float = 0.0
var _is_active: bool = false
var _lod_level: int = 2  # 0=close, 1=medium, 2=far (static)
var _terrain_generator: TerrainGenerator = null
var _sea_level: float = 0.0
var _patrol_points: Array[Vector3] = []
var _current_patrol_index: int = 0

# Animation state
var _sail_nodes: Array[Node3D] = []
var _wave_offset: float = 0.0

func _ready() -> void:
    _original_position = global_position
    _current_target = _original_position
    _wave_offset = randf() * TAU  # Randomize wave phase

    # Find sail nodes if this is a sailboat
    _find_sail_nodes(self)

func setup(terrain: TerrainGenerator, sea_level: float) -> void:
    _terrain_generator = terrain
    _sea_level = sea_level
    _generate_patrol_points()

func _find_sail_nodes(node: Node) -> void:
    if "Sail" in node.name or "Jib" in node.name:
        _sail_nodes.append(node)
    for child in node.get_children():
        _find_sail_nodes(child)

func _process(delta: float) -> void:
    if not _is_active or _lod_level >= 2:
        return

    _movement_timer += delta
    _execute_movement(delta)

    # Animate sails if close
    if _lod_level == 0 and not _sail_nodes.is_empty():
        _animate_sails(delta)

func update_lod(distance_to_player: float) -> void:
    # LOD levels: 0-200m = active, 200-500m = simple, 500+ = static
    if distance_to_player < 200.0:
        _lod_level = 0
        _is_active = true
    elif distance_to_player < 500.0:
        _lod_level = 1
        _is_active = true
    else:
        _lod_level = 2
        _is_active = false

func _execute_movement(delta: float) -> void:
    match movement_pattern:
        "sailing":
            _move_sailing(delta)
        "patrol":
            _move_patrol(delta)
        "racing":
            _move_racing(delta)
        "leisure":
            _move_leisure(delta)
        "cargo":
            _move_cargo(delta)
        "cruise":
            _move_cruise(delta)
        "tug":
            _move_tug(delta)
        "trawl":
            _move_trawl(delta)
        "drift":
            _move_drift(delta)
        _:
            pass  # static

## SAILING: Wind-driven movement with tacking
func _move_sailing(delta: float) -> void:
    # Simulated wind direction (slowly rotating)
    var wind_angle = _movement_timer * 0.05
    var wind_dir = Vector3(sin(wind_angle), 0, cos(wind_angle))

    # Sailboats tack into wind
    var target_pos = _original_position + wind_dir * area_radius * 0.6
    var move_dir = (target_pos - global_position).normalized()

    # Check shore before moving
    if _can_move_to(global_position + move_dir * base_speed * delta):
        global_position += move_dir * base_speed * delta * 0.7
        _smooth_rotate_toward(move_dir, delta * 1.5)

## PATROL: Follow waypoints (working boats, ferries)
func _move_patrol(delta: float) -> void:
    if _patrol_points.is_empty():
        _generate_patrol_points()
        return

    var target = _patrol_points[_current_patrol_index]
    var to_target = target - global_position
    to_target.y = 0
    var dist = to_target.length()

    if dist < 5.0:
        # Reached waypoint
        _current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
        return

    var move_dir = to_target.normalized()
    if _can_move_to(global_position + move_dir * base_speed * delta):
        global_position += move_dir * base_speed * delta
        _smooth_rotate_toward(move_dir, delta * 2.0)

## RACING: Fast circular patterns (speedboats)
func _move_racing(delta: float) -> void:
    var angle = _movement_timer * base_speed * 0.08
    var target_pos = _original_position + Vector3(
        cos(angle) * area_radius * 0.7,
        0,
        sin(angle) * area_radius * 0.7
    )

    var move_dir = (target_pos - global_position).normalized()
    if _can_move_to(global_position + move_dir * base_speed * 1.2 * delta):
        global_position += move_dir * base_speed * 1.2 * delta
        look_at(global_position + move_dir * 10.0, Vector3.UP)

## LEISURE: Slow random wandering (pontoons, rafts)
func _move_leisure(delta: float) -> void:
    _wander_timer += delta

    if _wander_timer > 5.0:
        # Pick new random target
        var random_angle = randf() * TAU
        _current_target = _original_position + Vector3(
            cos(random_angle) * area_radius * 0.4,
            0,
            sin(random_angle) * area_radius * 0.4
        )
        _wander_timer = 0.0

    var to_target = _current_target - global_position
    to_target.y = 0
    var dist = to_target.length()

    if dist > 3.0:
        var move_dir = to_target.normalized()
        if _can_move_to(global_position + move_dir * base_speed * 0.3 * delta):
            global_position += move_dir * base_speed * 0.3 * delta
            _smooth_rotate_toward(move_dir, delta * 0.8)

## CARGO: Slow straight-line shipping lanes (freighters, tankers)
func _move_cargo(delta: float) -> void:
    # Move in straight lines between waypoints
    if _patrol_points.is_empty():
        _generate_shipping_lane()
        return

    var target = _patrol_points[_current_patrol_index]
    var to_target = target - global_position
    to_target.y = 0
    var dist = to_target.length()

    if dist < 10.0:
        _current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
        return

    var move_dir = to_target.normalized()
    if _can_move_to(global_position + move_dir * base_speed * 0.5 * delta):
        global_position += move_dir * base_speed * 0.5 * delta
        _smooth_rotate_toward(move_dir, delta * 0.5)  # Slow turning

## CRUISE: Large circular cruising (cruise liners)
func _move_cruise(delta: float) -> void:
    var angle = _movement_timer * 0.02  # Very slow
    var cruise_radius = area_radius * 1.5
    var target_pos = _original_position + Vector3(
        cos(angle) * cruise_radius,
        0,
        sin(angle) * cruise_radius
    )

    var move_dir = (target_pos - global_position).normalized()
    if _can_move_to(global_position + move_dir * base_speed * 0.4 * delta):
        global_position += move_dir * base_speed * 0.4 * delta
        _smooth_rotate_toward(move_dir, delta * 0.6)

## TUG: Short back-and-forth in harbor areas
func _move_tug(delta: float) -> void:
    var oscillate = sin(_movement_timer * 0.3) * area_radius * 0.3
    var target_pos = _original_position + Vector3(oscillate, 0, 0)

    var move_dir = (target_pos - global_position).normalized()
    if _can_move_to(global_position + move_dir * base_speed * 0.6 * delta):
        global_position += move_dir * base_speed * 0.6 * delta
        _smooth_rotate_toward(move_dir, delta * 1.2)

## TRAWL: Figure-8 fishing patterns (trawlers)
func _move_trawl(delta: float) -> void:
    var t = _movement_timer * 0.05
    var fig8_x = sin(t) * area_radius * 0.5
    var fig8_z = sin(t * 2) * area_radius * 0.5
    var target_pos = _original_position + Vector3(fig8_x, 0, fig8_z)

    var move_dir = (target_pos - global_position).normalized()
    if _can_move_to(global_position + move_dir * base_speed * 0.5 * delta):
        global_position += move_dir * base_speed * 0.5 * delta
        _smooth_rotate_toward(move_dir, delta * 1.0)

## DRIFT: Minimal movement, just floating (rafts, anchored boats)
func _move_drift(delta: float) -> void:
    # Very slow random drift
    var drift_x = sin(_movement_timer * 0.1 + _wave_offset) * 0.5
    var drift_z = cos(_movement_timer * 0.15 + _wave_offset) * 0.5
    global_position.x += drift_x * delta
    global_position.z += drift_z * delta

## SHORE AVOIDANCE - Check terrain before moving
func _can_move_to(target_pos: Vector3) -> bool:
    if _terrain_generator == null:
        return true  # No terrain check, allow movement

    var terrain_h = _terrain_generator.get_height_at(target_pos.x, target_pos.z)

    # If terrain is above sea level, we're hitting shore!
    if terrain_h > _sea_level - 2.0:
        return false

    return true

func _smooth_rotate_toward(direction: Vector3, turn_speed: float) -> void:
    if direction.length() < 0.01:
        return

    var target_angle = atan2(direction.x, direction.z)
    var current_angle = rotation.y
    var angle_diff = target_angle - current_angle

    # Normalize to -PI to PI
    while angle_diff > PI:
        angle_diff -= TAU
    while angle_diff < -PI:
        angle_diff += TAU

    rotation.y += angle_diff * turn_speed

## SAIL ANIMATION - Billowing effect
func _animate_sails(delta: float) -> void:
    var wind_strength = 0.5 + sin(_movement_timer * 2.0 + _wave_offset) * 0.3

    for sail in _sail_nodes:
        if sail is MeshInstance3D:
            # Scale sails slightly to simulate billowing
            var base_scale = sail.get_meta("base_scale", Vector3.ONE)
            var billow = 1.0 + wind_strength * 0.15
            sail.scale = base_scale * Vector3(billow, 1.0, billow)

            # Store base scale on first frame
            if not sail.has_meta("base_scale"):
                sail.set_meta("base_scale", sail.scale)

## PATROL POINT GENERATION
func _generate_patrol_points() -> void:
    _patrol_points.clear()

    match movement_pattern:
        "patrol", "cargo":
            # Square patrol
            for i in range(4):
                var angle = (TAU / 4) * i
                var point = _original_position + Vector3(
                    cos(angle) * area_radius * 0.6,
                    0,
                    sin(angle) * area_radius * 0.6
                )
                _patrol_points.append(point)
        "racing":
            # 8-point race circuit
            for i in range(8):
                var angle = (TAU / 8) * i
                var point = _original_position + Vector3(
                    cos(angle) * area_radius * 0.7,
                    0,
                    sin(angle) * area_radius * 0.7
                )
                _patrol_points.append(point)
        _:
            # Default: back and forth
            _patrol_points.append(_original_position + Vector3(area_radius * 0.5, 0, 0))
            _patrol_points.append(_original_position - Vector3(area_radius * 0.5, 0, 0))

    _current_patrol_index = 0

func _generate_shipping_lane() -> void:
    # Generate long straight shipping lane
    _patrol_points.clear()
    var lane_length = area_radius * 3.0
    _patrol_points.append(_original_position + Vector3(-lane_length, 0, 0))
    _patrol_points.append(_original_position + Vector3(lane_length, 0, 0))
    _current_patrol_index = 0

## PUBLIC API
func enable_movement() -> void:
    _is_active = true

func disable_movement() -> void:
    _is_active = false

func set_movement_pattern(pattern: String) -> void:
    movement_pattern = pattern
    _generate_patrol_points()
