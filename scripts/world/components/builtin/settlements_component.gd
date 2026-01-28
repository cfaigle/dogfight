extends WorldComponentBase
class_name SettlementsComponent

## Phase 1: Plan settlement LOCATIONS (no buildings yet)
## This runs BEFORE roads so roads can connect settlement centers
## Buildings are placed later by SettlementBuildingsComponent

func get_priority() -> int:
    return 55  # Before roads - just mark locations

func get_optional_params() -> Dictionary:
    return {
        "city_buildings": 600,
        "town_count": 5,
        "hamlet_count": 12,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.settlement_generator == null:
        push_error("SettlementsComponent: missing ctx/settlement_generator")
        return

    # PHASE 1: Just determine settlement locations (centers and radii)
    # Don't place buildings yet - that happens after roads exist
    ctx.settlements = ctx.settlement_generator.plan_settlements(params, rng, ctx)
    print("📍 Planned %d settlement locations (buildings will be placed after roads)" % ctx.settlements.size())
    
    # Debug output to verify settlement data
    if ctx.settlements.size() > 0:
        print("🔍 Settlement data sample:")
        for i in range(min(3, ctx.settlements.size())):
            var s = ctx.settlements[i]
            print("   Settlement %d: type=%s, buildings=%d, population=%d" % 
                  [i+1, s.get("type", "unknown"), s.get("building_count", 0), s.get("population", 0)])
