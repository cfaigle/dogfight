extends WorldComponentBase
class_name OceanComponent

func get_priority() -> int:
    return 10

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("OceanComponent: missing ctx/terrain_generator")
        return

    var water_layer: Node3D = ctx.get_layer("Water")
    ctx.terrain_generator.build_ocean(water_layer, params, rng)
