extends WorldComponentBase
class_name ForestComponent

func get_priority() -> int:
    return 70

func get_optional_params() -> Dictionary:
    return {
        "tree_count": 8000,
        "forest_patches": 26,
        "pond_count": 18,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.prop_generator == null:
        push_error("ForestComponent: missing ctx/prop_generator")
        return

    var props_layer: Node3D = ctx.get_layer("Props")
    ctx.prop_generator.set_settlements(ctx.settlements)
    if ctx.biome_generator != null and ctx.prop_generator.has_method("set_biome_generator"):
        ctx.prop_generator.call("set_biome_generator", ctx.biome_generator)
    var out: Dictionary = ctx.prop_generator.generate(props_layer, params, rng, ctx)
    var groups: Array = out.get("prop_lod_groups", [])
    if groups.size() > 0:
        ctx.prop_lod_groups.append_array(groups)
