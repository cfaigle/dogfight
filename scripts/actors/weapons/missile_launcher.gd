extends Node
@export var defs: Resource
# Keep as plain Array for maximum compatibility.
@export var hardpoint_paths: Array = []
@export var missile_scene: PackedScene
@export var owner_node: NodePath = NodePath("..")

var damage = 85.0
var speed = 260.0
var turn_rate = 4.5
var accel = 260.0
var life = 10.0
var lock_cone_deg = 12.0
var lock_time = 1.25
var cooldown = 1.0

var _t = 0.0
var _hp_index = 0

func _ready() -> void:
    # Avoid top-level nodes, initialize lists in ready.
    if hardpoint_paths.is_empty():
        hardpoint_paths = [NodePath("Hardpoints/Left"), NodePath("Hardpoints/Right")]
    if defs:
        _apply(defs.missile)

func apply_defs(defs: Resource, weapon_type: String) -> void:
    if defs and defs.has_method("get"):
        var weapon_data = defs.get(weapon_type)
        if weapon_data:
            _apply(weapon_data)

func _process(dt: float) -> void:
    _t = max(_t - dt, 0.0)

func can_fire() -> bool:
    return _t <= 0.0 and missile_scene != null and hardpoint_paths.size() > 0

func fire(target: Node, locked: bool) -> void:
    if not can_fire():
        return
    _t = cooldown

    var hp = get_node_or_null(hardpoint_paths[_hp_index])
    if hp == null and get_parent() != null:
        hp = get_parent().get_node_or_null(hardpoint_paths[_hp_index])
    _hp_index = (_hp_index + 1) % hardpoint_paths.size()
    if hp == null:
        return

    var m = missile_scene.instantiate()
    get_tree().current_scene.add_child(m)
    m.global_transform = (hp as Node3D).global_transform

    var owner = get_node_or_null(owner_node)
    if m.has_method("arm"):
        m.arm(owner, target, locked, {
            "damage": damage,
            "speed": speed,
            "turn_rate": turn_rate,
            "accel": accel,
            "life": life
        })


func _apply(d: Dictionary) -> void:
    damage = d.get("damage", damage)
    speed = d.get("speed", speed)
    turn_rate = d.get("turn_rate", turn_rate)
    accel = d.get("accel", accel)
    life = d.get("life", life)
    lock_cone_deg = d.get("lock_cone_deg", lock_cone_deg)
    lock_time = d.get("lock_time", lock_time)
    cooldown = d.get("cooldown", cooldown)
