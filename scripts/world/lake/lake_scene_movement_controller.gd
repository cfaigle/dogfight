class_name LakeSceneMovementController
extends Node3D

## Controller for entire lake scene movement
## Coordinates movement of all boats in a lake scene

# Scene configuration
@export var is_enabled: bool = false
@export var lake_data: Dictionary = {}
@export var scene_type: String = "basic"

# Boat management
var boat_controllers: Array[BoatMovementController] = []
var movement_timer: float = 0.0

# Lake-wide behavior settings
var wind_strength: float = 1.0
var wind_direction: Vector3 = Vector3.RIGHT
var time_of_day: float = 0.5  # 0.0 = dawn, 0.5 = noon, 1.0 = dusk

func _ready() -> void:
    # Collect all boat movement controllers
    _collect_boat_controllers()
    
    # Initialize lake-wide conditions
    _initialize_lake_conditions()

func set_movement_enabled(enabled: bool) -> void:
    is_enabled = enabled
    
    for controller in boat_controllers:
        if controller != null:
            controller.set_movement_enabled(enabled)

func _process(delta: float) -> void:
    if not is_enabled:
        return
    
    movement_timer += delta
    _update_lake_conditions(delta)
    _coordinate_boat_movement(delta)

# --- Boat controller management ---

func _collect_boat_controllers() -> void:
    boat_controllers.clear()
    
    # Find all boat nodes in the scene
    var parent = get_parent()
    if parent == null:
        return
    
    var boat_nodes = []
    _find_boat_nodes(parent, boat_nodes)
    
    # Get movement controllers from each boat
    for boat_node in boat_nodes:
        var movement_controller = boat_node.get_node_or_null("MovementController")
        if movement_controller is BoatMovementController:
            boat_controllers.append(movement_controller)

func _find_boat_nodes(node: Node, result: Array) -> void:
    var node_name = node.name.to_lower()
    if "boat" in node_name:
        result.append(node)
    
    for child in node.get_children():
        _find_boat_nodes(child, result)

# --- Lake-wide condition simulation ---

func _initialize_lake_conditions() -> void:
    # Set initial wind conditions based on scene type
    match scene_type:
        "recreational":
            wind_strength = 0.8
            wind_direction = Vector3.RIGHT
        "fishing":
            wind_strength = 0.6
            wind_direction = Vector3.RIGHT * 0.8
        "harbor":
            wind_strength = 0.4
            wind_direction = Vector3.RIGHT * 0.6
        _:
            wind_strength = 0.5
            wind_direction = Vector3.RIGHT
    
    # Set time of day (affects boat behavior)
    time_of_day = 0.6  # Afternoon

func _update_lake_conditions(delta: float) -> void:
    # Simulate changing conditions over time
    
    # Wind variations
    var wind_variation = sin(movement_timer * 0.1) * 0.3
    var current_wind_strength = wind_strength * (1.0 + wind_variation)
    
    # Wind direction changes (slow, natural)
    var wind_rotation = movement_timer * 0.02
    var current_wind_direction = wind_direction.rotated(Vector3.UP, wind_rotation)
    
    # Update boat controllers with new conditions
    for controller in boat_controllers:
        if controller != null and controller.movement_pattern == "sailing":
            _update_sailboat_conditions(controller, current_wind_direction, current_wind_strength)

func _update_sailboat_conditions(controller: BoatMovementController, wind_dir: Vector3, wind_strength_val: float) -> void:
    # Adjust sailboat speed based on wind conditions
    var base_speed = 8.0
    var wind_factor = wind_strength_val
    
    # Calculate optimal angle to wind
    var optimal_angle = wind_dir.angle_to(Vector3.RIGHT)
    
    # Adjust speed based on how well aligned with wind
    var alignment_factor = abs(cos(optimal_angle))
    var adjusted_speed = base_speed * wind_factor * (0.3 + 0.7 * alignment_factor)
    
    controller.set_speed(adjusted_speed)

# --- Boat coordination ---

func _coordinate_boat_movement(delta: float) -> void:
    # Coordinate boat movements to avoid collisions and create realistic traffic patterns
    
    for i in range(boat_controllers.size()):
        var controller = boat_controllers[i]
        if controller == null or not controller.is_enabled:
            continue
        
        # Avoid collisions with other boats
        for j in range(boat_controllers.size()):
            if i == j:
                continue
            
            var other_controller = boat_controllers[j]
            if other_controller == null or not other_controller.is_enabled:
                continue
            
            _check_and_avoid_collision(controller, other_controller)
        
        # Adjust behavior based on time of day
        _adjust_behavior_by_time(controller)

func _check_and_avoid_collision(controller1: BoatMovementController, controller2: BoatMovementController) -> void:
    var pos1 = controller1.global_position
    var pos2 = controller2.global_position
    var distance = pos1.distance_to(pos2)
    
    # Collision avoidance threshold
    var avoidance_distance = 15.0
    
    if distance < avoidance_distance:
        # Calculate avoidance direction
        var avoidance_dir = (pos1 - pos2).normalized()
        var avoidance_strength = 1.0 - (distance / avoidance_distance)
        
        # Apply gentle avoidance (modify target position)
        if controller1.movement_pattern == "patrol":
            var current_target = controller1.current_target
            var new_target = current_target + avoidance_dir * avoidance_distance * avoidance_strength
            controller1.current_target = new_target

func _adjust_behavior_by_time(controller: BoatMovementController) -> void:
    # Adjust boat behavior based on time of day
    match controller.movement_pattern:
        "leisure":
            # More leisure boats active during midday
            var activity_factor = 1.0 - abs(time_of_day - 0.5) * 2.0
            var adjusted_speed = controller.speed * (0.5 + 0.5 * activity_factor)
            controller.set_speed(adjusted_speed)
        
        "racing":
            # Racing boats prefer morning/evening
            var racing_factor = 1.0 - abs(time_of_day - 0.3) * 1.5
            if racing_factor < 0.3:
                controller.set_movement_enabled(false)  # Too hot for racing
            else:
                controller.set_movement_enabled(true)
                var adjusted_speed = controller.speed * racing_factor
                controller.set_speed(adjusted_speed)
        
        "fishing":
            # Fishing boats prefer early morning/evening
            var fishing_factor = 1.0 - abs(time_of_day - 0.2) * 2.0
            if fishing_factor < 0.4:
                controller.set_speed(controller.speed * 0.3)  # Slow fishing
            else:
                controller.set_speed(controller.speed * 0.8)

# --- Public API ---

func start_lake_activity() -> void:
    is_enabled = true
    set_movement_enabled(true)

func stop_lake_activity() -> void:
    set_movement_enabled(false)
    is_enabled = false

func set_time_of_day(time: float) -> void:
    time_of_day = clamp(time, 0.0, 1.0)

func set_wind_conditions(direction: Vector3, strength: float) -> void:
    wind_direction = direction.normalized()
    wind_strength = clamp(strength, 0.0, 2.0)

func get_lake_status() -> Dictionary:
    var active_boats = 0
    for controller in boat_controllers:
        if controller != null and controller.is_enabled:
            active_boats += 1
    
    return {
        "scene_type": scene_type,
        "is_enabled": is_enabled,
        "total_boats": boat_controllers.size(),
        "active_boats": active_boats,
        "wind_strength": wind_strength,
        "wind_direction": wind_direction,
        "time_of_day": time_of_day
    }