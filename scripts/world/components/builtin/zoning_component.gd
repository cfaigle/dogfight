extends WorldComponentBase
class_name ZoningComponent

## Adds simple zoning information to settlements (core/suburb/industry/farm centers).

func get_priority() -> int:
    return 58  # After all roads (55-57), before buildings (65)

func get_optional_params() -> Dictionary:
    return {
        "zoning_enabled": true,
        "zoning_grid_size": 280.0,
        "zoning_core_scale": 0.35,
        "zoning_suburb_scale": 1.0,
        "zoning_industry_scale": 0.75,
        "zoning_farm_scale": 1.6,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("zoning_enabled", true)):
        return
    if ctx == null:
        push_error("ZoningComponent: missing ctx")
        return
    if ctx.zoning_generator == null:
        # Optional feature
        return
    if ctx.settlements.is_empty():
        return

    var gen: RefCounted = ctx.zoning_generator
    if not gen.has_method("generate"):
        push_error("ZoningComponent: zoning_generator missing generate")
        return

    gen.call("generate", ctx, params, rng)
