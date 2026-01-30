@tool
class_name BuildingTemplateRegistry
extends Resource

# BUILDING TEMPLATE REGISTRY
# Manages and provides access to all building templates
# Author: Claude AI Assistant
# Version: 1.0

# Template storage
var _templates: Dictionary = {}  # template_name -> BuildingTemplateDefinition
var _category_index: Dictionary = {}  # category -> [template_names]
var _style_index: Dictionary = {}  # style -> [template_names]

# Template weights for probability-based selection
var _template_weights: Dictionary = {}  # template_name -> weight

# Initialize registry with default templates
func _init():
    _register_default_templates()

# Register a new template
func register_template(template: BuildingTemplateDefinition) -> bool:
    if not template.validate_template():
        push_error("Failed to validate template: %s" % template.template_name)
        return false
    
    var name = template.template_name
    if _templates.has(name):
        push_warning("Template '%s' already exists, overwriting" % name)
    
    _templates[name] = template
    
    # Update indices
    _append_to_dict_array(_category_index, template.template_category, name)
    _append_to_dict_array(_style_index, template.architectural_style, name)
    
    # Update weights
    _template_weights[name] = template.spawn_weight
    
    print("Registered template: %s" % name)
    return true

# Get template by name
func get_template(template_name: String) -> BuildingTemplateDefinition:
    return _templates.get(template_name, null)

# Get all templates in a category
func get_templates_by_category(category: String) -> Array[BuildingTemplateDefinition]:
    var template_names = _category_index.get(category, [])
    var result: Array[BuildingTemplateDefinition] = []
    for name in template_names:
        result.append(_templates[name])
    return result

# Get all templates with a specific style
func get_templates_by_style(style: String) -> Array[BuildingTemplateDefinition]:
    var template_names = _style_index.get(style, [])
    var result: Array[BuildingTemplateDefinition] = []
    for name in template_names:
        result.append(_templates[name])
    return result

# Get weighted random template for context
func get_weighted_random_template(category: String = "", biome: String = "", settlement_type: String = "") -> BuildingTemplateDefinition:
    var candidates = []
    var weights = []
    
    # Filter by criteria
    for template in _templates.values():
        # Category filter
        if not category.is_empty() and template.template_category != category:
            continue
        
        # Biome filter
        if not biome.is_empty() and not template.biome_requirements.is_empty() and biome not in template.biome_requirements:
            continue
        
        # Settlement filter
        if not settlement_type.is_empty() and not template.settlement_requirements.is_empty() and settlement_type not in template.settlement_requirements:
            continue
        
        candidates.append(template)
        weights.append(template.spawn_weight)
    
    if candidates.is_empty():
        return null
    
    # Weighted random selection
    var total_weight = 0.0
    for w in weights:
        total_weight += w
    
    var random = RandomNumberGenerator.new()
    var rand_val = random.randf() * total_weight
    var current_weight = 0.0
    
    for i in range(candidates.size()):
        current_weight += weights[i]
        if rand_val <= current_weight:
            return candidates[i]
    
    return candidates[0]  # fallback

# Get all registered templates
func get_all_templates() -> Array[BuildingTemplateDefinition]:
    return _templates.values()

# Get template count
func get_template_count() -> int:
    return _templates.size()

# Print registry statistics
func print_registry_stats():
    print("=== Building Template Registry ===")
    print("Total Templates: %d" % _templates.size())
    print("Categories: %s" % str(_category_index.keys()))
    print("Styles: %s" % str(_style_index.keys()))
    print("================================")

# Helper method to append to dictionary array
func _register_default_templates():
    # First, register template resources
    _register_template_resources()

    # Only create fallback templates if none were loaded from resources
    if _templates.size() == 0:
        # Create stone cottage template (fallback if resources not loaded)
        var stone_cottage = BuildingTemplateDefinition.new()
        stone_cottage.template_name = "stone_cottage_classic"
        stone_cottage.template_category = "residential"
        stone_cottage.template_description = "Classic rustic stone cottage with gabled roof"
        stone_cottage.template_tags = ["cottage", "stone", "rustic", "traditional"]
        stone_cottage.architectural_style = "stone_cottage"
        stone_cottage.base_dimensions = Vector3(6.0, 4.0, 5.0)
        stone_cottage.dimension_variation = Vector3(1.0, 0.5, 1.0)

        # Stone cottage specific configurations
        stone_cottage.wall_config.wall_thickness = 0.3
        stone_cottage.wall_config.wall_height = 4.0
        stone_cottage.wall_config.wall_material = "stone"
        stone_cottage.wall_config.has_rustic_variation = true

        stone_cottage.roof_config.roof_type = "gabled"
        stone_cottage.roof_config.roof_pitch = 40.0
        stone_cottage.roof_config.roof_material = "stone_tiles"
        stone_cottage.roof_config.has_chimney = true

        stone_cottage.window_config.window_style = "double_hung"
        stone_cottage.window_config.window_count = 4
        stone_cottage.window_config.window_size = Vector2(0.8, 1.2)

        stone_cottage.door_config.door_style = "wooden"
        stone_cottage.door_config.door_size = Vector2(0.9, 2.0)

        stone_cottage.detail_config.detail_intensity = 0.7
        stone_cottage.detail_config.has_wooden_beams = true
        stone_cottage.detail_config.has_stone_foundations = true

        stone_cottage.spawn_weight = 2.0
        stone_cottage.settlement_requirements = ["hamlet", "village"]

        register_template(stone_cottage)

        # Create thatched cottage variant
        var thatched_cottage = BuildingTemplateDefinition.new()
        thatched_cottage.template_name = "thatched_cottage"
        thatched_cottage.template_category = "residential"
        thatched_cottage.template_description = "Rural cottage with traditional thatched roof"
        thatched_cottage.template_tags = ["cottage", "thatched", "rural", "traditional"]
        thatched_cottage.architectural_style = "thatched_cottage"
        thatched_cottage.base_dimensions = Vector3(5.5, 3.5, 4.5)
        thatched_cottage.dimension_variation = Vector3(0.8, 0.4, 0.8)

        thatched_cottage.roof_config.roof_type = "thatched"
        thatched_cottage.roof_config.roof_pitch = 50.0  # steeper for thatch
        thatched_cottage.roof_config.roof_material = "thatch"
        thatched_cottage.roof_config.roof_color = Color(0.6, 0.4, 0.2)

        thatched_cottage.window_config.window_style = "casement"
        thatched_cottage.window_config.window_count = 3

        thatched_cottage.detail_config.detail_intensity = 0.8
        thatched_cottage.detail_config.has_wooden_beams = true

        thatched_cottage.spawn_weight = 1.5
        thatched_cottage.settlement_requirements = ["hamlet", "village"]

        register_template(thatched_cottage)

# Register template resources from .tres files
func _register_template_resources():
    # Factory template
    var factory_template = _safe_load_template("res://resources/building_templates/industrial_factory.tres")
    if factory_template:
        register_template(factory_template)

    # Castle template
    var castle_template = _safe_load_template("res://resources/building_templates/medieval_castle.tres")
    if castle_template:
        register_template(castle_template)

    # Stone cottage template
    var stone_cottage_resource = _safe_load_template("res://resources/building_templates/stone_cottage_classic.tres")
    if stone_cottage_resource:
        register_template(stone_cottage_resource)

    # Thatched cottage template
    var thatched_cottage_resource = _safe_load_template("res://resources/building_templates/thatched_cottage.tres")
    if thatched_cottage_resource:
        register_template(thatched_cottage_resource)

# Safely load a template resource with error handling
func _safe_load_template(path: String) -> BuildingTemplateDefinition:
    if not ResourceLoader.exists(path):
        print("⚠️ Template resource does not exist: %s" % path)
        return null

    var resource = load(path)
    if resource == null:
        print("❌ Failed to load template resource: %s" % path)
        return null

    if not resource is BuildingTemplateDefinition:
        print("❌ Template resource is not a BuildingTemplateDefinition: %s" % path)
        return null

    return resource

# Helper function to append to dictionary array
func _append_to_dict_array(dict: Dictionary, key: String, value):
    if not dict.has(key):
        dict[key] = []
    dict[key].append(value)