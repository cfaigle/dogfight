class_name LakeSceneLOD
extends Node3D

## Distance-based LOD controller for lake scenes
## Manages visibility of different detail levels based on camera distance

var high_detail: Node3D
var medium_detail: Node3D
var low_detail: Node3D
var lake_center: Vector3
var lod_distance: float

var camera: Camera3D = null
var enabled: bool = true

# LOD distance thresholds
var high_detail_threshold: float = 200.0
var medium_detail_threshold: float = 500.0

func setup_static_lod(high: Node3D, medium: Node3D, low: Node3D, center: Vector3, max_distance: float) -> void:
    high_detail = high
    medium_detail = medium
    low_detail = low
    lake_center = center
    lod_distance = max_distance
    
    # Set thresholds
    high_detail_threshold = max_distance * 0.4
    medium_detail_threshold = max_distance
    
    # Add as children
    if high_detail != null:
        add_child(high_detail)
        high_detail.name = "HighDetail"
    
    if medium_detail != null:
        add_child(medium_detail)
        medium_detail.name = "MediumDetail"
    
    if low_detail != null:
        add_child(low_detail)
        low_detail.name = "LowDetail"

func _ready() -> void:
    # Find the main camera
    _find_camera()
    
    # Initial LOD update
    _update_lod()

func _process(_delta: float) -> void:
    if not enabled:
        return
    
    # Update LOD every few frames for performance
    if Engine.get_frames_drawn() % 4 == 0:
        _update_lod()

func _find_camera() -> void:
    # Try to find the main camera from Game
    if Game and Game.has_method("get_main_camera"):
        camera = Game.get_main_camera()
    
    # Fallback: find any camera in the scene
    if camera == null:
        var cameras = get_tree().get_nodes_in_group("camera")
        if cameras.size() > 0:
            camera = cameras[0]

func _update_lod() -> void:
    if camera == null:
        _find_camera()
        if camera == null:
            return
    
    # Calculate distance from camera to lake center
    var camera_pos = camera.global_position
    var distance = camera_pos.distance_to(lake_center)
    
    # Update visibility based on distance
    if distance <= high_detail_threshold:
        _set_lod_level("high")
    elif distance <= medium_detail_threshold:
        _set_lod_level("medium")
    else:
        _set_lod_level("low")

func _set_lod_level(level: String) -> void:
    match level:
        "high":
            _set_visibility(high_detail, true)
            _set_visibility(medium_detail, false)
            _set_visibility(low_detail, false)
        "medium":
            _set_visibility(high_detail, false)
            _set_visibility(medium_detail, true)
            _set_visibility(low_detail, false)
        "low":
            _set_visibility(high_detail, false)
            _set_visibility(medium_detail, false)
            _set_visibility(low_detail, true)

func _set_visibility(node: Node3D, visible: bool) -> void:
    if node == null:
        return
    
    if node is VisualInstance3D:
        node.visible = visible
    
    # Apply to all descendants
    for child in node.get_children():
        _set_child_visibility(child, visible)

func _set_child_visibility(node: Node, visible: bool) -> void:
    if node is VisualInstance3D:
        node.visible = visible
    
    for child in node.get_children():
        _set_child_visibility(child, visible)

func set_enabled(is_enabled: bool) -> void:
    enabled = is_enabled
    if is_enabled:
        _update_lod()

func get_current_lod_level() -> String:
    if high_detail != null and high_detail.visible:
        return "high"
    elif medium_detail != null and medium_detail.visible:
        return "medium"
    elif low_detail != null and low_detail.visible:
        return "low"
    else:
        return "unknown"