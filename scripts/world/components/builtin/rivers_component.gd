extends WorldComponentBase
class_name RiversComponent

func get_priority() -> int:
    return 40

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("RiversComponent: missing ctx/terrain_generator")
        return

    if ctx.rivers == null or ctx.rivers.is_empty():
        return

    var water_layer: Node3D = ctx.get_layer("Water")
    ctx.terrain_generator.build_rivers(water_layer, ctx.rivers, params, rng)
