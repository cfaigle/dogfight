# Parametric Building System Documentation

## Overview

The parametric building system generates infinite building variety from mathematical parameters and style rules. It's designed to be modular and extensible, allowing other AIs or developers to add new building components and types without modifying core code.

## Architecture

### Component-Based Design

The system uses a component-based architecture where each building element (walls, windows, roofs, details) is a separate, self-contained component that can be developed and tested independently.

```
scripts/building_systems/
├── parametric_buildings.gd          # Main orchestrator
├── components/
│   ├── building_component_base.gd   # Base class for all components
│   ├── component_registry.gd        # Component discovery system
│   ├── wall_component.gd            # Wall generation
│   ├── window_component.gd          # Window generation
│   ├── roof_component.gd            # Roof generation
│   └── detail_component.gd          # Architectural details
└── definitions/
    ├── building_definition_base.gd  # Building definition resource
    └── building_variant.gd          # Variant configuration resource
```

## Core Concepts

### Components

Components are reusable building blocks that generate specific parts of a building. Each component:
- Extends `BuildingComponentBase`
- Implements a `generate()` method that adds geometry to a SurfaceTool
- Declares required and optional parameters
- Validates parameters before generation

### Building Definitions

Building definitions are resource files (.tres) that define collections of building variants. They specify:
- Building type (residential, commercial, industrial)
- Style (ww2_european, american_art_deco, industrial_modern)
- Variants with dimensions, roof types, window styles, etc.
- Probability weights for random selection

### Materials

The system automatically creates PBR materials based on style rules:
- Wall materials (brick, stone, stucco)
- Roof materials (shingles, tiles, flat)
- Window materials (glass with transparency)
- Trim/detail materials (painted wood, stone)

## How To Extend The System

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

2. Register the component in `parametric_buildings.gd`:

```gdscript
func _register_components():
    _component_registry.register_component("wall", WallComponent)
    _component_registry.register_component("window", WindowComponent)
    _component_registry.register_component("window_gothic", WindowGothicComponent)  # Add this
    # ... other components
```

3. Use it in building definitions or code:

```gdscript
var gothic_window = _component_registry.get_component("window_gothic")
gothic_window.generate(st, params, materials)
```

### Adding a New Building Type

**Example: Creating Gothic cathedral buildings**

1. Create a building definition resource:

```gdscript
# resources/defs/buildings/cathedral_buildings.tres
[gd_resource type="Resource" script_class="BuildingDefinition" load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/building_systems/definitions/building_definition_base.gd" id="1"]
[ext_resource type="Script" path="res://scripts/building_systems/definitions/building_variant.gd" id="2"]

[sub_resource type="Resource" id="small_church"]
script = ExtResource("2")
name = "small_church"
footprint_type = "rect"
dimensions = Vector3(15.0, 20.0, 18.0)
floors = 1
roof_type = "gable"
window_style = "arched"
wall_profile = "historic"
detail_level = 2
probability_weight = 1.5
add_cupola = true

[resource]
script = ExtResource("1")
building_type = "religious"
style = "ww2_european"
variants = Array[Resource]([SubResource("small_church")])
```

2. Load and use in code:

```gdscript
var cathedral_def = load("res://resources/defs/buildings/cathedral_buildings.tres")
var variant = cathedral_def.get_random_variant()
var params = variant.to_params()
# Generate building with these params
```

### Adding a New Detail Type

**Example: Adding balconies**

1. Add a balcony generation method to `detail_component.gd`:

```gdscript
# In detail_component.gd
func generate_balconies(st: SurfaceTool, footprint: PackedVector2Array,
                        height: float, floors: int) -> void:
    # Generate balconies on upper floors
    for floor in range(1, floors):
        var y = floor * (height / floors)

        # Place balconies along front wall
        for i in range(balcony_count):
            _create_balcony(st, position, y, balcony_width, balcony_depth)

func _create_balcony(st: SurfaceTool, center: Vector3, y: float,
                     width: float, depth: float) -> void:
    # Create balcony platform
    var corners = [
        center + Vector3(-width/2, y, 0),
        center + Vector3(width/2, y, 0),
        center + Vector3(width/2, y, depth),
        center + Vector3(-width/2, y, depth)
    ]

    # Add balcony floor
    add_quad(st, corners[0], corners[1], corners[2], corners[3])

    # Add railing
    _add_balcony_railing(st, corners, y)
```

2. Expose as optional parameter:

```gdscript
func get_optional_params() -> Dictionary:
    return {
        # ... existing params ...
        "add_balconies": false,
        "balcony_count": 3
    }
```

3. Call in main generate method:

```gdscript
if params.get("add_balconies", false):
    generate_balconies(st, footprint, height, floors)
```

### Adding a New Footprint Shape

**Example: Adding octagonal footprint**

1. Add helper function to `parametric_buildings.gd`:

```gdscript
func _create_octagon_footprint(width: float, depth: float) -> PackedVector2Array:
    var points = PackedVector2Array()
    var radius = min(width, depth) * 0.5

    # Generate 8 points around a circle
    for i in range(8):
        var angle = (i / 8.0) * TAU
        var x = cos(angle) * radius
        var z = sin(angle) * radius
        points.append(Vector2(x, z))

    return points
```

2. Use in footprint generation:

```gdscript
func _create_residential_footprint(width: float, depth: float, floors: int) -> PackedVector2Array:
    var shape_type = randi() % 5  # Now includes octagon

    match shape_type:
        4:  # Octagon
            return _create_octagon_footprint(width, depth)
        # ... other cases ...
```

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

### BuildingVariant

Resource defining a specific building variant.

#### Properties

- `name: String` - Variant name
- `footprint_type: String` - "rect", "L", "T", "U", etc.
- `dimensions: Vector3` - (width, depth, height)
- `floors: int` - Number of floors
- `roof_type: String` - "gable", "hip", "flat", etc.
- `window_style: String` - "square", "arched", "bay", etc.
- `wall_profile: String` - "modern", "historic", "industrial"
- `detail_level: int` - 0=minimal, 1=normal, 2=ornate
- `probability_weight: float` - Selection weight (higher = more common)

#### Optional Overrides

- `color_override: Color` - Override default wall color
- `add_shutters: bool` - Add window shutters
- `add_window_boxes: bool` - Add window boxes
- `add_dormers: bool` - Add roof dormers
- `add_cupola: bool` - Add roof cupola

#### Methods

**`to_params() -> Dictionary`**
- Convert variant to parameter dictionary for building generation

### BuildingDefinition

Resource defining a collection of building variants.

#### Properties

- `building_type: String` - "residential", "commercial", "industrial", etc.
- `style: String` - "ww2_european", "american_art_deco", etc.
- `variants: Array[Resource]` - Array of BuildingVariant resources
- `default_materials: Dictionary` - Optional material overrides
- `component_overrides: Dictionary` - Optional component settings

#### Methods

**`get_random_variant() -> BuildingVariant`**
- Get random variant based on probability weights

**`get_variant_by_name(name: String) -> BuildingVariant`**
- Get specific variant by name

**`get_variant_names() -> Array[String]`**
- Get list of all variant names

## Style Rules

The system includes three built-in styles:

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

## Performance Considerations

### LOD System Integration

The parametric system respects the game's LOD system:
- **LOD 0 (Near)**: Full detail with windows, details, dormers
- **LOD 1 (Mid)**: Simplified geometry, fewer details
- **LOD 2 (Far)**: Basic shapes only

Currently, parametric buildings are only generated at LOD 0 for performance.

### MultiMesh Batching

Each building component creates a separate mesh surface with its own material:
- Walls surface (wall material)
- Windows surface (glass material)
- Roof surface (roof material)
- Details surface (trim material)

This allows efficient rendering while maintaining visual variety.

### Memory Usage

Each parametric building generates a unique mesh. For large settlements:
- Mix parametric (30%) with procedural/external assets (70%)
- Use simpler variants for distant buildings
- Consider implementing mesh caching for identical configurations

## Testing

### Visual Testing

Create a test scene to verify building generation:

```gdscript
extends Node3D

var building_system = BuildingParametricSystem.new()

func _ready():
    # Generate test grid of buildings
    for x in range(-3, 4):
        for z in range(-3, 4):
            var mesh = building_system.create_parametric_building(
                "residential",
                "ww2_european",
                10.0, 8.0, 12.0,
                randi_range(1, 3),
                2
            )

            var mi = MeshInstance3D.new()
            mi.mesh = mesh
            mi.position = Vector3(x * 20, 0, z * 20)
            add_child(mi)
```

### Component Testing

Test components in isolation:

```gdscript
var st = SurfaceTool.new()
st.begin(Mesh.PRIMITIVE_TRIANGLES)

var wall_component = WallComponent.new()
var params = {
    "footprint": PackedVector2Array([
        Vector2(-5, -5), Vector2(5, -5),
        Vector2(5, 5), Vector2(-5, 5)
    ]),
    "height": 10.0,
    "floors": 2,
    "floor_height": 5.0
}

if wall_component.validate_params(params):
    wall_component.generate(st, params, {})

st.generate_normals()
var mesh = st.commit()
assert(mesh != null)
```

## Troubleshooting

### Buildings Not Appearing

1. Check `_enable_parametric_buildings` flag in main.gd
2. Verify component registry is initialized
3. Check console for error messages from component validation

### Geometry Issues (Missing Faces, Inverted Normals)

1. Ensure vertices are in counter-clockwise order
2. Use `add_quad()` helper which handles winding automatically
3. Call `st.generate_normals()` after adding all geometry

### Materials Not Applied

1. Verify material dictionary is passed to component.generate()
2. Check surface indices match material assignments
3. Ensure ArrayMesh.surface_set_material() is called after adding surface

### Performance Issues

1. Reduce parametric building percentage (default 30%)
2. Disable parametric buildings for LOD > 0
3. Simplify component geometry (fewer vertices)
4. Use lower quality_level for distant buildings

## Future Extensions

### Potential Improvements

- **Mesh Caching**: Cache identical building configurations
- **Interior Generation**: Generate building interiors
- **Damage System**: Procedural damage/destruction
- **Animated Elements**: Doors, windows, flags
- **Texture System**: UV-mapped textures instead of solid colors
- **Vegetation**: Integrate with trees/plants (window boxes, ivy)
- **Lighting**: Emissive windows at night

### Community Contributions

To contribute new components or building types:
1. Create component extending BuildingComponentBase
2. Test in isolation first
3. Create example building definitions
4. Document parameters and usage
5. Submit with visual examples

## Examples

See the included building definitions for complete examples:
- `resources/defs/buildings/residential_buildings.tres`
- `resources/defs/buildings/commercial_buildings.tres`
- `resources/defs/buildings/industrial_buildings.tres`

## License

This parametric building system is part of the Neon Dogfight game codebase.

## Credits

Developed by Claude AI Assistant as part of the Neon Dogfight project.
Component-based architecture designed for extensibility and AI collaboration.
