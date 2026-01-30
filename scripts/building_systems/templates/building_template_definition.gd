@tool
class_name BuildingTemplateDefinition
extends Resource

# ARCHITECTURAL TEMPLATE SYSTEM
# Defines reusable building templates with component-based architecture
# Author: Claude AI Assistant
# Version: 1.0

# Template metadata
@export var template_name: String
@export var template_category: String  # "residential", "commercial", "industrial", "rural"
@export var template_description: String
@export var template_tags: Array[String] = ["cottage", "stone", "rustic"]

# Base building parameters
@export var base_dimensions: Vector3 = Vector3(6.0, 4.0, 5.0)  # width, height, depth
@export var dimension_variation: Vector3 = Vector3(1.0, 0.5, 1.0)  # random variation range

# Architectural style
@export var architectural_style: String = "stone_cottage"

# Component configuration - Using Resources instead of custom classes
@export var wall_config: WallConfiguration
@export var roof_config: RoofConfiguration
@export var window_config: WindowConfiguration
@export var door_config: DoorConfiguration
@export var detail_config: DetailConfiguration

# Specialized component configurations for complex buildings
@export var industrial_config: IndustrialConfiguration
@export var castle_config: CastleConfiguration

# Material definitions
@export var material_definitions: MaterialDefinitions

# Layout configuration
@export var layout_type: String = "rectangular"  # "rectangular", "L_shaped", "T_shaped", "courtyard"
@export var layout_parameters: Dictionary = {}

# Special features
@export var has_chimney: bool = true
@export var has_porch: bool = false
@export var has_garage: bool = false
@export var has_basement: bool = false

# Probability settings for template selection
@export var spawn_weight: float = 1.0
@export var biome_requirements: Array[String] = []
@export var settlement_requirements: Array[String] = ["hamlet", "village"]

# Configuration classes are now in separate files to allow proper resource loading
# See: wall_configuration.gd, roof_configuration.gd, window_configuration.gd, etc.

# Initialize default configurations
func _init():
    if wall_config == null:
        wall_config = load("res://scripts/building_systems/templates/wall_configuration.gd").new()
    if roof_config == null:
        roof_config = load("res://scripts/building_systems/templates/roof_configuration.gd").new()
    if window_config == null:
        window_config = load("res://scripts/building_systems/templates/window_configuration.gd").new()
    if door_config == null:
        door_config = load("res://scripts/building_systems/templates/door_configuration.gd").new()
    if detail_config == null:
        detail_config = load("res://scripts/building_systems/templates/detail_configuration.gd").new()
    if industrial_config == null:
        industrial_config = load("res://scripts/building_systems/templates/industrial_configuration.gd").new()
    if castle_config == null:
        castle_config = load("res://scripts/building_systems/templates/castle_configuration.gd").new()
    if material_definitions == null:
        material_definitions = load("res://scripts/building_systems/templates/material_definitions.gd").new()

# Validate template configuration
func validate_template() -> bool:
    if template_name.is_empty():
        push_error("Template name cannot be empty")
        return false
    
    if base_dimensions.x <= 0 or base_dimensions.y <= 0 or base_dimensions.z <= 0:
        push_error("Base dimensions must be positive")
        return false
    
    return true

# Get template summary for debugging
func get_template_summary() -> String:
    var summary = "Template: %s\n" % template_name
    summary += "Category: %s\n" % template_category
    summary += "Style: %s\n" % architectural_style
    summary += "Dimensions: %.1fx%.1fx%.1f\n" % [base_dimensions.x, base_dimensions.y, base_dimensions.z]
    summary += "Roof: %s (%.1f°)\n" % [roof_config.roof_type, roof_config.roof_pitch]
    summary += "Windows: %d x %s\n" % [window_config.window_count, window_config.window_style]
    summary += "Doors: %d x %s\n" % [door_config.door_count, door_config.door_style]
    return summary