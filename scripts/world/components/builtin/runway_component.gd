extends WorldComponentBase
class_name RunwayComponent

func get_priority() -> int:
    return 30

func get_optional_params() -> Dictionary:
    return {
        "runway_len": 900.0,
        "runway_w": 80.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("RunwayComponent: missing ctx/terrain_generator")
        return

    var infra_layer: Node3D = ctx.get_layer("Infrastructure")
    ctx.runway_spawn = ctx.terrain_generator.build_runway(infra_layer, params, rng)
