extends WorldComponentBase
class_name RoadNetworkComponent

## Generates trunk roads and highways between settlements.

func get_priority() -> int:
    return 56  # After settlement locations (55), before buildings (65)

func get_optional_params() -> Dictionary:
    return {
        "enable_roads": true,
        "road_width": 18.0,
        "road_smooth": true,
        "allow_bridges": true,
        "road_density": 1.0,
        "highway_density": 0.35,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_roads", true)):
        return
    if ctx == null:
        push_error("RoadNetworkComponent: missing ctx")
        return
    if ctx.road_network_generator == null:
        return
    if ctx.settlements.is_empty():
        return

    var gen: RefCounted = ctx.road_network_generator
    if not gen.has_method("generate"):
        push_error("RoadNetworkComponent: road_network_generator missing generate")
        return

    ctx.roads = gen.call("generate", ctx, params, rng)
