extends WorldComponentBase
class_name ForestComponent

func get_priority() -> int:
    return 70

func get_optional_params() -> Dictionary:
    return {
        # Forest Patch Controls
        "forest_patch_count": Game.settings.get("forest_patch_count", 26),
        "forest_patch_trees_per_patch": Game.settings.get("forest_patch_trees_per_patch", 200),
        "forest_patch_radius_min": Game.settings.get("forest_patch_radius_min", 180.0),
        "forest_patch_radius_max": Game.settings.get("forest_patch_radius_max", 520.0),
        "forest_patch_placement_attempts": Game.settings.get("forest_patch_placement_attempts", 50),
        "forest_patch_placement_buffer": Game.settings.get("forest_patch_placement_buffer", 250.0),
        
        # Random Tree Controls
        "random_tree_count": 500,  # TEMPORARY: Override to test random trees visibility
        "random_tree_clearance_buffer": Game.settings.get("random_tree_clearance_buffer", 30.0),
        "random_tree_slope_limit": Game.settings.get("random_tree_slope_limit", 34.0),
        "random_tree_placement_attempts": Game.settings.get("random_tree_placement_attempts", 10),
        
        # Settlement Tree Controls
        "settlement_tree_count_per_building": 2.0,  # TEMPORARY: Override to test settlement trees
        "urban_tree_buffer_distance": Game.settings.get("urban_tree_buffer_distance", 50.0),
        "park_tree_density": Game.settings.get("park_tree_density", 6),
        "roadside_tree_spacing": Game.settings.get("roadside_tree_spacing", 40.0),
        
        # Biome & Rendering Controls
        "forest_biome_tree_types": Game.settings.get("forest_biome_tree_types", {}),
        "use_external_tree_assets": Game.settings.get("use_external_tree_assets", true),
        "tree_lod_distance": Game.settings.get("tree_lod_distance", 200.0),
        "tree_max_instances_per_mesh": Game.settings.get("tree_max_instances_per_mesh", 8000),
        "tree_debug_metrics": Game.settings.get("tree_debug_metrics", true),
        
        # Legacy Backward Compatibility (deprecated)
        "pond_count": Game.settings.get("pond_count", 0),
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.prop_generator == null:
        push_error("ForestComponent: missing ctx/prop_generator")
        return

    var props_layer: Node3D = ctx.get_layer("Props")
    ctx.prop_generator.set_settlements(ctx.settlements)
    if ctx.biome_generator != null and ctx.prop_generator.has_method("set_biome_generator"):
        ctx.prop_generator.call("set_biome_generator", ctx.biome_generator)
    
    # DEBUG: Check Game.settings availability
    print("🔍 FOREST COMPONENT DEBUG - Game.settings check:")
    print("  - Game.settings exists: ", Game.settings != null)
    if Game.settings != null:
        print("  - random_tree_count from Game.settings: ", Game.settings.get("random_tree_count", "MISSING"))
    else:
        print("  - Game.settings is null!")
    
    var out: Dictionary = ctx.prop_generator.generate(props_layer, params, rng, ctx)
    var groups: Array = out.get("prop_lod_groups", [])
    if groups.size() > 0:
        ctx.prop_lod_groups.append_array(groups)
