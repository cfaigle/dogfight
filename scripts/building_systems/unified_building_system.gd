@tool
class_name UnifiedBuildingSystem
extends Resource

# Import required building system classes
const BuildingTypeRegistry = preload("res://scripts/building_systems/registry/building_type_registry.gd")
const ComponentRegistry = preload("res://scripts/building_systems/components/component_registry.gd")
const BuildingTemplateRegistry = preload("res://scripts/building_systems/templates/building_template_registry.gd")
const TemplateParametricIntegration = preload("res://scripts/building_systems/templates/template_parametric_integration.gd")

# UNIFIED BUILDING SYSTEM
# Combines parametric generation with template configurations for consistent quality
# Supports all scales from single huts to complex castles
# Author: Claude AI Assistant
# Version: 1.0

# Component registry for building components
var _component_registry: ComponentRegistry = null

# Template registry for building configurations
var _template_registry: BuildingTemplateRegistry = null

# Unified building type registry for consistent classification
var _type_registry = null

# Template-parametric integration
var _integration_system: TemplateParametricIntegration = null

# Enhanced template generator
var _enhanced_generator: RefCounted = null

# Building type tracking
var _building_counts: Dictionary = {}

func _init():
    _initialize_systems()

# Initialize all subsystems
func _initialize_systems():
    _component_registry = ComponentRegistry.new()
    _template_registry = BuildingTemplateRegistry.new()
    _type_registry = BuildingTypeRegistry.get_instance()
    _integration_system = TemplateParametricIntegration.new(_template_registry)
    _enhanced_generator = preload("res://scripts/building_systems/enhanced_template_generator.gd").new(_template_registry, _component_registry)

    # Register parametric components
    _component_registry.register_component("wall", WallComponent)
    _component_registry.register_component("window", WindowComponent)
    _component_registry.register_component("roof", RoofComponent)
    _component_registry.register_component("detail", DetailComponent)

    # Validate unified registry
    _type_registry.validate_registry()
    _type_registry.print_registry_stats()

    print("🏗️ Unified Building System initialized with unified type registry")

# Generate building from template name
func generate_building_from_template(template_name: String, plot: Dictionary, seed_value: int = 0) -> MeshInstance3D:
    var template = _template_registry.get_template(template_name)
    if template == null:
        # print("❌ Template not found: %s" % template_name)
        return null

    # Use the enhanced template generator to create the building with proper components
    var building_node = _enhanced_generator.generate_building_from_template(template_name, plot, seed_value)

    if building_node and building_node.mesh:
        # Set proper name for the building
        building_node.name = "Building_%s_%d" % [template_name, _building_counts.get(template_name, 0)]
        
        # Track this building creation - use the actual building type from plot if available
        var building_type = plot.get("building_type", template_name)
        _track_building_creation(building_type)
        return building_node
    else:
        print("❌ Failed to generate building from template: %s" % template_name)
        return null

# Track building creation by type
func _track_building_creation(template_name: String):
    if _building_counts.has(template_name):
        _building_counts[template_name] += 1
    else:
        _building_counts[template_name] = 1

# Get building creation statistics
func get_building_statistics() -> Dictionary:
    return _building_counts.duplicate()

# Generate building using parametric system with template enhancements
func generate_parametric_building_with_template(template_name: String, building_type: String,
                                             width: float, depth: float, height: float,
                                             floors: int, quality_level: int = 2) -> Mesh:
    var template = _template_registry.get_template(template_name)
    if template == null:
        # print("❌ Template not found: %s" % template_name)
        # Fall back to pure parametric generation
        var parametric_system = BuildingParametricSystem.new()
        var mesh = parametric_system.create_parametric_building(building_type, "ww2_european", width, depth, height, floors, quality_level)
        _track_building_creation(building_type + "_fallback")
        return mesh

    # Create a temporary plot for the enhanced generator
    var plot = {
        "lot_width": width,
        "lot_depth": depth,
        "height_category": "low" if floors <= 1 else ("medium" if floors <= 2 else "tall")
    }

    # Use the enhanced template generator for better quality
    var building_node = _enhanced_generator.generate_building_from_template(template_name, plot, 0)
    if building_node and building_node.mesh:
        _track_building_creation(building_type)
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

        _track_building_creation(building_type + "_enhanced")
        return enhanced_mesh

# Generate building using the most appropriate method based on unified type registry
func generate_adaptive_building(building_type: String, plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Use unified type registry for consistent building type resolution
    var type_data = _type_registry.get_building_config(building_type)
    
    # If building type not found, try to get appropriate type for density
    if type_data == null:
        var density_class = plot.get("density_class", "rural")
        building_type = _type_registry.get_building_type_for_density(density_class, rng)
        type_data = _type_registry.get_building_config(building_type)
        print("🔄 Resolved unknown building type to: %s (density: %s)" % [building_type, density_class])

    # Update plot with resolved building type
    plot["building_type"] = building_type
    
    # Check if this building type should use template system
    if type_data.preferred_template != "":
        var template_name = type_data.preferred_template
        if template_name != "":
            # Use template-based generation
            var building = generate_building_from_template(template_name, plot, rng.seed)
            if building:
                _track_building_creation(building_type)
                return building
            else:
                # print("⚠️ Template generation failed for %s, falling back to parametric" % building_type)
                pass
        else:
            print("⚠️ Building type %s marked for template use but has no template" % building_type)

    # Check for special geometry buildings (based on building type patterns)
    var special_types = ["windmill", "radio_tower", "grain_silo", "corn_feeder", "lighthouse", "barn", "blacksmith", "church", "castle"]
    if building_type in special_types:
        var building = _generate_special_geometry_building(building_type, plot, rng)
        if building:
            _track_building_creation(building_type)
            return building
        else:
            print("⚠️ Special geometry generation failed for %s, falling back to parametric" % building_type)

    # Fall back to parametric generation with style based on building type
    var parametric_style = "ww2_european"  # Default style
    
    # Select style based on building characteristics
    match building_type:
        "church", "cathedral", "temple":
            parametric_style = "medieval_church"
        "castle", "fortress", "tower":
            parametric_style = "medieval_castle"
        "windmill", "radio_tower", "grain_silo", "corn_feeder", "barn":
            parametric_style = "rural_barn"
        "factory", "industrial":
            parametric_style = "industrial_modern"
    var building = _generate_parametric_building_with_style(building_type, parametric_style, plot, rng)
    if building:
        _track_building_creation(building_type)
        return building

    # Ultimate fallback to simple residential parametric
    print("❌ All generation methods failed for %s, using ultimate fallback" % building_type)
    building = _generate_parametric_building_with_style("residential", "stone_cottage", plot, rng)
    if building:
        _track_building_creation("residential_fallback")
        return building
    
    return null

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
    building.name = "AdaptiveParametric_%s_%s_%d" % [building_type, style, _building_counts.get(building_type, 0)]
    building.set_meta("building_type", building_type)
    building.set_meta("building_category", "building")
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
            var rural_styles = ["ww2_european", "industrial_modern", "stone_cottage", "timber_cabin", "log_chalet", "barn", "windmill", "radio_tower", "blacksmith"]
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

# Get unified type registry for external access
func get_type_registry():
    return _type_registry

# Get system statistics for debugging
func get_system_stats() -> Dictionary:
    var template_stats = _integration_system.get_template_stats()
    return {
        "template_count": template_stats.get("total_templates", 0),
        "registered_components": _component_registry.get_component_names(),
        "component_count": _component_registry.get_component_names().size(),
        "building_types": _type_registry.get_all_building_types().size(),
        "building_counts": _building_counts
    }

# Generate special geometry buildings
func _generate_special_geometry_building(building_type: String, plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Import organic building placement component for special geometry functions
    var organic_component = preload("res://scripts/world/components/builtin/organic_building_placement_component.gd").new()

    # Call the special building geometry functions
    var mesh = null
    match building_type:
        "windmill":
            mesh = organic_component._create_windmill_geometry(plot, rng)
        "radio_tower":
            mesh = organic_component._create_radio_tower_geometry(plot, rng)
        "grain_silo":
            mesh = organic_component._create_grain_silo_geometry(plot, rng)
        "corn_feeder":
            mesh = organic_component._create_corn_feeder_geometry(plot, rng)
        "blacksmith":
            mesh = organic_component._create_blacksmith_geometry(plot, rng)
        "barn":
            mesh = organic_component._create_barn_geometry(plot, rng)
        "church":
            mesh = organic_component._create_church_geometry(plot, rng)
        "lighthouse":
            mesh = organic_component._create_lighthouse_geometry(plot, rng)
        _:
            print("⚠️ Unknown special geometry building type: %s" % building_type)
            return null

    if mesh == null:
        return null

    # Create mesh instance
    var building = MeshInstance3D.new()
    building.name = "Building_%s_%d" % [building_type, _building_counts.get(building_type, 0)]
    building.mesh = mesh
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    building.set_meta("building_type", building_type)
    building.set_meta("building_category", "building")

    # Transfer metadata from mesh to building node (for towers)
    if building_type == "radio_tower" and mesh.has_meta("tower_height"):
        building.set_meta("tower_height", mesh.get_meta("tower_height"))
        building.set_meta("tower_base_width", mesh.get_meta("tower_base_width"))
        building.set_meta("tower_top_width", mesh.get_meta("tower_top_width"))

    return building

# Generate parametric building with specific style
func _generate_parametric_building_with_style(building_type: String, parametric_style: String, plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
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

    # Generate the parametric building with specified style
    var mesh = parametric_system.create_parametric_building(
        building_type,
        parametric_style,
        width,
        depth,
        building_height,
        floors,
        2  # quality level
    )

    if mesh == null:
        print("⚠️ Failed to create parametric building for type: %s, style: %s" % [building_type, parametric_style])
        return null

    # Create mesh instance
    var building = MeshInstance3D.new()
    building.set_meta("name", "Building_%s_%d" % [building_type, _building_counts.get(building_type, 0)])
    building.set_meta("building_type", building_type)
    building.set_meta("building_category", "building")
    building.mesh = mesh
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    return building

# Print building statistics
func print_building_statistics():
    print("\n=== BUILDING CREATION STATISTICS ===")
    if _building_counts.is_empty():
        print("No buildings have been created yet.")
    else:
        for building_type in _building_counts.keys():
            print("   🏠 %s: %d" % [building_type, _building_counts[building_type]])
    print("==================================\n")