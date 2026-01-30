@tool
class_name TemplateParametricIntegration
extends RefCounted

# INTEGRATION LAYER BETWEEN TEMPLATE SYSTEM AND PARAMETRIC SYSTEM
# Allows template-based buildings to be used seamlessly with existing parametric building system
# Author: Claude AI Assistant
# Version: 1.0

# Template registry
var template_registry: BuildingTemplateRegistry

# Initialize with template registry
func _init(registry: BuildingTemplateRegistry = null):
    template_registry = registry if registry else BuildingTemplateRegistry.new()

# Convert template to parametric building format
func create_parametric_from_template(template_name: String, plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var template = template_registry.get_template(template_name)
    if template == null:
        push_error("Template not found: %s" % template_name)
        return null
    
    # Use template generator to create mesh
    var generator = BuildingTemplateGenerator.new(template_registry)
    var building_node = generator.generate_building(template_name, plot, rng.seed)
    
    if building_node and building_node.mesh:
        return building_node.mesh
    else:
        return null

# Check if a building type should use template system
func should_use_template_system(building_type: String) -> bool:
    var template_types = [
        # Original types
        "stone_cottage", "stone_cabin", "thatched_cottage",
        "cottage", "rustic_cabin", "log_chalet", "timber_cabin",
        "factory", "industrial", "factory_building",
        "castle", "fortress", "castle_keep", "tower",
        "windmill", "blacksmith", "barn", "church", "cathedral",
        "manor", "mansion", "villa", "cabin",
        "mill", "bakery", "inn", "tavern", "pub", "shop",
        "warehouse", "workshop", "foundry", "mill_factory",
        "fort", "keep", "bastion", "redoubt", "barracks",
        "cottage_small", "cottage_medium", "cottage_large",
        "house_victorian", "house_colonial", "house_tudor",
        "manor_house", "estate", "chateau", "villa_italian",
        "farmhouse", "homestead", "outbuilding", "stable",
        "gristmill", "sawmill", "oil_mill", "paper_mill",
        "tannery", "brewery", "distillery", "granary",
        "armory", "guard_house", "watchtower", "gatehouse",
        # Additional specific types from settlement generator
        "medieval_hut", "timber_cabin", "blacksmith", "windmill",
        "castle_keep", "market_stall", "monastery", "fjord_house",
        "white_stucco_house", "stone_farmhouse", "log_chalet",
        "church", "barn", "victorian_mansion", "train_station",
        "lighthouse", "power_station", "gas_station", "trailer_park",
        "modular_home", "school", "warehouse", "sawmill", "oil_mill",
        "paper_mill", "sauna_building", "viking_longhouse",
        "fishing_hut", "shepherd_hut", "grange", "farm_outbuilding",
        "miller_house", "weaver_house", "potter_house", "carpenter_house",
        "priest_house", "merchant_house", "noble_house", "knight_house",
        "servant_quarters", "stable_master_house", "gamekeeper_house",
        "forester_house", "mason_house", "roofer_house", "plasterer_house",
        "wheelwright_house", "blacksmith_house", "baker_house",
        "butcher_house", "tanner_house", "weaver_house", "miller_house",
        "inn_keeper_house", "tavern_keeper_house", "priest_house",
        "bishop_house", "abbot_house", "prior_house", "monk_house",
        "novice_house", "lay_brother_house", "kitchen_garden",
        "herb_garden", "vegetable_garden", "fruit_orchard", "olive_grove",
        "vineyard", "beehives", "chicken_coop", "pig_pen", "goat_pen",
        "sheep_fold", "cattle_shed", "horse_stable", "oxen_shed",
        "dovecote", "rabbit_hutch", "duck_pond", "fish_pond",
        "grain_store", "hay_loft", "tool_shed", "wood_shed", "coal_shed",
        "dairy", "brew_house", "larder", "pantry", "cellar", "wine_cellar",
        "root_cellar", "apple_store", "potato_store", "onion_store",
        "grain_bin", "flour_mill", "linseed_oil_mill", "walnut_oil_mill",
        "apple_juice_press", "grape_wine_press", "hop_dryer", "malting_house",
        "wool_scouring", "fulling_mill", "tanning_pit", "leather_workshop",
        "shoe_workshop", "harness_workshop", "saddle_workshop",
        "cart_workshop", "wagon_workshop", "plow_workshop",
        "harrow_workshop", "scythe_workshop", "sickle_workshop",
        "axe_workshop", "hoe_workshop", "spade_workshop", "rake_workshop",
        "pitchfork_workshop", "shovel_workshop", "bucket_workshop",
        "barrel_workshop", "keg_workshop", "cask_workshop", "tank_workshop",
        "pottery_kiln", "clay_pit", "brick_kiln", "lime_kiln", "charcoal_kiln",
        "charcoal_pit", "ash_pit", "potash_pit", "salt_pit", "sand_pit",
        "gravel_pit", "stone_quarry", "limestone_quarry", "sandstone_quarry",
        "granite_quarry", "marble_quarry", "slate_quarry", "clay_pit",
        "peat_cutting", "peat_drying", "peat_storage", "firewood_storage",
        "timber_storage", "lumber_storage", "log_storage", "branch_storage",
        "twig_storage", "leaf_storage", "bark_storage", "sap_collection",
        "resin_collection", "turpentine_collection", "tar_collection",
        "pitch_collection", "charcoal_collection", "ash_collection",
        "potash_collection", "salt_collection", "water_collection",
        "rainwater_collection", "spring_collection", "well", "cistern",
        "water_tank", "water_tower", "windmill_water_pump", "water_wheel",
        "treadmill", "crank_wheel", "gear_system", "pulley_system",
        "lever_system", "counterweight_system", "balance_system",
        "screw_system", "cam_system", "ratchet_system", "pawl_system",
        "flywheel_system", "governor_system", "speed_control", "power_transmission"
    ]

    return building_type in template_types

# Get appropriate template name for building type
func get_template_for_building_type(building_type: String) -> String:
    match building_type:
        "stone_cottage", "stone_cabin", "cottage_small", "cottage_medium", "cottage_large", "cabin", "medieval_hut", "timber_cabin", "fjord_house", "white_stucco_house", "stone_farmhouse", "log_chalet", "fishing_hut", "shepherd_hut", "miller_house", "weaver_house", "potter_house", "carpenter_house", "priest_house", "merchant_house", "noble_house", "knight_house", "servant_quarters", "stable_master_house", "gamekeeper_house", "forester_house", "mason_house", "roofer_house", "plasterer_house", "wheelwright_house", "blacksmith_house", "baker_house", "butcher_house", "tanner_house", "weaver_house", "miller_house", "inn_keeper_house", "tavern_keeper_house", "bishop_house", "abbot_house", "prior_house", "monk_house", "novice_house", "lay_brother_house", "farmhouse", "homestead", "house_victorian", "house_colonial", "house_tudor", "victorian_mansion", "trailer_park", "modular_home", "school", "sauna_building", "viking_longhouse", "grange", "farm_outbuilding":
            return "stone_cottage_classic"
        "thatched_cottage":
            return "thatched_cottage"
        "cottage":
            # Randomly choose between cottage types
            var cottage_types = ["stone_cottage_classic", "thatched_cottage"]
            return cottage_types[randi() % cottage_types.size()]
        "rustic_cabin", "log_chalet", "timber_cabin", "cottage", "cabin":
            return "thatched_cottage"  # Use thatched as closest match
        "factory", "industrial", "factory_building", "warehouse", "workshop", "foundry", "mill_factory", "power_station", "gas_station", "sawmill", "oil_mill", "paper_mill", "brew_house", "tannery", "brewery", "distillery", "malting_house", "wool_scouring", "fulling_mill", "tanning_pit", "leather_workshop", "shoe_workshop", "harness_workshop", "saddle_workshop", "cart_workshop", "wagon_workshop", "plow_workshop", "harrow_workshop", "scythe_workshop", "sickle_workshop", "axe_workshop", "hoe_workshop", "spade_workshop", "rake_workshop", "pitchfork_workshop", "shovel_workshop", "bucket_workshop", "barrel_workshop", "keg_workshop", "cask_workshop", "tank_workshop", "pottery_kiln", "brick_kiln", "lime_kiln", "charcoal_kiln", "train_station", "lighthouse":
            return "industrial_factory"
        "castle", "fortress", "castle_keep", "fort", "keep", "bastion", "redoubt", "barracks", "armory", "guard_house", "gatehouse", "watchtower", "monastery", "church", "cathedral", "kitchen_garden", "herb_garden", "vegetable_garden", "fruit_orchard", "olive_grove", "vineyard", "beehives", "chicken_coop", "pig_pen", "goat_pen", "sheep_fold", "cattle_shed", "horse_stable", "oxen_shed", "dovecote", "rabbit_hutch", "duck_pond", "fish_pond", "grain_store", "hay_loft", "tool_shed", "wood_shed", "coal_shed", "dairy", "larder", "pantry", "cellar", "wine_cellar", "root_cellar", "apple_store", "potato_store", "onion_store", "grain_bin", "flour_mill", "linseed_oil_mill", "walnut_oil_mill", "apple_juice_press", "grape_wine_press", "hop_dryer", "bishop_house", "abbot_house", "prior_house", "monk_house", "novice_house", "lay_brother_house":
            return "medieval_castle"
        "windmill":
            # Use thatched cottage template as a base for windmill (will have special features)
            return "thatched_cottage"
        "blacksmith", "barn", "stable", "granary", "outbuilding", "market_stall", "barn", "blacksmith_house", "baker_house", "butcher_house", "tanner_house", "weaver_house", "miller_house", "inn_keeper_house", "tavern_keeper_house", "priest_house":
            return "thatched_cottage"  # Use thatched as closest match for rural buildings
        "mansion", "manor", "manor_house", "estate", "chateau", "villa", "villa_italian":
            return "stone_cottage_classic"  # Use stone cottage as base for manor houses
        "mill", "gristmill", "sawmill", "oil_mill", "paper_mill":
            return "industrial_factory"  # Industrial template for mills
        "bakery", "inn", "tavern", "pub", "shop":
            return "stone_cottage_classic"  # Residential template for commercial buildings
        "stone_quarry", "limestone_quarry", "sandstone_quarry", "granite_quarry", "marble_quarry", "slate_quarry", "clay_pit", "peat_cutting", "peat_drying", "peat_storage", "firewood_storage", "timber_storage", "lumber_storage", "log_storage", "branch_storage", "twig_storage", "leaf_storage", "bark_storage", "sap_collection", "resin_collection", "turpentine_collection", "tar_collection", "pitch_collection", "charcoal_collection", "ash_collection", "potash_collection", "salt_pit", "sand_pit", "gravel_pit":
            return "industrial_factory"  # Industrial template for resource extraction
        "water_collection", "rainwater_collection", "spring_collection", "well", "cistern", "water_tank", "water_tower", "windmill_water_pump", "water_wheel", "treadmill", "crank_wheel", "gear_system", "pulley_system", "lever_system", "counterweight_system", "balance_system", "screw_system", "cam_system", "ratchet_system", "pawl_system", "flywheel_system", "governor_system", "speed_control", "power_transmission":
            return "industrial_factory"  # Industrial template for mechanical systems
        _:
            return ""

# Enhance parametric building with template details
func enhance_parametric_with_template_details(
    parametric_mesh: Mesh, 
    template_name: String, 
    dimensions: Dictionary
) -> Mesh:
    var template = template_registry.get_template(template_name)
    if template == null:
        return parametric_mesh
    
    # This would add template-specific details to an existing parametric mesh
    # For now, just return the original mesh
    # In a full implementation, this could add things like:
    # - Better window geometry
    # - Detailed door frames  
    # - Chimney placement
    # - Roof textures and materials
    
    return parametric_mesh

# Register template integration with existing parametric system
func integrate_with_parametric_system(parametric_system: BuildingParametricSystem):
    # This would hook into the parametric system to use templates when appropriate
    # For now, we'll just ensure the template registry is accessible
    pass

# Get template statistics for debugging
func get_template_stats() -> Dictionary:
    return {
        "total_templates": template_registry.get_template_count(),
        "available_templates": _get_template_names()
    }

func _get_template_names() -> Array[String]:
    var names: Array[String] = []
    for template in template_registry.get_all_templates():
        names.append(template.template_name)
    return names