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

# Check if a building type should use template system using unified registry
func should_use_template_system(building_type: String) -> bool:
    # Try to load unified type registry if available
    var unified_registry_path = "res://scripts/building_systems/registry/building_type_registry.gd"
    if ResourceLoader.exists(unified_registry_path):
        var UnifiedBuildingTypeRegistry = load(unified_registry_path)
        if UnifiedBuildingTypeRegistry:
            var type_registry = UnifiedBuildingTypeRegistry.new()
            return type_registry.should_use_template_system(building_type)
    
    # Fallback to legacy logic for backward compatibility
    var template_types = [
        "stone_cottage", "stone_cabin", "thatched_cottage", "cottage",
        "factory", "industrial", "factory_building", "warehouse",
        "castle", "fortress", "castle_keep", "house_victorian", "house_colonial"
    ]
    return building_type in template_types

# Get appropriate template name for building type using unified registry
func get_template_for_building_type(building_type: String) -> String:
    # Try to load unified type registry if available
    var unified_registry_path = "res://scripts/building_systems/registry/building_type_registry.gd"
    if ResourceLoader.exists(unified_registry_path):
        var UnifiedBuildingTypeRegistry = load(unified_registry_path)
        if UnifiedBuildingTypeRegistry:
            var type_registry = UnifiedBuildingTypeRegistry.new()
            var template_name = type_registry.get_template_for_building_type(building_type)
            if template_name != "":
                return template_name
    
    # Fallback to legacy mapping for backward compatibility
    match building_type:
        "stone_cottage", "stone_cabin", "cottage", "cabin", "farmhouse", "house_victorian", "house_colonial":
            return "stone_cottage_classic"
        "thatched_cottage":
            return "thatched_cottage"
        "factory", "industrial", "factory_building", "warehouse", "workshop", "foundry", "train_station":
            return "industrial_factory"
        "castle", "fortress", "castle_keep":
            return "medieval_castle"
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