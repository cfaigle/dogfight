extends Node3D

const Smooth = preload("res://scripts/util/smooth.gd")

@export var target_path: NodePath
@export var cam_path: NodePath = NodePath("MainCamera")

var _cam: Camera3D
var _target: Node3D
var _shake := 0.0
var _cam_offset := Vector3.ZERO

func _ready() -> void:
    add_to_group("camera_rig")
    _cam = get_node_or_null(cam_path) as Camera3D
    _target = get_node_or_null(target_path) as Node3D

func set_target(t: Node3D) -> void:
    _target = t

func add_shake(amount: float) -> void:
    _shake = clamp(_shake + amount, 0.0, 1.0)

func _process(dt: float) -> void:
    if _cam == null:
        _cam = get_node_or_null(cam_path) as Camera3D
        if _cam == null:
            return
    if _target == null or not is_instance_valid(_target):
        return

    var dist := float(Game.settings.get("camera_distance", 9.0))
    var h := float(Game.settings.get("camera_height", 2.5))
    var lag := float(Game.settings.get("camera_lag", 10.0))

    var forward := (-_target.global_transform.basis.z).normalized()
    var up := _target.global_transform.basis.y.normalized()

    # Position: classic chase cam.
    var desired_pos := _target.global_position - forward * dist + up * h
    global_position = Smooth.exp_smooth_v3(global_position, desired_pos, lag, dt)

    # Look: ahead of the nose for speed readability.
    var look_pos := _target.global_position + forward * 10.0
    var up_vec := (Vector3.UP * 0.85 + up * 0.15).normalized()
    look_at(look_pos, up_vec)

    # Speed-based FOV (cinematic speed feel).
    if _target.has_method("get_speed"):
        var sp = float(_target.get_speed())
        var fov_base = float(Game.settings.get("fov_base", 72.0))
        var fov_boost = float(Game.settings.get("fov_boost", 14.0))
        var fov_tgt = fov_base + clamp(sp / 240.0, 0.0, 1.0) * fov_boost
        _cam.fov = Smooth.exp_smooth(_cam.fov, fov_tgt, 7.0, dt)
    # Tiny camera shake (smoothed so it looks “cinematic”, not “broken”).
    _shake = max(_shake - dt * 1.6, 0.0)
    if _shake > 0.001:
        var shake_scale = float(Game.settings.get("shake_hit", 0.35))
        var jitter: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (0.22 * _shake * shake_scale)
        _cam_offset = Smooth.exp_smooth_v3(_cam_offset, jitter, 18.0, dt)
    else:
        _cam_offset = Smooth.exp_smooth_v3(_cam_offset, Vector3.ZERO, 18.0, dt)

    _cam.position = _cam_offset
