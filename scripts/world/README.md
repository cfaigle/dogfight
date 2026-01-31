## World Generation System

Modular, component-based world generation architecture for Dogfight: 1940.

## Architecture

### Core Classes

**WorldBuilder** (`world_builder.gd`)
- Main orchestrator for world generation
- Coordinates all generators and components
- Provides unified interface for main.gd
- Manages generation pipeline and progress

**Generators / Services**
- **TerrainGenerator** (`generators/terrain_generator.gd`) - Heightmap, mesh chunks, ocean, rivers
- **SettlementGenerator** (`generators/settlement_generator.gd`) - Settlement placement + building instancing
- **PropGenerator** (`generators/prop_generator.gd`) - Forests + ponds (biome-aware if available)
- **BiomeGenerator** (`generators/biome_generator.gd`) - Biome classification map (service)
- **WaterBodiesGenerator** (`generators/water_bodies_generator.gd`) - Lakes (carves into heightmap)
- **RoadNetworkGenerator** (`generators/road_network_generator.gd`) - Trunk roads/highways (uses RoadModule)
- **ZoningGenerator** (`generators/zoning_generator.gd`) - District hints around settlements
- **LODManager** (`generators/lod_manager.gd`) - Level of detail updates based on camera

### Components (Active)

Built-in components live in `scripts/world/components/builtin/` and are registered by `WorldBuilder`.

Default pipeline (order):
1. Heightmap
2. Lakes (carve into heightmap)
3. Biomes (classification map)
4. Ocean
5. TerrainMesh (chunked LOD)
6. Runway
7. Rivers
8. Landmarks
9. Settlements
10. Zoning
11. RoadNetwork
12. Farms
13. Decor (suburbs/industry/beach huts)
14. Forest (trees/ponds)

**WorldComponentBase** (`components/world_component_base.gd`)
- Base class for all world components
- Standard interface: `generate(world_root, params, rng)`
- Dependency resolution via `get_dependencies()`
- Priority-based ordering via `get_priority()`

**WorldComponentRegistry** (`components/world_component_registry.gd`)
- Component registration and discovery
- Dependency ordering (topological sort)
- Component instantiation

### Modules (Infrastructure)

**RoadModule** (`modules/road_module.gd`)
- A* pathfinding for road generation
- Obstacle avoidance (water, steep terrain)
- Bridge placement
- Road mesh generation

**Future Modules:**
- BridgeModule - Bridge generation across water
- RiverModule - River network generation
- VegetationModule - Biome-based vegetation placement

## Usage

### Basic World Generation

```gdscript
var world_builder = WorldBuilder.new()
world_builder.set_mesh_cache(mesh_cache)
world_builder.set_material_cache(material_cache)

var params = {
	"terrain_size": 32000.0,
	"terrain_res": 512,
	"lod0_radius": 800.0,
	"lod1_radius": 1600.0
}

world_builder.build_world(world_root, seed, params)
```

### LOD Updates

```gdscript
func _process(delta: float) -> void:
	var camera_pos = camera.global_position
	world_builder.update_lod(camera_pos, true)
```

### Terrain Queries

```gdscript
# Get height at position
var height = world_builder.get_height_at(x, z)

# Get slope
var slope = world_builder.get_slope_at(x, z)

# Check if near coast
var near_coast = world_builder.is_near_coast(x, z, 150.0)

# Find random land point
var land_point = world_builder.find_land_point(rng, min_height, max_slope, prefer_coast)
```

## Component System (Future)

### Creating a New Component

```gdscript
class_name RiverComponent
extends WorldComponentBase

func get_priority() -> int:
	return 5  # After terrain (0), before settlements (10)

func get_dependencies() -> Array[String]:
	return ["terrain"]  # Requires terrain to be generated first

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Generate river network
	var source = _find_highest_point(params)
	var path = _flow_to_ocean(source, params)
	_create_river_mesh(world_root, path)
```

### Registering Components

```gdscript
func _register_default_components() -> void:
	_component_registry.register_component("terrain", TerrainComponent)
	_component_registry.register_component("water", WaterComponent)
	_component_registry.register_component("river", RiverComponent)
	_component_registry.register_component("vegetation", VegetationComponent)
	_component_registry.register_component("infrastructure", InfrastructureComponent)
```

### Generation Pipeline

Components generate in priority order with dependency resolution:
1. Terrain (priority 0)
2. Water/Ocean (priority 5)
3. Rivers (priority 10)
4. Settlements (priority 20)
5. Vegetation (priority 30)
6. Infrastructure (priority 40)

## Road Generation

### Using RoadModule

```gdscript
var road_module = RoadModule.new()
road_module.set_terrain_generator(terrain_generator)

var params = {
	"allow_bridges": true,
	"smooth": true,
	"width": 6.0
}

var path = road_module.generate_road(start_pos, end_pos, params)
var road_mesh = road_module.create_road_mesh(path, 6.0, road_material)
world_root.add_child(road_mesh)
```

### Pathfinding Features

- **Water Avoidance**: High cost for water tiles, routes around lakes
- **Bridge Placement**: Can build bridges with configurable cost
- **Slope Penalties**: Avoids steep terrain when possible
- **Path Smoothing**: Catmull-Rom or averaging smoothing

## Migration from main.gd

### Before (main.gd)
```gdscript
# 3913 lines of monolithic world generation
func _setup_world() -> void:
	_build_terrain()
	_build_ocean()
	_build_rivers()
	_build_set_dressing()  # settlements, props, etc.
	_build_roads()
	# ... hundreds more lines ...
```

### After (main.gd with WorldBuilder)
```gdscript
# Clean delegation to WorldBuilder
func _setup_world() -> void:
	if not _world_builder:
		_world_builder = WorldBuilder.new()
		_world_builder.set_mesh_cache(_mesh_cache)
		_world_builder.set_material_cache(_material_cache)

	_world_builder.build_world(_world_root, world_seed, world_params)
```

## Future Extensions

### Advanced Road Network
- Road hierarchy (highways, streets, paths)
- Intersection generation
- Traffic simulation points
- Road surface variation (paved, dirt, damaged)

### Dynamic Bridges
- Suspension bridges over long spans
- Arch bridges over rivers
- Railway bridges
- Destructible bridges

### River Networks
- Watershed simulation
- Erosion patterns
- River junctions and deltas
- Wetlands and marshes

### Vegetation Biomes
- Climate-based plant distribution
- Forest density maps
- Transition zones
- Seasonal variation

### Settlement Evolution
- Road-following expansion
- Agricultural zones around settlements
- Resource-based placement
- Historical growth simulation

## Performance

### Current
- Terrain LOD: 3 levels (stride 1, 2, 4)
- Prop LOD: 3 levels (near, mid, far)
- Chunk size: 32 cells (configurable)
- Heightmap: 512x512 (configurable)

### Optimization Opportunities
- Async generation (threaded)
- Streaming world chunks
- Procedural detail on GPU
- Instanced rendering for vegetation
- Occlusion culling for settlements

## Files

```
scripts/world/
├── world_builder.gd                  # Main orchestrator
├── components/
│   ├── world_component_base.gd       # Component base class
│   └── world_component_registry.gd   # Component registry
├── generators/
│   ├── terrain_generator.gd          # Terrain generation
│   ├── settlement_generator.gd       # Settlement generation
│   ├── prop_generator.gd             # Prop generation
│   └── lod_manager.gd                # LOD updates
└── modules/
    └── road_module.gd                # Road pathfinding & generation
```

## Development Workflow

1. **Add new feature**: Create component class
2. **Register**: Add to WorldBuilder._register_default_components()
3. **Set priority**: Define generation order
4. **Add dependencies**: Declare component dependencies
5. **Test**: Verify generation in isolation
6. **Integrate**: Add to WorldBuilder.build_world() pipeline

## Credits

Refactored from main.gd monolith into modular architecture.
Component system designed for AI collaboration and extensibility.
