class_name LakeSceneFactory
extends RefCounted

## Main factory for generating detailed lake scenes
## Coordinates boat, dock, and shore feature generation

var _lake_defs: LakeDefs
var _boat_generator: BoatGenerator
var _dock_generator: DockGenerator
var _shore_generator: ShoreFeatureGenerator

func _init():
    _lake_defs = load("res://resources/defs/lake_defs.tres") as LakeDefs
    _boat_generator = BoatGenerator.new()
    _dock_generator = DockGenerator.new()
    _shore_generator = ShoreFeatureGenerator.new()

func generate_lake_scene(ctx: WorldContext, water_data: Dictionary, params: Dictionary, rng: RandomNumberGenerator, lake_defs: LakeDefs) -> Node3D:
    var water_type: String = water_data.get("type", "lake")
    var scene_root = Node3D.new()
    scene_root.name = ("RiverScene_" if water_type == "river" else "LakeScene_") + str(ctx.seed)

    var scene_type = water_data.get("scene_type", "basic")

    print("  [Factory] Generating ", water_type, " scene (type: ", scene_type, ")")

    # Set terrain generator for all generators
    if ctx.terrain_generator != null:
        _shore_generator.set_terrain_generator(ctx.terrain_generator)
        _dock_generator.set_terrain_generator(ctx.terrain_generator)
        _boat_generator.set_terrain_generator(ctx.terrain_generator)

    # Set lake defs
    _shore_generator.set_lake_defs(lake_defs)
    _dock_generator.set_lake_defs(lake_defs)
    _boat_generator.set_lake_defs(lake_defs)

    # Generate shore features (adapted for rivers vs lakes)
    var should_shore = _should_have_shore_detail(scene_type, params, rng)
    print("  [Factory] Shore features: ", should_shore)
    if should_shore:
        _shore_generator.generate_shore_features(ctx, scene_root, water_data, scene_type, rng, water_type)

    # Generate docks/harbors (river-specific placement for rivers)
    var should_docks = _should_have_docks(scene_type, params, rng)
    print("  [Factory] Docks: ", should_docks)
    if should_docks:
        if water_type == "river":
            _dock_generator.generate_river_docks(ctx, scene_root, water_data, scene_type, rng)
        else:
            _dock_generator.generate_docks(ctx, scene_root, water_data, scene_type, rng)

    # Generate boats and buoys (adapted for rivers)
    var should_boats = _should_have_boats(scene_type, params, rng)
    print("  [Factory] Boats: ", should_boats)
    if should_boats:
        _boat_generator.generate_boats_and_buoys(ctx, scene_root, water_data, scene_type, params, rng, water_type)

    # Add scene-wide movement controller (static for now)
    _add_scene_movement_controller(scene_root, water_data, scene_type)

    print("  [Factory] Scene generation complete")
    return scene_root

func _should_have_shore_detail(scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> bool:
    if scene_type == "basic":
        return false
    return rng.randf() <= params.get("shore_feature_probability", 0.7)

func _should_have_docks(scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> bool:
    if scene_type == "basic":
        return false
    return rng.randf() <= params.get("dock_probability", 0.5)

func _should_have_boats(scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> bool:
    if scene_type == "basic":
        return false
    return true

func _add_scene_movement_controller(scene_root: Node3D, lake_data: Dictionary, scene_type: String) -> void:
    var movement_controller = Node3D.new()
    movement_controller.name = "LakeSceneMovementController"
    
    # Store metadata for future movement implementation
    movement_controller.set_meta("is_enabled", false)  # Start disabled
    movement_controller.set_meta("lake_data", lake_data)
    movement_controller.set_meta("scene_type", scene_type)
    movement_controller.set_meta("boat_nodes", [])  # Will be populated by boats
    
    scene_root.add_child(movement_controller)