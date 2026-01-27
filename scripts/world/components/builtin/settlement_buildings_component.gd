extends WorldComponentBase
class_name SettlementBuildingsComponent

## Phase 2: Place buildings ALONG existing roads
## This runs AFTER all roads exist (regional + inter-settlement + settlement streets)
## Buildings are placed with road frontage, proper spacing, no overlaps

func get_priority() -> int:
    return 65  # After all roads (55-57) and zoning (58)

func get_dependencies() -> Array[String]:
    return ["regional_roads", "road_network", "settlement_roads"]

func get_optional_params() -> Dictionary:
    return {
        "city_buildings": 600,
        "enable_parametric_buildings": true,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.settlement_generator == null:
        push_error("SettlementBuildingsComponent: missing ctx/settlement_generator")
        return

    if ctx.settlements.is_empty():
        push_warning("SettlementBuildingsComponent: no settlements planned")
        return

    var infra_layer: Node3D = ctx.get_layer("Infrastructure")

    # Now place buildings using the existing generate() method
    # Settlement locations already exist in ctx.settlements from earlier phase
    var out: Dictionary = ctx.settlement_generator.generate(infra_layer, params, rng, ctx.parametric_system, ctx)

    # Update settlement metadata with building info
    var built_settlements: Array = out.get("settlements", [])
    if built_settlements.size() > 0:
        # Merge building data back into planned settlements
        for i in range(min(ctx.settlements.size(), built_settlements.size())):
            if ctx.settlements[i] is Dictionary and built_settlements[i] is Dictionary:
                ctx.settlements[i].merge(built_settlements[i])

    var groups: Array = out.get("prop_lod_groups", [])
    if groups.size() > 0:
        ctx.prop_lod_groups.append_array(groups)

    print("🏘️ Placed buildings in %d settlements along existing roads" % built_settlements.size())
