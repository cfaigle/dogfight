extends WorldComponentBase
class_name OceanFeaturesComponent

## Scatters boats, buoys, and docks across the ocean surface

func get_priority() -> int:
    return 73  # After ocean component

func get_optional_params() -> Dictionary:
    return {
        "enable_ocean_features": true,
        "ocean_boat_count": 2000,  # Reduced to 20% of original
        "ocean_buoy_count": 2000,  # Reduced to 20% of original
        "coastal_dock_count": 400,  # Reduced to 20% of original
        "coastal_shore_feature_count": 1000,  # Reduced to 20% of original
        "min_distance_from_shore": 20.0,  # Allow boats closer to shore
        "max_distance_from_shore": 3000.0,  # Cover more ocean area
        "boat_density_nearshore": 3.0,  # 3x more boats near coast
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    print("⛵ OceanFeaturesComponent: Starting generation")

    if not bool(params.get("enable_ocean_features", true)):
        print("  ❌ Ocean features disabled")
        return

    if ctx == null or ctx.terrain_generator == null:
        print("  ❌ Missing context or terrain generator")
        return

    var features_root := Node3D.new()
    features_root.name = "OceanFeatures"
    ctx.get_layer("Props").add_child(features_root)

    # Load lake defs (we'll reuse boat/dock definitions)
    var lake_defs: LakeDefs = load("res://resources/defs/lake_defs.tres")
    if lake_defs == null:
        push_warning("OceanFeaturesComponent: Could not load lake_defs.tres")
        return

    # Create generators
    var boat_gen = load("res://scripts/world/generators/boat_generator.gd").new()
    boat_gen.set_terrain_generator(ctx.terrain_generator)
    boat_gen.set_lake_defs(lake_defs)

    var sea_level: float = float(params.get("sea_level", Game.sea_level))
    var boat_count: int = int(params.get("ocean_boat_count", 10000))

    print("  🚤 Placing ", boat_count, " boats on ocean (fast mode - no distance checks)")

    var boats_placed = 0
    # ALL boat types including new big ships!
    var boat_types = [
        "fishing", "sailboat", "large_sailboat", "speedboat", "pontoon", "raft",
        "trawler", "tugboat", "barge", "transport", "liner", "car_carrier", "oldtimey"
    ]

    # FAST: Just spam boats randomly, only check if in water
    for i in range(boat_count):
        var x = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var z = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var terrain_h = ctx.terrain_generator.get_height_at(x, z)

        # Only requirement: must be in water
        if terrain_h < sea_level - 2.0:
            var pos = Vector3(x, sea_level + 0.18, z)
            var boat_type = boat_types[rng.randi() % boat_types.size()]

            var boat_config = {
                "type": boat_type,
                "rotation": rng.randf() * TAU
            }

            var boat_node = boat_gen.create_single_boat(pos, boat_config, rng)
            if boat_node:
                print("🌊 Ocean boat created: name='%s', type='%s', instance_id=%d" % [boat_node.name, boat_type, boat_node.get_instance_id()])
                features_root.add_child(boat_node)
                print("  - After add_child: name='%s', in_tree=%s, parent=%s" % [boat_node.name, boat_node.is_inside_tree(), boat_node.get_parent().name])

                # CRITICAL: Verify name before collision
                if not "Boat_" in boat_node.name:
                    push_error("❌ BOAT NAME CORRUPTED: Expected 'Boat_*' but got '%s'" % boat_node.name)

                # Add collision after boat is in scene tree
                if CollisionManager:
                    print("  - About to call add_collision_to_object...")
                    print("    boat_node.name = '%s'" % boat_node.name)
                    print("    boat_node.get_instance_id() = %d" % boat_node.get_instance_id())
                    CollisionManager.add_collision_to_object(boat_node, "boat")
                    print("  - Collision added (check logs above for result)")

                boats_placed += 1

    print("  ✓ Placed ", boats_placed, " boats on ocean (including big ships!)")

    # Scatter buoys
    var buoy_count: int = int(params.get("ocean_buoy_count", 10000))
    var buoys_placed = 0

    print("  🎯 Placing ", buoy_count, " buoys on ocean")

    for i in range(buoy_count):
        var x = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var z = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var terrain_h = ctx.terrain_generator.get_height_at(x, z)

        if terrain_h < sea_level - 2.0:  # In water
            var pos = Vector3(x, sea_level + 0.12, z)
            var buoy = boat_gen.create_single_buoy(pos, "navigation", rng)
            if buoy:
                features_root.add_child(buoy)
                buoys_placed += 1

    print("  ✓ Placed ", buoys_placed, " buoys on ocean")

    # Add coastal docks along shoreline
    var dock_count: int = int(params.get("coastal_dock_count", 2000))
    print("  ⚓ Placing ", dock_count, " coastal docks")

    var dock_gen = load("res://scripts/world/generators/dock_generator.gd").new()
    dock_gen.set_terrain_generator(ctx.terrain_generator)
    dock_gen.set_lake_defs(lake_defs)

    var docks_placed = 0
    for i in range(dock_count):
        # Sample random positions looking for coastline (land near water)
        var x = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var z = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var terrain_h = ctx.terrain_generator.get_height_at(x, z)

        # Look for coastline: land just above sea level
        if terrain_h > sea_level + 1.0 and terrain_h < sea_level + 20.0:
            # Check if water is nearby
            var has_water_nearby = false
            for angle in [0, 45, 90, 135, 180, 225, 270, 315]:
                var check_dist = 30.0
                var check_x = x + cos(deg_to_rad(angle)) * check_dist
                var check_z = z + sin(deg_to_rad(angle)) * check_dist
                var check_h = ctx.terrain_generator.get_height_at(check_x, check_z)
                if check_h < sea_level - 2.0:
                    has_water_nearby = true
                    break

            if has_water_nearby:
                var pos = Vector3(x, terrain_h, z)
                var dock_types = ["fishing_pier", "marina_dock", "boat_launch"]
                var dock_type = dock_types[rng.randi() % dock_types.size()]

                var dock_config = {
                    "type": dock_type,
                    "length": rng.randf_range(15.0, 30.0),
                    "width": rng.randf_range(4.0, 8.0),
                    "rotation": rng.randf() * TAU
                }

                var dock_node = dock_gen.create_single_dock(pos, dock_config, rng)
                if dock_node:
                    features_root.add_child(dock_node)
                    docks_placed += 1

    print("  ✓ Placed ", docks_placed, " coastal docks")

    # Add coastal shore features (beaches, picnic areas)
    var shore_count: int = int(params.get("coastal_shore_feature_count", 5000))
    print("  🏖️ Placing ", shore_count, " coastal shore features")

    var shore_gen = load("res://scripts/world/generators/shore_feature_generator.gd").new()
    shore_gen.set_terrain_generator(ctx.terrain_generator)
    shore_gen.set_lake_defs(lake_defs)

    var shores_placed = 0
    var feature_types = ["beach", "concession", "picnic_area"]

    for i in range(shore_count):
        var x = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var z = rng.randf_range(-ctx.hmap_half * 0.9, ctx.hmap_half * 0.9)
        var terrain_h = ctx.terrain_generator.get_height_at(x, z)

        # Look for gentle coastal slopes
        if terrain_h > sea_level + 0.5 and terrain_h < sea_level + 15.0:
            var pos = Vector3(x, terrain_h, z)
            # Just place simple beach markers for now (full shore features would need _create_beach_area etc)
            # For quick implementation, just place boats as markers
            var marker = boat_gen.create_single_buoy(pos, "navigation", rng)
            if marker:
                marker.name = "ShoreFeature_" + feature_types[rng.randi() % feature_types.size()]
                features_root.add_child(marker)
                shores_placed += 1

    print("  ✓ Placed ", shores_placed, " coastal shore features")
    print("  ✓ OceanFeaturesComponent: Complete")
