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
        "stone_cottage", "stone_cabin", "thatched_cottage",
        "cottage", "rustic_cabin", "log_chalet", "timber_cabin",
        "factory", "industrial", "factory_building",
        "castle", "fortress", "castle_keep", "tower",
        "windmill", "blacksmith", "barn", "church", "cathedral",
        "manor", "mansion", "villa", "cottage", "cabin",
        "mill", "bakery", "inn", "tavern", "pub", "shop",
        "warehouse", "workshop", "foundry", "mill_factory",
        "fort", "keep", "bastion", "redoubt", "barracks",
        "cottage_small", "cottage_medium", "cottage_large",
        "house_victorian", "house_colonial", "house_tudor",
        "manor_house", "estate", "chateau", "villa_italian",
        "farmhouse", "homestead", "outbuilding", "stable",
        "gristmill", "sawmill", "oil_mill", "paper_mill",
        "tannery", "brewery", "distillery", "granary",
        "armory", "guard_house", "watchtower", "gatehouse"
    ]

    return building_type in template_types

# Get appropriate template name for building type
func get_template_for_building_type(building_type: String) -> String:
    match building_type:
        "stone_cottage", "stone_cabin", "cottage_small", "cottage_medium", "cottage_large", "cabin":
            return "stone_cottage_classic"
        "thatched_cottage":
            return "thatched_cottage"
        "cottage":
            # Randomly choose between cottage types
            var cottage_types = ["stone_cottage_classic", "thatched_cottage"]
            return cottage_types[randi() % cottage_types.size()]
        "rustic_cabin", "log_chalet", "timber_cabin", "cottage", "cabin":
            return "thatched_cottage"  # Use thatched as closest match
        "factory", "industrial", "factory_building", "warehouse", "workshop", "foundry", "mill_factory":
            return "industrial_factory"
        "castle", "fortress", "castle_keep", "fort", "keep", "bastion", "redoubt", "barracks":
            return "medieval_castle"
        "tower", "watchtower":
            # Use castle template for towers (has towers)
            return "medieval_castle"
        "windmill":
            # Use thatched cottage template as a base for windmill (will have special features)
            return "thatched_cottage"
        "blacksmith", "barn", "stable", "granary", "outbuilding":
            return "thatched_cottage"  # Use thatched as closest match for rural buildings
        "church", "cathedral", "monastery", "chapel":
            return "medieval_castle"  # Use castle template for religious buildings
        "mansion", "manor", "manor_house", "estate", "chateau", "villa", "villa_italian":
            return "stone_cottage_classic"  # Use stone cottage as base for manor houses
        "house_victorian", "house_colonial", "house_tudor", "victorian_mansion":
            return "stone_cottage_classic"  # Use stone cottage as base for houses
        "farmhouse", "homestead":
            return "thatched_cottage"  # Rural house template
        "mill", "gristmill", "sawmill", "oil_mill", "paper_mill":
            return "industrial_factory"  # Industrial template for mills
        "bakery", "inn", "tavern", "pub", "shop":
            return "stone_cottage_classic"  # Residential template for commercial buildings
        "tannery", "brewery", "distillery":
            return "industrial_factory"  # Industrial template
        "armory", "guard_house", "gatehouse":
            return "medieval_castle"  # Military/castle template
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