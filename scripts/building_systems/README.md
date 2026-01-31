# Unified Building System Documentation

## Overview

The unified building system combines parametric generation with template configurations for consistent quality across all building scales. It supports everything from single huts to complex castles with proper normals, materials, and architectural coherence.

## Architecture

### Dual-System Approach

The system integrates two complementary approaches:
1. **Parametric System**: Component-based generation with walls, windows, roofs, and details
2. **Template System**: Configuration-driven buildings with detailed architectural parameters

```
scripts/building_systems/
├── unified_building_system.gd       # Main orchestrator and integration layer
├── enhanced_template_generator.gd   # High-quality template-based generation
├── parametric_buildings.gd          # Original parametric system
├── components/
│   ├── building_component_base.gd   # Base class for all components
│   ├── component_registry.gd        # Component discovery system
│   ├── wall_component.gd            # Wall generation
│   ├── window_component.gd          # Window generation
│   ├── roof_component.gd            # Roof generation
│   └── detail_component.gd          # Architectural details
├── templates/
│   ├── building_template_definition.gd  # Template configuration
│   ├── building_template_generator.gd   # Basic template generation
│   └── template_parametric_integration.gd # Integration layer
└── definitions/
    ├── building_definition_base.gd  # Building definition resource
    └── building_variant.gd          # Variant configuration resource
```

## Core Concepts

### Unified System Components

The unified system combines two approaches for maximum flexibility:

1. **Enhanced Template Generator**: Uses the component system to create high-quality buildings from templates with proper normals and materials
2. **Parametric System**: Original component-based generation with walls, windows, roofs, and details
3. **Template System**: Configuration-driven buildings with detailed architectural parameters
4. **Integration Layer**: Seamlessly connects templates with parametric generation

### Building Templates

Building templates are resource files (.tres) that define detailed architectural configurations. They specify:
- Building type (residential, commercial, industrial, rural)
- Architectural style (stone_cottage, thatched_cottage, medieval_castle, industrial_factory)
- Dimensions and variations
- Component configurations (walls, windows, roofs, details)
- Material definitions
- Special features (chimneys, porches, towers)

### Materials

The system automatically creates PBR materials based on template configurations:
- Wall materials (stone, brick, stucco, wood)
- Roof materials (tiles, shingles, thatch, flat)
- Window materials (glass with transparency)
- Door materials (wood, metal)
- Detail materials (trim, foundations, beams)

## How To Use The System

### Generating Buildings

**Using the unified system:**

```gdscript
# Initialize the unified system
var unified_system = UnifiedBuildingSystem.new()

# Generate from template
var building_node = unified_system.generate_building_from_template(
    "stone_cottage_classic",
    plot_dict,
    seed_value
)

# Generate parametric with template enhancements
var mesh = unified_system.generate_parametric_building_with_template(
    "stone_cottage_classic",
    "residential",
    width, depth, height,
    floors,
    quality_level
)

# Adaptive generation (chooses best method)
var adaptive_building = unified_system.generate_adaptive_building(
    building_type,
    plot_dict,
    rng
)
```

### Adding a New Building Template

**Example: Creating a Tudor-style cottage**

1. Create a template resource file:

```gdscript
# resources/building_templates/tudor_cottage.tres
[gd_resource type="Resource" script_class="BuildingTemplateDefinition" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/building_systems/templates/building_template_definition.gd" id="1_tudor"]

[sub_resource type="StandardMaterial3D" id="TimberFrameMaterial"]
albedo_color = Color(0.5, 0.3, 0.15, 1)
roughness = 0.8
metallic = 0.0

[sub_resource type="StandardMaterial3D" id="PlasterMaterial"]
albedo_color = Color(0.9, 0.85, 0.75, 1)
roughness = 0.9
metallic = 0.0

[resource]
script = ExtResource("1_tudor")
template_name = "tudor_cottage"
template_category = "residential"
template_description = "Traditional Tudor-style cottage with timber framing"
template_tags = Array[String](["cottage", "tudor", "timber", "traditional"])
base_dimensions = Vector3(7, 5, 6)
dimension_variation = Vector3(1.2, 0.6, 1.2)
architectural_style = "tudor"
layout_type = "rectangular"
layout_parameters = {}
has_chimney = true
has_porch = true
has_garage = false
has_basement = false
spawn_weight = 1.0
biome_requirements = Array[String]([])
settlement_requirements = Array[String](["hamlet", "village"])

[resource.sub_resource.wall_config]
wall_thickness = 0.25
wall_height = 5.0
wall_material = "timber_frame"
wall_texture_scale = Vector2(1, 1)
has_rustic_variation = true
rustic_offset_range = 0.1

[resource.sub_resource.roof_config]
roof_type = "gabled"
roof_pitch = 45.0
roof_overhang = 0.4
roof_material = "thatch"
roof_color = Color(0.6, 0.4, 0.2, 1)
has_chimney = true
chimney_position = Vector2(0.4, 0.3)

[resource.sub_resource.window_config]
window_style = "diamond_leaded"
window_count = 6
window_size = Vector2(0.9, 1.1)
window_material = "lead_glass"
window_distribution = "symmetric"
has_window_sills = true
window_sill_depth = 0.1

[resource.sub_resource.door_config]
door_style = "wooden"
door_count = 1
door_size = Vector2(0.8, 1.9)
door_material = "oak"
door_position = Vector2(0, 0)
has_door_frame = true
door_frame_width = 0.15

[resource.sub_resource.detail_config]
detail_intensity = 0.9
detail_scale = 1.0
has_wooden_beams = true
has_stone_foundations = true
foundation_height = 0.4
has_guttering = false
has_garden_elements = true

[resource.sub_resource.material_definitions]
wall_material = SubResource("TimberFrameMaterial")
roof_material = SubResource("PlasterMaterial")
window_material = SubResource("WindowMaterial")
door_material = SubResource("DoorMaterial")
detail_material = SubResource("DetailMaterial")
```

2. Register the template in the system:
The template will be automatically loaded and registered when the system initializes.

### Adding a New Building Component

**Example: Creating a custom window style**

1. Create a new component file:

```gdscript
# scripts/building_systems/components/window_gothic_component.gd
class_name WindowGothicComponent
extends BuildingComponentBase

func get_required_params() -> Array[String]:
    return ["footprint", "height", "floors"]

func get_optional_params() -> Dictionary:
    return {
        "floor_height": 3.0,
        "window_width": 1.5,
        "window_height": 3.0,
        "pointed_arch_height": 0.8
    }

func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    var footprint: PackedVector2Array = params["footprint"]
    var height: float = params["height"]
    var floors: int = params["floors"]

    # Your custom window generation logic here
    for floor in range(floors):
        var y = floor * params["floor_height"]
        _create_gothic_window(st, Vector3(0, y, 0), params["window_width"],
                              params["window_height"])

func _create_gothic_window(st: SurfaceTool, center: Vector3, width: float,
                           height: float) -> void:
    # Create pointed arch window with custom geometry
    # Use add_quad() helper from base class for faces
    pass
```

2. The component will be automatically available in the unified system.

## Component API Reference

### BuildingComponentBase

Base class for all building components.

#### Methods

**`generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void`**
- Main generation method. Override in subclasses.
- **Parameters:**
  - `st`: SurfaceTool to add geometry to
  - `params`: Dictionary of generation parameters
  - `materials`: Dictionary of materials keyed by zone name

**`get_required_params() -> Array[String]`**
- Returns array of required parameter names
- Component will error if these are missing

**`get_optional_params() -> Dictionary`**
- Returns dictionary of optional parameters with defaults
- Format: `{"param_name": default_value}`

**`validate_params(params: Dictionary) -> bool`**
- Validates parameters before generation
- Automatically adds optional params with defaults
- Returns false if required params are missing

**`add_quad(st: SurfaceTool, v0, v1, v2, v3: Vector3, uv0, uv1, uv2, uv3: Vector2)`**
- Helper to add a quad with proper winding and normals
- Vertices should be in counter-clockwise order when viewed from outside

**`calculate_wall_uv(position: Vector3, wall_start, wall_end: Vector3, height: float, texture_scale: float) -> Vector2`**
- Helper to calculate UV coordinates for wall segments
- Handles texture tiling based on wall dimensions

### ComponentRegistry

Manages component registration and instantiation.

#### Methods

**`register_component(name: String, component_class: GDScript) -> void`**
- Register a component class under a given name

**`get_component(name: String) -> BuildingComponentBase`**
- Get a new instance of a registered component
- Returns null if not found

**`has_component(name: String) -> bool`**
- Check if a component is registered

**`get_component_names() -> Array[String]`**
- Get list of all registered component names

### BuildingTemplateDefinition

Resource defining a detailed building template.

#### Properties

- `template_name: String` - Unique identifier for the template
- `template_category: String` - "residential", "commercial", "industrial", "rural"
- `template_description: String` - Human-readable description
- `template_tags: Array[String]` - Tags for filtering and selection
- `base_dimensions: Vector3` - (width, height, depth) base dimensions
- `dimension_variation: Vector3` - Random variation ranges
- `architectural_style: String` - Style identifier for material selection

#### Configuration Sections

- `wall_config`: Wall properties (thickness, height, material)
- `roof_config`: Roof properties (type, pitch, overhang, material)
- `window_config`: Window properties (style, count, size, distribution)
- `door_config`: Door properties (style, count, size, position)
- `detail_config`: Architectural details (intensity, scale, features)
- `material_definitions`: PBR material definitions

#### Methods

**`validate_template() -> bool`**
- Validates template configuration for completeness

**`get_template_summary() -> String`**
- Returns human-readable summary of template properties

## Style Rules

The system includes multiple architectural styles:

### ww2_european
- Roof systems: gabled, hipped, mansard
- Wall profiles: historic (thick walls)
- Window systems: double_hung, casement, bay
- Details: ornate (cornices, quoins, string courses)
- Colors: brick red, stone gray, stucco beige

### american_art_deco
- Roof systems: flat, mansard
- Wall profiles: modern (thin walls)
- Window systems: punched, casement
- Details: subtle (minimal ornamentation)
- Colors: pastel colors, earth tones

### industrial_modern
- Roof systems: flat, gabled
- Wall profiles: industrial (medium walls)
- Window systems: punched, bay
- Details: minimal (no ornamentation)
- Colors: concrete gray, metal gray, brick orange

### stone_cottage
- Roof systems: gabled, thatched
- Wall profiles: historic (thick stone walls)
- Window systems: double_hung, casement
- Details: ornate (wooden beams, stone foundations)
- Colors: stone grays, earth tones

## Performance Considerations

### LOD System Integration

The unified system respects the game's LOD system:
- **LOD 0 (Near)**: Full detail with windows, details, dormers
- **LOD 1 (Mid)**: Simplified geometry, fewer details
- **LOD 2 (Far)**: Basic shapes only

### Quality Levels

The system supports different quality levels:
- **Level 0 (High)**: Maximum detail with all features
- **Level 1 (Medium)**: Reduced detail for performance
- **Level 2 (Low)**: Minimal geometry for distant buildings

### Memory Usage

The unified system optimizes memory usage:
- Template reuse reduces redundant geometry
- Component-based generation enables efficient batching
- Quality scaling adapts to performance requirements

## Troubleshooting

### Buildings Not Appearing

1. Check that `ctx.unified_building_system` is properly initialized in WorldContext
2. Verify template files exist and are correctly formatted
3. Check console for error messages from template validation

### Geometry Issues (Missing Faces, Inverted Normals)

1. The unified system uses proper component-based generation with correct normals
2. Enhanced template generator ensures proper surface normals
3. All components use the `add_quad()` helper for consistent winding

### Materials Not Applied

1. Verify template material definitions are properly configured
2. Check that material dictionaries are passed to component.generate()
3. Ensure ArrayMesh.surface_set_material() is called after surface addition

## Benefits of the Unified System

### Consistent Quality
- All building types use the same high-quality generation methods
- Proper normals and UV mapping across all scales
- Architectural coherence from huts to castles

### Scalability
- Supports tiny huts to massive castles
- Hierarchical component generation for complex structures
- Quality scaling based on distance and importance

### Maintainability
- Single codebase for all building types
- Easy to add new architectural styles
- Consistent API across different generation methods

## Examples

See the included building templates for complete examples:
- `resources/building_templates/stone_cottage_classic.tres`
- `resources/building_templates/thatched_cottage.tres`
- `resources/building_templates/medieval_castle.tres`
- `resources/building_templates/industrial_factory.tres`

## License

This unified building system is part of the Dogfight: 1940 game codebase.

## Credits

Developed by Claude AI Assistant as part of the Dogfight: 1940 project.
Unified architecture designed for consistent quality across all building scales.
