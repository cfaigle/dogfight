# Dogfight: 1940 (Godot 4.6) - Development Context

## Project Overview

Dogfight: 1940 is a self-contained arcade 3D dogfight sandbox game built with Godot 4.6. The game includes procedural fighter meshes, weapons systems (guns with tracers and muzzle flashes, homing missiles), enemy AI with lead pursuit and evasive maneuvers, waves, scoring, and a comprehensive HUD.

## Architecture

The project follows a modular architecture with:
- `Plane` base class with `PlayerPlane` and `EnemyPlane` subclasses
- Separate weapon components (`Gun`, `MissileLauncher`, `Missile`)
- `GameEvents` autoload for decoupled signals
- Modular world generation system with component-based pipeline

## Key Systems

### World Generation
The project implements a sophisticated modular world generation system with:
- Component-based pipeline (heightmap → lakes → biomes → ocean → terrain_mesh → runway → rivers → landmarks → settlements → zoning → road_network → farms → decor → forest)
- Built-in components in `scripts/world/components/builtin/*`
- Reusable generators in `scripts/world/generators/`
- LOD (Level of Detail) systems for performance optimization

### Road and Bridge System
The road system has been significantly enhanced with:
- Unified road network component using tessellated rendering
- Intelligent bridge detection that only creates bridges over water bodies
- Proper road segmentation with land sections and water-crossing bridges
- Hierarchical road branching for organic city structure
- Settlement-local road networks for dense urban areas
- Road density analysis for emergent urban center identification
- Building plot generation along roads
- Adaptive road subdivision that follows terrain contours without disruption
- Enhanced terrain carving with improved parameters for better road integration
- Consistent road elevation offset to prevent terrain clipping

### Lake Scene System
Advanced lake scene generation with:
- Multiple lake types (basic, recreational, fishing, harbor)
- Procedural boat generation (fishing boats, sailboats, speedboats, pontoons, etc.)
- Buoy and dock systems
- Shore features (beaches, concessions, picnic areas)
- Harbor infrastructure with breakwaters and navigation lights
- Performance-optimized LOD system with 3 detail levels

### Building Systems
- Parametric building system for procedural structures
- Building kit system organized by settlement style
- Damage modeling and visual degradation

### Vehicle Systems
- Flight physics with pitch, roll, yaw, throttle controls
- Weapon systems with hitscan guns and homing missiles
- Enemy AI with targeting and evasion behaviors

## Controls

- **Pitch**: W / S
- **Roll**: A / D  
- **Yaw**: Q / E
- **Throttle**: R / F (incremental)
- **Afterburner**: Shift
- **Guns**: Left Mouse (or Space)
- **Missile**: Right Mouse (or Ctrl)
- **Hold lock**: Alt (build lock if target is in cone)
- **Next target**: Tab
- **Pause**: Esc
- **Regenerate world (new seed)**: F2
- **Regenerate world (same seed)**: F3
- **Toggle Peaceful Mode (no enemies)**: F4

## Configuration

Data-driven tuning lives in `res://resources/defs/`:
- `plane_defs.tres` (player/enemy stats + colors)
- `weapon_defs.tres` (gun + missile stats)
- `lake_defs.tres` (lake scene configurations)

## Building and Running

### Requirements
- Godot **4.6 stable** (or newer in the 4.6 line)

### How to run
1. Import this folder as a Godot project
2. Press **Play** (F5)

### Debugging and Syntax Checking
- To check syntax of individual scripts: `godot --check-script <script_path>`
- To import and verify project syntax: `godot --import-only`
- To run the editor: `godot --path . --editor`

### Development Best Practices
- Always check script syntax after editing: `godot --check-script <script_path>`
- Verify the project builds correctly after making changes: `godot --import-only`

### Road and Bridge System Debugging
- Roads now use adaptive subdivision to follow terrain contours without disruption
- Bridge detection properly identifies water crossings and creates bridges only where needed
- Road elevation is consistently raised above terrain with dynamic validation to prevent clipping (minimum 2.0m clearance)
- Local road networks properly connect with shared vertices to eliminate gaps
- Enhanced terrain carving temporarily disabled to prevent roads from floating above terrain
- Tessellated rendering used consistently across all road types for smooth geometry
- Path validation system ensures no part of roads go under terrain by checking intermediate points along entire path

## Development Conventions

### GDScript Best Practices
- Avoid `:=` when the RHS is a Variant-ish value to prevent "Warnings treated as errors"
- Use `var x = dict.get("k", 0)` instead of `var x := dict.get("k", 0)`
- Or explicitly type it: `var x: int = int(dict.get("k", 0))`

### Component Architecture
- Components extend `WorldComponentBase`
- Use `ctx` (WorldContext) for shared state and layer management
- Store outputs back onto `ctx` if later stages depend on them
- Use `ctx.get_layer("Props")` for accessing named layers

### Performance Considerations
- MultiMesh usage where possible
- Chunked generation and LOD toggles
- Caching for meshes, materials, and props
- Distance-based LOD systems

## Key Files and Directories

- `.godot/` - Godot project metadata
- `assets/` - Game assets
- `resources/` - Game resources including shaders and definitions
- `scenes/` - Scene files
- `scripts/` - Source code organized by functionality:
  - `game/` - Core game logic
  - `actors/` - Player and enemy entities
  - `ui/` - User interface elements
  - `world/` - World generation systems
  - `util/` - Utility functions
- `tools/` - Development tools
- `project.godot` - Project configuration

## Special Features

### Procedural Generation
- Procedural fighter meshes (no external assets)
- Procedural terrain with heightmaps
- Procedural settlements and road networks
- Procedural lake scenes with boats and infrastructure

### Visual Effects
- Tracers and muzzle flashes for guns
- Smoke trails for missiles
- Hit markers and visual feedback
- Dynamic lighting and shadows

### Technical Systems
- Jolt Physics engine
- Custom terrain shader
- Ocean shader with dynamic properties
- Advanced LOD systems for terrain and props