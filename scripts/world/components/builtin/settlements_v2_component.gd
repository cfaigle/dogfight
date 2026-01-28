extends WorldComponentBase
class_name SettlementsV2Component

## Modern settlement generation using WorldPlanner + SettlementPlanner
## Replaces old circular settlement logic with terrain-aware boundaries

func get_priority() -> int:
    return 55  # Before roads (56)

func get_dependencies() -> Array[String]:
    return ["heightmap", "lakes", "biomes"]

func get_optional_params() -> Dictionary:
    return {
        "enable_settlements_v2": true,
        "city_count": 3,           # Increased from 1 to 3
        "town_count": 12,          # Increased from 6 to 12
        "hamlet_count": 24,        # Increased from 12 to 24
        "city_buildings_min": 200,  # Reduced min for more variety
        "city_buildings_max": 1200, # Increased max for larger cities
        "town_buildings_min": 80,   # Reduced min for smaller towns
        "town_buildings_max": 600,  # Increased max for larger towns
        "hamlet_buildings_min": 20,  # Reduced min for tiny hamlets
        "hamlet_buildings_max": 150, # Increased max for larger hamlets
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_settlements_v2", true)):
        return

    if ctx == null or ctx.terrain_generator == null:
        push_error("SettlementsV2Component: missing ctx or terrain_generator")
        return

    print("🏙️  SettlementsV2Component: Starting terrain-aware settlement generation...")

    # PHASE 1: World Planning (WHERE to build)
    var world_planner := WorldPlanner.new()
    var world_plan: Dictionary = world_planner.plan_world(ctx.terrain_generator, params, rng)

    var planned_settlements: Array = world_plan.settlements
    print("   📍 World planner selected %d settlement locations" % planned_settlements.size())

    # PHASE 2: Per-Settlement Planning (HOW to build each)
    var final_settlements: Array = []

    for planned_settlement in planned_settlements:
        if not planned_settlement is Dictionary:
            continue

        var s_type: String = planned_settlement.get("type", "hamlet")
        var s_center: Vector3 = planned_settlement.get("center", Vector3.ZERO)
        var s_radius: float = planned_settlement.get("radius", 200.0)
        var s_population: int = planned_settlement.get("population", 100)

        # Create terrain-aware plan for this settlement
        var settlement_planner := SettlementPlanner.new()
        var settlement_plan: Dictionary = settlement_planner.plan_settlement(
            s_center, s_type, s_radius, ctx.terrain_generator
        )

        # Calculate building count based on settlement type and population
        var building_count: int = 0
        if s_type == "city":
            building_count = rng.randi_range(int(params.get("city_buildings_min", 400)), int(params.get("city_buildings_max", 800)))
        elif s_type == "town":
            building_count = rng.randi_range(int(params.get("town_buildings_min", 150)), int(params.get("town_buildings_max", 350)))
        else:  # hamlet
            building_count = rng.randi_range(int(params.get("hamlet_buildings_min", 30)), int(params.get("hamlet_buildings_max", 80)))
        
        # Store complete settlement data
        var settlement_data := {
            "type": s_type,
            "center": s_center,
            "radius": s_radius,
            "population": s_population,
            "building_count": building_count,
            "boundary": settlement_plan.boundary,  # Terrain-aware polygon!
            "valid_area": settlement_plan.valid_area,
            "zones": settlement_plan.zones,
            "roads": settlement_plan.roads,  # Internal road network
            "stats": settlement_plan.stats
        }

        final_settlements.append(settlement_data)

    # PHASE 3: Build settlement structures (buildings + internal roads)
    var settlements_root := Node3D.new()
    settlements_root.name = "Settlements"
    ctx.get_layer("Props").add_child(settlements_root)

    # Setup building style mixer (mixes parametric + 27 styles)
    var parametric_system: RefCounted = ctx.parametric_system
    var building_style_defs: BuildingStyleDefs = preload("res://scripts/world/defs/building_style_defs.gd").new()
    building_style_defs.ensure_defaults()

    var style_mixer := BuildingStyleMixer.new(parametric_system, building_style_defs)

    for settlement in final_settlements:
        _build_settlement(settlements_root, settlement, style_mixer, params, rng)

    # Store settlements for other components
    ctx.settlements = final_settlements
    ctx.set_data("settlements", final_settlements)

    # Debug output to verify settlement data
    print("✅ SettlementsV2Component: Built %d settlements with terrain-aware boundaries" % final_settlements.size())
    if final_settlements.size() > 0:
        print("   🔍 Settlement data verification:")
        for settlement in final_settlements:
            print("     %s: pop=%d, bldgs=%d, area=%.0fm²" % 
                  [settlement.get("type", "unknown"), 
                   settlement.get("population", 0),
                   settlement.get("building_count", 0),
                   settlement.get("valid_area", 0)])


## Build actual structures for a settlement
func _build_settlement(parent: Node3D, settlement: Dictionary, style_mixer: BuildingStyleMixer, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var s_type: String = settlement.get("type", "hamlet")
    var center: Vector3 = settlement.get("center", Vector3.ZERO)
    var zones: Dictionary = settlement.get("zones", {})

    var settlement_node := Node3D.new()
    settlement_node.name = "%s_%d" % [s_type, rng.randi()]
    parent.add_child(settlement_node)

    print("   🏗️  Building %s with %d zones" % [s_type, zones.size()])

    # Determine building counts based on type
    var building_count: int = 0
    match s_type:
        "city":
            building_count = rng.randi_range(
                int(params.get("city_buildings_min", 400)),
                int(params.get("city_buildings_max", 800))
            )
        "town":
            building_count = rng.randi_range(
                int(params.get("town_buildings_min", 150)),
                int(params.get("town_buildings_max", 350))
            )
        "hamlet":
            building_count = rng.randi_range(
                int(params.get("hamlet_buildings_min", 30)),
                int(params.get("hamlet_buildings_max", 80))
            )

    # Place buildings in zones
    var buildings_placed: int = 0

    for zone_name in zones.keys():
        var zone_plots: Array = zones[zone_name]
        if zone_plots.is_empty():
            continue

        # Calculate buildings for this zone (proportional to plot count)
        var total_plots: int = 0
        for z in zones.values():
            if z is Array:
                total_plots += z.size()

        var zone_building_count: int = int(float(building_count) * float(zone_plots.size()) / float(maxi(1, total_plots)))

        # Place buildings
        for i in range(mini(zone_building_count, zone_plots.size())):
            var plot: Vector3 = zone_plots[i]

            # Determine if this is a landmark building
            var is_landmark: bool = false
            if zone_name == "downtown" or zone_name == "town_center":
                is_landmark = (i < 3) or (rng.randf() < 0.15)  # First 3 or 15% chance

            # Get building from mixer (mixed parametric + styles)
            var building_data: Dictionary = style_mixer.get_next_building(zone_name, is_landmark, rng)

            # Safety check: ensure we have valid building data
            if not building_data.has("mesh") or not building_data.has("material"):
                print("⚠️ Invalid building data for zone ", zone_name, ": ", building_data)
                continue

            # Create building instance
            var building := MeshInstance3D.new()
            building.mesh = building_data.mesh
            building.material_override = building_data.material

            # Position and orient
            var width: float = building_data.width
            var depth: float = building_data.depth
            var height: float = building_data.height

            var yaw: float = rng.randf_range(-PI, PI)
            var basis := Basis(Vector3.UP, yaw)
            basis = basis.scaled(Vector3(width, height, depth))

            building.transform = Transform3D(basis, Vector3(plot.x, plot.y + height * 0.5, plot.z))
            building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

            settlement_node.add_child(building)
            buildings_placed += 1

    print("      ✅ Placed %d buildings (%d parametric, %d styled)" % [buildings_placed, buildings_placed / 5, buildings_placed * 4 / 5])

    # TODO: Build internal roads from settlement.roads
