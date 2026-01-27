class_name BoatMovementController
extends Node3D

## Controller for future boat movement animations
## Currently static but with architecture for movement implementation

@export var boat_type: String = ""
@export var is_static: bool = true
@export var movement_pattern: String = "static"

# Movement parameters (for future use)
@export var speed: float = 15.0
@export var turn_speed: float = 2.0
@export var wander_radius: float = 50.0
@export var patrol_points: Array[Vector3] = []

# Internal state
var is_enabled: bool = false
var original_position: Vector3
var current_target: Vector3
var movement_timer: float = 0.0

func _ready() -> void:
    # Store original position
    original_position = global_position
    current_target = original_position

func set_movement_enabled(enabled: bool) -> void:
    is_enabled = enabled
    
    if enabled and is_static:
        # Transition from static to moving
        is_static = false
        _generate_patrol_points()

func set_movement_pattern(pattern: String) -> void:
    movement_pattern = pattern
    _generate_patrol_points()

func _process(delta: float) -> void:
    if is_static or not is_enabled:
        return
    
    movement_timer += delta
    _execute_movement_pattern(delta)

# --- Future movement patterns ---

func _execute_movement_pattern(delta: float) -> void:
    match movement_pattern:
        "patrol":
            _execute_patrol_movement(delta)
        "sailing":
            _execute_sailing_movement(delta)
        "racing":
            _execute_racing_movement(delta)
        "leisure":
            _execute_leisure_movement(delta)
        _:
            pass  # Static or unknown pattern

func _execute_patrol_movement(delta: float) -> void:
    if patrol_points.size() < 2:
        return
    
    # Move towards current target
    var direction = (current_target - global_position).normalized()
    var distance = global_position.distance_to(current_target)
    
    if distance > 1.0:
        # Move towards target
        var move_vector = direction * speed * delta
        global_position += move_vector
        
        # Face movement direction
        if move_vector.length() > 0.1:
            look_at(global_position + move_vector, Vector3.UP)
    else:
        # Reached target, select next
        _select_next_patrol_point()

func _execute_sailing_movement(delta: float) -> void:
    # Sailing movement with wind simulation
    var wind_direction = Vector3(sin(movement_timer * 0.1), 0, cos(movement_timer * 0.1))
    var sail_force = wind_direction * speed * 0.5
    
    var target_pos = original_position + sail_force * 10.0
    var direction = (target_pos - global_position).normalized()
    
    global_position += direction * speed * delta * 0.8
    
    # Gentle turning
    if direction.length() > 0.1:
        var target_rotation = atan2(direction.x, direction.z)
        var current_rotation = rotation.y
        var rotation_diff = target_rotation - current_rotation
        
        # Normalize rotation difference
        while rotation_diff > PI:
            rotation_diff -= TAU
        while rotation_diff < -PI:
            rotation_diff += TAU
        
        rotation.y += rotation_diff * turn_speed * delta

func _execute_racing_movement(delta: float) -> void:
    # Fast racing movement in patterns
    var race_center = original_position
    var race_radius = wander_radius
    
    # Circular racing pattern
    var angle = movement_timer * speed * 0.05
    var target_pos = race_center + Vector3(
        cos(angle) * race_radius,
        0,
        sin(angle) * race_radius
    )
    
    var direction = (target_pos - global_position).normalized()
    global_position += direction * speed * delta
    
    # Face movement direction aggressively
    if direction.length() > 0.1:
        look_at(global_position + direction * 5.0, Vector3.UP)

func _execute_leisure_movement(delta: float) -> void:
    # Slow, random leisure movement
    movement_timer += delta
    
    # Change direction occasionally
    if movement_timer > 3.0:
        var random_angle = randf() * TAU
        current_target = original_position + Vector3(
            cos(random_angle) * wander_radius,
            0,
            sin(random_angle) * wander_radius
        )
        movement_timer = 0.0
    
    var direction = (current_target - global_position).normalized()
    var distance = global_position.distance_to(current_target)
    
    if distance > 2.0:
        global_position += direction * speed * 0.3 * delta
        
        if direction.length() > 0.1:
            look_at(global_position + direction * 2.0, Vector3.UP)

# --- Patrol point management ---

func _generate_patrol_points() -> void:
    patrol_points.clear()
    
    match movement_pattern:
        "patrol":
            # Generate patrol points around lake area
            for i in range(4):
                var angle = (TAU / 4) * i
                var point = original_position + Vector3(
                    cos(angle) * wander_radius,
                    0,
                    sin(angle) * wander_radius
                )
                patrol_points.append(point)
        
        "racing":
            # Generate racing circuit
            for i in range(6):
                var angle = (TAU / 6) * i
                var radius = wander_radius * (1.0 + 0.3 * sin(i * 2))
                var point = original_position + Vector3(
                    cos(angle) * radius,
                    0,
                    sin(angle) * radius
                )
                patrol_points.append(point)
        
        _:
            # Default: simple back and forth
            patrol_points.append(original_position + Vector3(wander_radius, 0, 0))
            patrol_points.append(original_position - Vector3(wander_radius, 0, 0))
    
    if patrol_points.size() > 0:
        current_target = patrol_points[0]

func _select_next_patrol_point() -> void:
    if patrol_points.size() < 2:
        return
    
    # Find current target index
    var current_index = -1
    for i in range(patrol_points.size()):
        if patrol_points[i] == current_target:
            current_index = i
            break
    
    # Select next point (circular)
    var next_index = (current_index + 1) % patrol_points.size()
    current_target = patrol_points[next_index]

# --- Public API for external control ---

func stop_movement() -> void:
    is_static = true
    is_enabled = false

func start_movement() -> void:
    is_static = false
    is_enabled = true

func set_speed(new_speed: float) -> void:
    speed = new_speed

func get_movement_status() -> Dictionary:
    return {
        "boat_type": boat_type,
        "is_static": is_static,
        "is_enabled": is_enabled,
        "movement_pattern": movement_pattern,
        "current_position": global_position,
        "original_position": original_position,
        "current_target": current_target,
        "speed": speed
    }