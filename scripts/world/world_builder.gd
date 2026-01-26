class_name WorldBuilder
extends RefCounted

## Main orchestrator for world generation
## Coordinates all generators and components to build the game world
## Replaces monolithic main.gd world generation

signal generation_started
signal generation_progress(stage: String, progress: float)
signal generation_completed

# Component registry
var _component_registry: WorldComponentRegistry = null

# Generator modules
var terrain_generator: TerrainGenerator = null
var settlement_generator: SettlementGenerator = null
var prop_generator: PropGenerator = null
var lod_manager: LODManager = null

# World state
var world_root: Node3D = null
var world_seed: int = 0
var world_params: Dictionary = {}

# References (passed from main.gd)
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}

func _init():
	_component_registry = WorldComponentRegistry.new()
	_register_default_components()

	# Initialize generators
	terrain_generator = TerrainGenerator.new()
	settlement_generator = SettlementGenerator.new()
	prop_generator = PropGenerator.new()
	lod_manager = LODManager.new()

	# Wire up dependencies
	lod_manager.set_terrain_generator(terrain_generator)
	lod_manager.set_prop_generator(prop_generator)

## Register default world components
func _register_default_components() -> void:
	# Components will be registered here as they're created
	# For now, using generator classes instead
	pass

## Build entire world
func build_world(root: Node3D, seed: int, params: Dictionary) -> void:
	print("🌍 WorldBuilder: Starting world generation (seed: %d)" % seed)
	generation_started.emit()

	world_root = root
	world_seed = seed
	world_params = params

	var rng = RandomNumberGenerator.new()
	rng.seed = seed

	# Clear existing world
	for child in world_root.get_children():
		child.queue_free()

	# Stage 1: Terrain
	generation_progress.emit("terrain", 0.0)
	terrain_generator.generate(world_root, params, rng)
	generation_progress.emit("terrain", 1.0)

	# Stage 2: Water features (ocean, rivers, ponds)
	generation_progress.emit("water", 0.0)
	terrain_generator.build_ocean(world_root, params)
	terrain_generator.build_rivers(world_root, params, rng)
	generation_progress.emit("water", 1.0)

	# Stage 3: Settlements
	generation_progress.emit("settlements", 0.0)
	settlement_generator.generate(world_root, params, rng)
	generation_progress.emit("settlements", 1.0)

	# Stage 4: Props (trees, rocks, fields, etc.)
	generation_progress.emit("props", 0.0)
	prop_generator.generate(world_root, params, rng)
	generation_progress.emit("props", 1.0)

	# Stage 5: Infrastructure (roads, runway, etc.)
	generation_progress.emit("infrastructure", 0.0)
	terrain_generator.build_runway(world_root, params)
	settlement_generator.build_roads(world_root, params, rng)
	generation_progress.emit("infrastructure", 1.0)

	# Stage 6: Final details
	generation_progress.emit("details", 0.0)
	terrain_generator.build_landmarks(world_root, params, rng)
	prop_generator.build_ww2_props(world_root, params, rng)
	generation_progress.emit("details", 1.0)

	print("🌍 WorldBuilder: World generation complete")
	generation_completed.emit()

## Update LOD based on camera position
func update_lod(camera_position: Vector3, lod_enabled: bool) -> void:
	if not lod_manager:
		return

	var lod_params = {
		"lod_enabled": lod_enabled,
		"lod0_radius": world_params.get("lod0_radius", 800.0),
		"lod1_radius": world_params.get("lod1_radius", 1600.0)
	}

	lod_manager.update(world_root, camera_position, lod_params)

## Get terrain height at position
func get_height_at(x: float, z: float) -> float:
	if terrain_generator:
		return terrain_generator.get_height_at(x, z)
	return 0.0

## Get terrain normal at position
func get_normal_at(x: float, z: float) -> Vector3:
	if terrain_generator:
		return terrain_generator.get_normal_at(x, z)
	return Vector3.UP

## Get slope at position (in degrees)
func get_slope_at(x: float, z: float) -> float:
	if terrain_generator:
		return terrain_generator.get_slope_at(x, z)
	return 0.0

## Check if position is near coast
func is_near_coast(x: float, z: float, radius: float) -> bool:
	if terrain_generator:
		return terrain_generator.is_near_coast(x, z, radius)
	return false

## Find random land point meeting criteria
func find_land_point(rng: RandomNumberGenerator, min_height: float, max_slope: float, prefer_coast: bool) -> Vector3:
	if terrain_generator:
		return terrain_generator.find_land_point(rng, min_height, max_slope, prefer_coast)
	return Vector3.ZERO

## Get settlements for AI/gameplay
func get_settlements() -> Array:
	if settlement_generator:
		return settlement_generator.get_settlements()
	return []

## Set mesh cache reference (from main.gd)
func set_mesh_cache(cache: Dictionary) -> void:
	_mesh_cache = cache
	if terrain_generator:
		terrain_generator.set_mesh_cache(cache)
	if settlement_generator:
		settlement_generator.set_mesh_cache(cache)
	if prop_generator:
		prop_generator.set_mesh_cache(cache)

## Set material cache reference (from main.gd)
func set_material_cache(cache: Dictionary) -> void:
	_material_cache = cache
	if terrain_generator:
		terrain_generator.set_material_cache(cache)
	if settlement_generator:
		settlement_generator.set_material_cache(cache)
	if prop_generator:
		prop_generator.set_material_cache(cache)
