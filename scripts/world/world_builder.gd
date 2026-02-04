class_name WorldBuilder
extends RefCounted

## Modular world generation orchestrator.
## Uses WorldComponentBase scripts (registered in WorldComponentRegistry) to build the world in stages.

signal generation_started
signal generation_progress(stage: String, progress: float)
signal generation_completed

# Component registry
var _component_registry: WorldComponentRegistry = null
var _default_components: Array[String] = []

# Generators (shared services)
var terrain_generator: TerrainGenerator = null
var settlement_generator: SettlementGenerator = null
var prop_generator: PropGenerator = null

# New: helper generators (kept untyped to avoid class load-order issues)
var biome_generator: RefCounted = null
var water_bodies_generator: RefCounted = null
var road_network_generator: RefCounted = null
var zoning_generator: RefCounted = null

# World state
var world_root: Node3D = null
var world_seed: int = 0
var world_params: Dictionary = {}

# Shared references
var _assets: RefCounted = null
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _building_kits: Dictionary = {}
var _parametric_system: RefCounted = null
var _unified_building_system: RefCounted = null

# Last build outputs
var _ctx: WorldContext = null

func _init():
    _component_registry = WorldComponentRegistry.new()
    _register_default_components()

    terrain_generator = TerrainGenerator.new()
    settlement_generator = SettlementGenerator.new()
    prop_generator = PropGenerator.new()
    biome_generator = BiomeGenerator.new()
    water_bodies_generator = WaterBodiesGenerator.new()
    road_network_generator = RoadNetworkGenerator.new()
    zoning_generator = ZoningGenerator.new()

    # Initialize building systems
    _parametric_system = preload("res://scripts/building_systems/parametric_buildings.gd").new()
    _unified_building_system = preload("res://scripts/building_systems/unified_building_system.gd").new()

    # Wire up dependencies
    settlement_generator.set_terrain_generator(terrain_generator)
    prop_generator.set_terrain_generator(terrain_generator)
    water_bodies_generator.set_terrain_generator(terrain_generator)
    road_network_generator.set_terrain_generator(terrain_generator)

## Register default world components (builtin pipeline)
func _register_default_components() -> void:
    # Built-in components (script-based, replaceable)
    _component_registry.register_component("heightmap", preload("res://scripts/world/components/builtin/heightmap_component.gd"))
    _component_registry.register_component("lakes", preload("res://scripts/world/components/builtin/lakes_component.gd"))
    _component_registry.register_component("biomes", preload("res://scripts/world/components/builtin/biomes_component.gd"))
    _component_registry.register_component("ocean", preload("res://scripts/world/components/builtin/ocean_component.gd"))
    _component_registry.register_component("terrain_mesh", preload("res://scripts/world/components/builtin/terrain_mesh_component.gd"))
    _component_registry.register_component("terrain_carving", preload("res://scripts/world/components/builtin/terrain_carving_component.gd"))
    _component_registry.register_component("runway", preload("res://scripts/world/components/builtin/runway_component.gd"))
    _component_registry.register_component("rivers", preload("res://scripts/world/components/builtin/rivers_component.gd"))
    _component_registry.register_component("landmarks", preload("res://scripts/world/components/builtin/landmarks_component.gd"))

    # NEW: Improved road generation components
    _component_registry.register_component("waypoints", preload("res://scripts/world/components/builtin/waypoint_generator_component.gd"))
    _component_registry.register_component("unified_road_planner", preload("res://scripts/world/components/unified_road_network_component.gd"))
    _component_registry.register_component("road_density_analysis", preload("res://scripts/world/components/builtin/road_density_analyzer_component.gd"))
    _component_registry.register_component("settlement_local_roads", preload("res://scripts/world/components/builtin/settlement_local_roads_component.gd"))
    _component_registry.register_component("hierarchical_road_branching", preload("res://scripts/world/components/builtin/hierarchical_road_branching_component.gd"))
    _component_registry.register_component("road_plot_generator", preload("res://scripts/world/components/builtin/road_plot_generator_component.gd"))
    _component_registry.register_component("organic_building_placement", preload("res://scripts/world/components/builtin/organic_building_placement_component.gd"))

    # OLD: Legacy components (disabled - replaced by organic system above)
    #_component_registry.register_component("master_roads", preload("res://scripts/world/components/builtin/master_roads_component.gd"))
    #_component_registry.register_component("settlements", preload("res://scripts/world/components/builtin/settlements_v2_component.gd"))
    #_component_registry.register_component("zoning", preload("res://scripts/world/components/builtin/zoning_component.gd"))
    #_component_registry.register_component("settlement_buildings", preload("res://scripts/world/components/builtin/settlement_buildings_component.gd"))

    # OLD: Legacy road components (disabled - now handled by master_roads)
    #_component_registry.register_component("regional_roads", preload("res://scripts/world/components/builtin/regional_roads_component.gd"))
    #_component_registry.register_component("road_network", preload("res://scripts/world/components/builtin/road_network_component.gd"))
    #_component_registry.register_component("settlement_roads", preload("res://scripts/world/components/builtin/settlement_roads_component.gd"))

    # OLD: Legacy circular settlement system (removed - unified into settlements above)
    # _component_registry.register_component("settlements", preload("res://scripts/world/components/builtin/settlements_component.gd"))

    _component_registry.register_component("zoning", preload("res://scripts/world/components/builtin/zoning_component.gd"))
    _component_registry.register_component("settlement_buildings", preload("res://scripts/world/components/builtin/settlement_buildings_component.gd"))
    _component_registry.register_component("farms", preload("res://scripts/world/components/builtin/farms_component.gd"))
    _component_registry.register_component("decor", preload("res://scripts/world/components/builtin/decor_component.gd"))
    _component_registry.register_component("forest", preload("res://scripts/world/components/builtin/forest_component.gd"))
    _component_registry.register_component("lake_scenes", preload("res://scripts/world/components/builtin/lake_scenes_component.gd"))
    _component_registry.register_component("river_features", preload("res://scripts/world/components/builtin/river_features_component.gd"))
    _component_registry.register_component("ocean_features", preload("res://scripts/world/components/builtin/ocean_features_component.gd"))

    _default_components = [
        "heightmap",
        # "lakes",              # DISABLED: Lake generation disabled due to performance/quality issues
        "biomes",
        "ocean",
        "terrain_mesh",       # Initial terrain mesh generation
        "runway",
        # "rivers",            # DISABLED: River generation disabled due to performance/quality issues
        "landmarks",
        # NEW: Improved road generation pipeline
        "waypoints",                    # Identify terrain features (valleys, plateaus, coasts)
        "unified_road_planner",         # Build intelligent road network with proper planning and bridges
        "road_density_analysis",        # Calculate urban density from road intersections
        "settlement_local_roads",       # Generate DENSE local road networks INSIDE settlements
        "hierarchical_road_branching",  # Smart branches connecting to existing roads
        "road_plot_generator",          # Generate building plots along roads
        "organic_building_placement",   # Place buildings on plots
        "terrain_carving",              # Carve roads into terrain, regenerate mesh
        # OLD: Legacy settlement-first pipeline (disabled)
        #"settlements",        # Plan settlement locations with organic roads
        #"master_roads",       # Build inter-settlement road network
        #"zoning",
        #"settlement_buildings",
        "farms",
        "decor",
        "forest",
        # "lake_scenes",       # DISABLED: Lake scenes disabled
        # "river_features",    # DISABLED: River features disabled
        "ocean_features",
    ]

## Build entire world (returns outputs for main.gd to hook into)
func build_world(root: Node3D, seed: int, params: Dictionary) -> Dictionary:
    print("🌍 WorldBuilder: Starting modular world generation (seed: %d)" % seed)
    generation_started.emit()

    world_root = root
    world_seed = seed
    world_params = params

    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    # Clear existing world
    for child in world_root.get_children():
        child.queue_free()

    # Context
    _ctx = WorldContext.new()
    _ctx.setup(world_root, rng, world_params)
    _ctx.assets = _assets
    _ctx.mesh_cache = _mesh_cache
    _ctx.material_cache = _material_cache
    _ctx.building_kits = _building_kits
    _ctx.parametric_system = _parametric_system
    _ctx.unified_building_system = _unified_building_system
    _ctx.terrain_generator = terrain_generator
    _ctx.settlement_generator = settlement_generator
    _ctx.prop_generator = prop_generator
    _ctx.biome_generator = biome_generator
    _ctx.water_bodies_generator = water_bodies_generator
    _ctx.road_network_generator = road_network_generator
    _ctx.zoning_generator = zoning_generator

    terrain_generator.set_assets(_assets)
    settlement_generator.set_assets(_assets)
    prop_generator.set_assets(_assets)

    # Component order (overrideable)
    var component_ids: Array[String] = _default_components
    if world_params.has("world_components") and world_params["world_components"] is Array:
        component_ids = world_params["world_components"]

    # Apply optional defaults up-front so components can rely on params
    _apply_component_defaults(component_ids)

    # Execute pipeline
    var total: int = max(1, component_ids.size())
    for i in range(component_ids.size()):
        var id: String = component_ids[i]
        generation_progress.emit(id, float(i) / float(total))
        _run_component(id, rng)
        generation_progress.emit(id, float(i + 1) / float(total))

    generation_completed.emit()
    print("🌍 WorldBuilder: World generation complete")

    return {
        "hmap": _ctx.hmap,
        "hmap_res": _ctx.hmap_res,
        "hmap_step": _ctx.hmap_step,
        "hmap_half": _ctx.hmap_half,
        "rivers": _ctx.rivers,
        "biome_map": _ctx.biome_map,
        "lakes": _ctx.lakes,
        "roads": _ctx.get_data("organic_roads"),
        "runway_spawn": _ctx.runway_spawn,
        "terrain_root": _ctx.terrain_render_root,
        "settlements": _ctx.settlements,
        "prop_lod_groups": _ctx.prop_lod_groups,
    }

func _apply_component_defaults(component_ids: Array[String]) -> void:
    for id in component_ids:
        var c: WorldComponentBase = _component_registry.get_component(id)
        if c == null:
            continue
        var opt: Dictionary = c.get_optional_params()
        for k in opt.keys():
            if not world_params.has(k):
                world_params[k] = opt[k]

func _run_component(id: String, rng: RandomNumberGenerator) -> void:
    var c: WorldComponentBase = _component_registry.get_component(id)
    if c == null:
        push_error("WorldBuilder: unknown component '%s'" % id)
        return
    c.set_context(_ctx)

    # Required param check (warn only)
    var req: Array[String] = c.get_required_params()
    for k in req:
        if not world_params.has(k):
            push_warning("WorldBuilder[%s]: missing param '%s' (using defaults if any)" % [id, k])

    c.generate(world_root, world_params, rng)

## Update LOD based on camera position (terrain only for now)
func update_lod(camera_position: Vector3, lod_enabled: bool) -> void:
    if terrain_generator == null:
        return
    var lod0_r: float = float(world_params.get("terrain_lod0_r", 6500.0))
    var lod1_r: float = float(world_params.get("terrain_lod1_r", 16000.0))
    var enabled: bool = lod_enabled and bool(world_params.get("terrain_lod_enabled", true))
    terrain_generator.apply_terrain_lod(camera_position, enabled, lod0_r, lod1_r)

## Terrain query helpers
func get_height_at(x: float, z: float) -> float:
    if terrain_generator:
        return terrain_generator.get_height_at(x, z)
    return 0.0

func get_normal_at(x: float, z: float) -> Vector3:
    if terrain_generator:
        return terrain_generator.get_normal_at(x, z)
    return Vector3.UP

func get_slope_at(x: float, z: float) -> float:
    if terrain_generator:
        return terrain_generator.get_slope_at(x, z)
    return 0.0

func is_near_coast(x: float, z: float, radius: float) -> bool:
    if terrain_generator:
        return terrain_generator.is_near_coast(x, z, radius)
    return false

func find_land_point(rng: RandomNumberGenerator, min_height: float, max_slope: float, prefer_coast: bool) -> Vector3:
    if terrain_generator:
        return terrain_generator.find_land_point(rng, min_height, max_slope, prefer_coast)
    return Vector3.ZERO

func get_settlements() -> Array:
    if settlement_generator:
        return settlement_generator.get_settlements()
    return []

# --- Pass-through setters for shared references ---
func set_assets(a: RefCounted) -> void:
    _assets = a
    if terrain_generator:
        terrain_generator.set_assets(a)
    if settlement_generator:
        settlement_generator.set_assets(a)
    if prop_generator:
        prop_generator.set_assets(a)

func set_mesh_cache(cache: Dictionary) -> void:
    _mesh_cache = cache

func set_material_cache(cache: Dictionary) -> void:
    _material_cache = cache

func set_building_kits(kits: Dictionary) -> void:
    _building_kits = kits

func set_parametric_system(sys: RefCounted) -> void:
    _parametric_system = sys

# Get unified building system for statistics
func get_unified_building_system():
    return _unified_building_system

# Get world context for accessing shared data
func get_context() -> WorldContext:
    return _ctx
