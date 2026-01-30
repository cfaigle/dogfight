@tool
class_name UnifiedBuildingSystem
extends Resource

# UNIFIED BUILDING SYSTEM
# Combines parametric generation with template configurations for consistent quality
# Supports all scales from single huts to complex castles
# Author: Claude AI Assistant
# Version: 1.0

# Component registry for building components
var _component_registry: ComponentRegistry = null

# Template registry for building configurations
var _template_registry: BuildingTemplateRegistry = null

# Template-parametric integration
var _integration_system: TemplateParametricIntegration = null

# Enhanced template generator
var _enhanced_generator: RefCounted = null

func _init():
    _initialize_systems()

# Initialize all subsystems
func _initialize_systems():
    _component_registry = ComponentRegistry.new()
    _template_registry = BuildingTemplateRegistry.new()
    _integration_system = TemplateParametricIntegration.new(_template_registry)
    _enhanced_generator = preload("res://scripts/building_systems/enhanced_template_generator.gd").new(_template_registry, _component_registry)

    # Register parametric components
    _component_registry.register_component("wall", WallComponent)
    _component_registry.register_component("window", WindowComponent)
    _component_registry.register_component("roof", RoofComponent)
    _component_registry.register_component("detail", DetailComponent)

    print("🏗️ Unified Building System initialized")

# Generate building from template name
func generate_building_from_template(template_name: String, plot: Dictionary, seed_value: int = 0) -> MeshInstance3D:
    var template = _template_registry.get_template(template_name)
    if template == null:
        print("❌ Template not found: %s" % template_name)
        return null

    # Use the enhanced template generator to create the building with proper components
    var building_node = _enhanced_generator.generate_building_from_template(template_name, plot, seed_value)

    if building_node and building_node.mesh:
        return building_node
    else:
        print("❌ Failed to generate building from template: %s" % template_name)
        return null

# Generate building using parametric system with template enhancements
func generate_parametric_building_with_template(template_name: String, building_type: String,
                                             width: float, depth: float, height: float,
                                             floors: int, quality_level: int = 2) -> Mesh:
    var template = _template_registry.get_template(template_name)
    if template == null:
        print("❌ Template not found: %s" % template_name)
        # Fall back to pure parametric generation
        var parametric_system = BuildingParametricSystem.new()
        return parametric_system.create_parametric_building(building_type, "ww2_european", width, depth, height, floors, quality_level)

    # Create a temporary plot for the enhanced generator
    var plot = {
        "lot_width": width,
        "lot_depth": depth,
        "height_category": "low" if floors <= 1 else ("medium" if floors <= 2 else "tall")
    }

    # Use the enhanced template generator for better quality
    var building_node = _enhanced_generator.generate_building_from_template(template_name, plot, 0)
    if building_node and building_node.mesh:
        return building_node.mesh
    else:
        # Fall back to parametric system enhanced with template details
        var parametric_system = BuildingParametricSystem.new()
        var base_mesh = parametric_system.create_parametric_building(
            building_type,
            template.architectural_style,
            width,
            depth,
            height,
            floors,
            quality_level
        )

        # Enhance with template-specific details
        var enhanced_mesh = _integration_system.enhance_parametric_with_template_details(base_mesh, template_name, {
            "width": width,
            "depth": depth,
            "height": height
        })

        return enhanced_mesh

# Generate building using the most appropriate method based on template availability
func generate_adaptive_building(building_type: String, plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
    # First, try to find an appropriate template for this building type
    var template_name = _integration_system.get_template_for_building_type(building_type)
    
    if template_name != "":
        # Use template-based generation
        var building = generate_building_from_template(template_name, plot, rng.seed)
        if building:
            return building
    else:
        # Fall back to parametric generation with style matching
        return _generate_parametric_building_adaptive(building_type, plot, rng)
    
    # Ultimate fallback to simple parametric
    return _generate_parametric_building_adaptive("residential", plot, rng)

# Internal method to generate parametric building with adaptive style selection
func _generate_parametric_building_adaptive(building_type: String, plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
    var parametric_system = BuildingParametricSystem.new()
    
    # Calculate dimensions based on plot
    var width = max(plot.lot_width * 0.8, 4.0)
    var depth = max(plot.lot_depth * 0.8, 4.0)
    
    var building_height = 0.0
    var floors = 1
    
    match plot.height_category:
        "tall":
            building_height = rng.randf_range(18.0, 36.0)
            floors = int(building_height / 4.0)
        "medium":
            building_height = rng.randf_range(9.0, 15.0)
            floors = int(building_height / 4.0)
        "low":
            building_height = rng.randf_range(3.0, 6.0)
            floors = max(1, int(building_height / 4.0))
    
    # Select style based on plot characteristics
    var style = _select_appropriate_style(plot, building_type, rng)
    
    # Generate the parametric building
    var mesh = parametric_system.create_parametric_building(
        building_type,
        style,
        width,
        depth,
        building_height,
        floors,
        2  # quality level
    )
    
    if mesh == null:
        print("⚠️ Failed to create parametric building for type: %s, style: %s" % [building_type, style])
        return null
    
    # Create mesh instance
    var building = MeshInstance3D.new()
    building.mesh = mesh
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    
    return building

# Select appropriate style based on plot characteristics
func _select_appropriate_style(plot: Dictionary, building_type: String, rng: RandomNumberGenerator) -> String:
    match plot.density_class:
        "urban_core":
            var urban_styles = ["american_art_deco", "industrial_modern", "ww2_european", "victorian_mansion"]
            return urban_styles[rng.randi() % urban_styles.size()]
        "urban":
            var urban_styles = ["american_art_deco", "ww2_european", "industrial_modern", "victorian_mansion"]
            return urban_styles[rng.randi() % urban_styles.size()]
        "suburban":
            var sub_styles = ["ww2_european", "american_art_deco", "stone_cottage", "timber_cabin", "white_stucco_house"]
            return sub_styles[rng.randi() % sub_styles.size()]
        "rural":
            var rural_styles = ["ww2_european", "industrial_modern", "stone_cottage", "timber_cabin", "log_chalet", "barn", "windmill", "blacksmith"]
            return rural_styles[rng.randi() % rural_styles.size()]
        _:
            var default_styles = ["ww2_european", "american_art_deco", "industrial_modern"]
            return default_styles[rng.randi() % default_styles.size()]

# Get template registry for external access
func get_template_registry() -> BuildingTemplateRegistry:
    return _template_registry

# Get component registry for external access
func get_component_registry() -> ComponentRegistry:
    return _component_registry

# Get system statistics for debugging
func get_system_stats() -> Dictionary:
    var template_stats = _integration_system.get_template_stats()
    return {
        "template_count": template_stats.get("total_templates", 0),
        "registered_components": _component_registry.get_component_names(),
        "component_count": _component_registry.get_component_names().size()
    }