extends Node
class_name BoatLODManager

## Manages LOD updates for thousands of boats
## Only updates boats near player for performance

@export var update_interval: float = 0.5  # Update every 0.5 seconds
@export var lod_distance_close: float = 200.0  # Full detail + movement
@export var lod_distance_medium: float = 500.0  # Simplified movement
@export var lod_distance_far: float = 1000.0  # Static

var _boats: Array[Node3D] = []
var _player: Node3D = null
var _update_timer: float = 0.0
var _current_batch_index: int = 0
var _batch_size: int = 100  # Update 100 boats per frame

func _ready() -> void:
    # Find player
    await get_tree().process_frame
    _player = Game.player if Game.has("player") else null

    if _player == null:
        # Try to find player in scene
        var players = get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            _player = players[0]

func register_boat(boat: Node3D) -> void:
    _boats.append(boat)

func register_boats(boats: Array) -> void:
    for boat in boats:
        if boat is Node3D:
            _boats.append(boat)

func _process(delta: float) -> void:
    if _player == null or _boats.is_empty():
        return

    _update_timer += delta

    if _update_timer >= update_interval:
        _update_timer = 0.0
        _update_batch()

func _update_batch() -> void:
    if _boats.is_empty():
        return

    var player_pos = _player.global_position
    var end_index = mini(_current_batch_index + _batch_size, _boats.size())

    for i in range(_current_batch_index, end_index):
        var boat = _boats[i]
        if not is_instance_valid(boat):
            continue

        var distance = boat.global_position.distance_to(player_pos)

        # Update LOD on movement controller
        for child in boat.get_children():
            if child is SmartBoatMovement:
                child.update_lod(distance)
                break

    # Move to next batch
    _current_batch_index = end_index
    if _current_batch_index >= _boats.size():
        _current_batch_index = 0

func clear_boats() -> void:
    _boats.clear()
    _current_batch_index = 0

func get_boat_count() -> int:
    return _boats.size()

func get_stats() -> Dictionary:
    var active_count = 0
    var static_count = 0

    for boat in _boats:
        if not is_instance_valid(boat):
            continue

        for child in boat.get_children():
            if child is SmartBoatMovement:
                if child._is_active:
                    active_count += 1
                else:
                    static_count += 1
                break

    return {
        "total_boats": _boats.size(),
        "active_boats": active_count,
        "static_boats": static_count
    }
