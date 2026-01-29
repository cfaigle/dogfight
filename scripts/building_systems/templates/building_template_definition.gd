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

# Component configuration
@export var wall_config: WallConfiguration
@export var roof_config: RoofConfiguration  
@export var window_config: WindowConfiguration
@export var door_config: DoorConfiguration
@export var detail_config: DetailConfiguration

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

# Sub-configuration classes
@tool
class WallConfiguration:
	@export var wall_thickness: float = 0.25
	@export var wall_height: float = 4.0
	@export var wall_material: String = "stone"
	@export var wall_texture_scale: Vector2 = Vector2(1.0, 1.0)
	@export var has_rustic_variation: bool = true
	@export var rustic_offset_range: float = 0.1

@tool
class RoofConfiguration:
	@export var roof_type: String = "gabled"  # "gabled", "hipped", "thatched", "flat"
	@export var roof_pitch: float = 40.0  # degrees
	@export var roof_overhang: float = 0.3
	@export var roof_material: String = "stone_tiles"
	@export var roof_color: Color = Color(0.4, 0.3, 0.2)
	@export var has_chimney: bool = true
	@export var chimney_position: Vector2 = Vector2(0.3, 0.2)  # relative to building center

@tool
class WindowConfiguration:
	@export var window_style: String = "double_hung"  # "double_hung", "casement", "bay", "punched"
	@export var window_count: int = 4
	@export var window_size: Vector2 = Vector2(0.8, 1.2)
	@export var window_material: String = "wood_frame"
	@export var window_distribution: String = "symmetric"  # "symmetric", "random", "clustered"
	@export var has_window_sills: bool = true
	@export var window_sill_depth: float = 0.1

@tool
class DoorConfiguration:
	@export var door_style: String = "wooden"  # "wooden", "double", "arched", "modern"
	@export var door_count: int = 1
	@export var door_size: Vector2 = Vector2(0.9, 2.0)
	@export var door_material: String = "oak"
	@export var door_position: Vector2 = Vector2(0.0, 0.0)  # relative to front wall center
	@export var has_door_frame: bool = true
	@export var door_frame_width: float = 0.15

@tool
class DetailConfiguration:
	@export var detail_intensity: float = 0.7  # 0.0 = minimal, 1.0 = ornate
	@export var detail_scale: float = 1.0
	@export var has_wooden_beams: bool = true
	@export var has_stone_foundations: bool = true
	@export var foundation_height: float = 0.3
	@export var has_guttering: bool = false
	@export var has_garden_elements: bool = false

@tool
class MaterialDefinitions:
	@export var wall_material: StandardMaterial3D
	@export var roof_material: StandardMaterial3D
	@export var window_material: StandardMaterial3D
	@export var door_material: StandardMaterial3D
	@export var detail_material: StandardMaterial3D
	
	# Create default materials if not set
	func _init():
		if wall_material == null:
			wall_material = _create_stone_material()
		if roof_material == null:
			roof_material = _create_roof_material()
		if window_material == null:
			window_material = _create_glass_material()
		if door_material == null:
			door_material = _create_wood_material()
		if detail_material == null:
			detail_material = _create_detail_material()
	
	func _create_stone_material() -> StandardMaterial3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.55, 0.45)
		mat.roughness = 0.95
		mat.metallic = 0.0
		mat.normal_scale = 0.3
		return mat
	
	func _create_roof_material() -> StandardMaterial3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.2, 0.15)
		mat.roughness = 0.9
		mat.metallic = 0.0
		return mat
	
	func _create_glass_material() -> StandardMaterial3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.8, 0.9)
		mat.roughness = 0.1
		mat.metallic = 0.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.alpha_scissor_threshold = 0.1
		return mat
	
	func _create_wood_material() -> StandardMaterial3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.3, 0.2)
		mat.roughness = 0.8
		mat.metallic = 0.0
		return mat
	
	func _create_detail_material() -> StandardMaterial3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.25, 0.2)
		mat.roughness = 0.85
		mat.metallic = 0.0
		return mat

# Initialize default configurations
func _init():
	if wall_config == null:
		wall_config = WallConfiguration.new()
	if roof_config == null:
		roof_config = RoofConfiguration.new()
	if window_config == null:
		window_config = WindowConfiguration.new()
	if door_config == null:
		door_config = DoorConfiguration.new()
	if detail_config == null:
		detail_config = DetailConfiguration.new()
	if material_definitions == null:
		material_definitions = MaterialDefinitions.new()

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