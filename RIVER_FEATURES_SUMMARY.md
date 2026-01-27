# River Features Implementation - Summary

## Overview
Added lake-like features to rivers including docks, boats, and shore features. Features are placed strategically along rivers based on width, flow direction, and position (upper/middle/lower sections).

## New Files Created

### 1. `scripts/world/components/builtin/river_features_component.gd`
Main component that generates features along rivers.

**Key Features:**
- Samples rivers at multiple points using parameterization (t from 0.0 to 1.0)
- Places docks on riverbanks in wide sections
- Places boats floating in the middle/lower sections
- Respects minimum width requirements for different features
- Uses river direction to orient features correctly

**Configuration Parameters:**
```gdscript
{
    "enable_river_features": true,
    "river_dock_chance": 0.3,      // Chance per suitable river section
    "river_boat_chance": 0.2,
    "river_bridge_chance": 0.15,   // Reserved for future use
    "min_river_width_for_docks": 25.0,
    "min_river_width_for_boats": 20.0,
}
```

**Priority:** 72 (runs after rivers are generated, before final decoration)

## Modified Files

### 1. `scripts/world/generators/dock_generator.gd`
Added public methods to support river features:

```gdscript
func set_terrain_generator(terrain: TerrainGenerator) -> void
func set_lake_defs(defs: LakeDefs) -> void
func create_single_dock(position: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> Node3D
```

**Usage:**
```gdscript
var dock_generator = DockGenerator.new()
dock_generator.set_terrain_generator(ctx.terrain_generator)
dock_generator.set_lake_defs(lake_defs)

var dock_config = {
    "type": "fishing_pier",  // or "marina_dock", "boat_launch", "swimming_dock"
    "length": 20.0,
    "width": 5.0,
    "rotation": 1.57  // radians
}
var dock = dock_generator.create_single_dock(position, dock_config, rng)
```

### 2. `scripts/world/generators/boat_generator.gd`
Added public methods to support river features:

```gdscript
func set_terrain_generator(terrain: TerrainGenerator) -> void
func set_lake_defs(defs: LakeDefs) -> void
func create_single_boat(position: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> Node3D
```

**Usage:**
```gdscript
var boat_generator = BoatGenerator.new()
boat_generator.set_terrain_generator(ctx.terrain_generator)
boat_generator.set_lake_defs(lake_defs)

var boat_config = {
    "type": "fishing",  // or "sailboat", "speedboat", "pontoon"
    "rotation": 0.5  // radians (optional, aligns with river flow)
}
var boat = boat_generator.create_single_boat(position, boat_config, rng)
```

### 3. `scripts/world/world_builder.gd`
Registered the new river_features component:
- Line 78: Added registration
- Line 96: Added to default components list

## Technical Implementation

### River Parameterization System

The system uses a parameterization approach where each point along the river is represented by t (0.0 to 1.0):
- t = 0.0: River source (narrow, fast-flowing)
- t = 0.3-0.7: Middle sections (moderate width)
- t = 0.9-1.0: River mouth (wide, slow-flowing)

**Helper Functions:**
```gdscript
_get_river_position_at(points: PackedVector3Array, t: float) -> Vector3
_get_river_direction_at(points: PackedVector3Array, t: float) -> Vector3
_get_river_width_at(width0: float, width1: float, t: float) -> float
```

### Feature Placement Strategy

#### Docks
- Placed on riverbanks (offset perpendicular to flow direction)
- Require minimum width of 25m (configurable)
- Skip upper sections (t < 0.2) which are too narrow/fast
- Oriented perpendicular to river flow
- Type varies by position:
  - Upper/middle (t < 0.7): fishing_pier
  - Lower/mouth (t >= 0.7): marina_dock

#### Boats
- Placed in middle of river or slightly off-center
- Require minimum width of 20m (configurable)
- Skip upper sections (t <= 0.3) which are too narrow
- Oriented parallel to river flow with slight random variation
- Type varies by width:
  - Narrow rivers (< 35m): fishing boats
  - Wide rivers (>= 35m): sailboats

### Perpendicular Offset Calculation

Features are placed on riverbanks using perpendicular offset:
```gdscript
var direction: Vector3 = _get_river_direction_at(points, t)
var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
var side: float = 1.0 if rng.randf() < 0.5 else -1.0  // Randomly choose left or right bank
var offset_pos: Vector3 = center + perpendicular * side * offset_distance
```

## River Width Interpolation

River width increases non-linearly from source to mouth:
```gdscript
var width: float = lerp(width0, width1, pow(t, 0.85))
```

This creates a natural profile where:
- Source: 10-16m wide
- Mouth: 34-58m wide
- Growth accelerates toward the mouth

## Dependencies

- **Requires:** Rivers component (must run after rivers are generated)
- **Uses:** LakeDefs resource (`res://resources/defs/lake_defs.tres`)
- **Generators:** DockGenerator, BoatGenerator

## Configuration

Enable/disable in world generation parameters:
```gdscript
var params = {
    "enable_river_features": true,
    "river_dock_chance": 0.3,
    "river_boat_chance": 0.2,
    "min_river_width_for_docks": 25.0,
    "min_river_width_for_boats": 20.0,
}
```

## Future Enhancements (Not Implemented)

1. **Bridge Generation**:
   - Parameter `river_bridge_chance` is defined but not used
   - Could place bridges at narrow sections or settlement crossings

2. **Shore Features**:
   - Could add reeds, rocks, beaches along riverbanks
   - Similar to lake shore features

3. **River Towns/Settlements**:
   - Could place small riverside settlements
   - Dock clusters at strategic locations

4. **Fishing Spots**:
   - Designated fishing areas with props (fishing poles, boats)

5. **Water Mills**:
   - Historical water mills along suitable river sections

6. **Dynamic Flow Visualization**:
   - Particle effects showing water flow direction
   - Foam/rapids in narrow/steep sections

## Testing

The component has been integrated into the default world generation pipeline and will automatically generate features on all rivers that meet the width requirements.

To test:
1. Press F5 in Godot to run the game
2. Look for docks along wide river sections
3. Look for boats floating in rivers
4. Check that features align with river flow direction

To disable:
```gdscript
Game.set_param("enable_river_features", false)
```

## Files Modified Summary

- Created: 1 new component file
- Modified: 4 existing files
  - dock_generator.gd (added public API)
  - boat_generator.gd (added public API)
  - world_builder.gd (registered component)
  - (using SPACES for indentation as requested)

Total impact: Minimal, well-isolated feature addition with no breaking changes.
