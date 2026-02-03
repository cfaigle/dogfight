extends WorldComponentBase
class_name RiverFeaturesComponent

## Adds docks, boats, and shore features to rivers.
## Places features based on river width and position (upper/middle/lower sections).

func get_priority() -> int:
    return 72  # After rivers (generated early) but before final decoration

func get_dependencies() -> Array[String]:
    return ["rivers"]

func get_optional_params() -> Dictionary:
    return {
        "enable_river_features": true,
        "river_dock_chance": 0.3,  # Chance per suitable river section
        "river_boat_chance": 0.2,
        "river_bridge_chance": 0.15,
        "min_river_width_for_docks": 25.0,
        "min_river_width_for_boats": 20.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    print("🏞️ RiverFeaturesComponent: Starting generation")

    if not bool(params.get("enable_river_features", true)):
        print("  ❌ River features disabled in params")
        return

    if ctx == null:
        print("  ❌ Context is null")
        return

    print("  ℹ️  Rivers in context: ", ctx.rivers.size())

    if ctx.rivers.is_empty():
        print("  ❌ No rivers found in context")
        return

    var features_root := Node3D.new()
    features_root.name = "RiverFeatures"
    ctx.get_layer("Props").add_child(features_root)

    var lake_defs: LakeDefs = load("res://resources/defs/lake_defs.tres")
    if lake_defs == null:
        push_warning("RiverFeaturesComponent: Could not load lake_defs.tres")
        return

    print("  ✓ Loaded lake_defs, processing ", ctx.rivers.size(), " rivers")

    # Use unified factory (same as lakes)
    var factory = LakeSceneFactory.new()

    # Generate features for each river
    var river_count = 0
    for river in ctx.rivers:
        river_count += 1
        if not (river is Dictionary):
            continue

        var points: PackedVector3Array = river.get("points", PackedVector3Array())
        var width1: float = float(river.get("width1", 44.0))

        if points.size() < 2:
            print("    ⚠️  River ", river_count, " too short (", points.size(), " points)")
            continue

        # Short rivers (< 6 points) still get basic features but fewer of them
        if points.size() < 6:
            print("    ⚠️  River ", river_count, " is short (", points.size(), " points), will place minimal features")

        # Prepare river data with type marker
        var river_data = river.duplicate()
        river_data["type"] = "river"
        river_data["scene_type"] = _classify_river_scene_type(river)

        print("  🌊 Processing river ", river_count, " (", points.size(), " points, scene_type: ", river_data["scene_type"], ")")

        # Use unified factory (same as lakes)
        var river_scene = factory.generate_lake_scene(ctx, river_data, params, rng, lake_defs)
        if river_scene:
            features_root.add_child(river_scene)

    print("  ✓ River features generation complete")

func _classify_river_scene_type(river: Dictionary) -> String:
    var width1: float = float(river.get("width1", 40.0))
    var points: PackedVector3Array = river.get("points", PackedVector3Array())

    # Wide rivers with long paths = harbor potential
    if width1 > 50.0 and points.size() > 40:
        return "harbor"
    # Medium rivers = recreational
    elif width1 > 35.0:
        return "recreational"
    # Narrow rivers = fishing
    else:
        return "fishing"

# DEPRECATED: Legacy manual generation - kept for reference
# Now using unified LakeSceneFactory for both lakes and rivers
func _generate_river_features(
    parent: Node3D,
    points: PackedVector3Array,
    width0: float,
    width1: float,
    params: Dictionary,
    rng: RandomNumberGenerator,
    lake_defs: LakeDefs
) -> void:
    var min_dock_width: float = float(params.get("min_river_width_for_docks", 25.0))
    var min_boat_width: float = float(params.get("min_river_width_for_boats", 20.0))
    var dock_chance: float = float(params.get("river_dock_chance", 0.3))
    var boat_chance: float = float(params.get("river_boat_chance", 0.2))

    # Sample river at multiple points
    var sample_count: int = max(3, int(points.size() / 4))

    print("    Sampling river at ", sample_count, " points")
    var docks_placed = 0
    var boats_placed = 0

    for i in range(sample_count):
        var t: float = float(i) / float(sample_count - 1)

        # Skip upper sections (too narrow/fast)
        if t < 0.2:
            continue

        var width: float = _get_river_width_at(width0, width1, t)

        # Get position and direction at this point
        var pos: Vector3 = _get_river_position_at(points, t)
        var direction: Vector3 = _get_river_direction_at(points, t)

        # Docks near river mouths and wide sections
        if width >= min_dock_width and rng.randf() < dock_chance:
            _place_river_dock(parent, pos, direction, width, rng, lake_defs, t)
            docks_placed += 1

        # Boats in middle/lower sections
        if width >= min_boat_width and t > 0.3 and rng.randf() < boat_chance:
            _place_river_boat(parent, pos, direction, width, rng, lake_defs)
            boats_placed += 1

    print("    ✓ Placed ", docks_placed, " docks and ", boats_placed, " boats")

func _place_river_dock(
    parent: Node3D,
    center: Vector3,
    direction: Vector3,
    river_width: float,
    rng: RandomNumberGenerator,
    lake_defs: LakeDefs,
    t: float
) -> void:
    # Place dock on one side of the river
    var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
    var side: float = 1.0 if rng.randf() < 0.5 else -1.0
    var dock_offset: float = (river_width * 0.5) + 3.0  # Just beyond river edge

    var dock_pos: Vector3 = center + perpendicular * side * dock_offset
    dock_pos.y = ctx.terrain_generator.get_height_at(dock_pos.x, dock_pos.z)

    # Check if suitable
    if dock_pos.y < Game.sea_level + 0.5:
        return

    # Use dock generator from lake defs
    var dock_generator = load("res://scripts/world/generators/dock_generator.gd").new()
    dock_generator.set_terrain_generator(ctx.terrain_generator)
    dock_generator.set_lake_defs(lake_defs)

    # Determine dock type based on river position
    var dock_type: String = "fishing_pier" if t < 0.7 else "marina_dock"

    var dock_config: Dictionary = {
        "type": dock_type,
        "length": rng.randf_range(15.0, 25.0),
        "width": rng.randf_range(4.0, 6.0),
        "rotation": atan2(direction.z, direction.x) + (PI * 0.5 * side)
    }

    var dock_node: Node3D = dock_generator.create_single_dock(dock_pos, dock_config, rng)
    if dock_node != null:
        parent.add_child(dock_node)

func _place_river_boat(
    parent: Node3D,
    center: Vector3,
    direction: Vector3,
    river_width: float,
    rng: RandomNumberGenerator,
    lake_defs: LakeDefs
) -> void:
    # Place boat in the middle or slightly off-center
    var offset_factor: float = rng.randf_range(-0.3, 0.3)
    var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
    var boat_pos: Vector3 = center + perpendicular * river_width * offset_factor

    boat_pos.y = ctx.terrain_generator.get_height_at(boat_pos.x, boat_pos.z) + 0.18

    # Use boat generator from lake defs
    var boat_generator = load("res://scripts/world/generators/boat_generator.gd").new()
    boat_generator.set_terrain_generator(ctx.terrain_generator)
    boat_generator.set_lake_defs(lake_defs)

    # Choose boat type based on river width
    var boat_type: String = "fishing" if river_width < 35.0 else "sailboat"

    var boat_config: Dictionary = {
        "type": boat_type,
        "rotation": atan2(direction.z, direction.x) + rng.randf_range(-0.2, 0.2)
    }

    var boat_node: Node3D = boat_generator.create_single_boat(boat_pos, boat_config, rng)
    if boat_node != null:
        parent.add_child(boat_node)

        # Add collision after boat is in scene tree
        if CollisionManager:
            CollisionManager.add_collision_to_object(boat_node, "boat")

# Helper functions for river parameterization

func _get_river_position_at(points: PackedVector3Array, t: float) -> Vector3:
    if points.size() < 2:
        return Vector3.ZERO

    var index_float: float = t * float(points.size() - 1)
    var index: int = int(index_float)
    var fraction: float = index_float - float(index)

    if index >= points.size() - 1:
        return points[points.size() - 1]

    return points[index].lerp(points[index + 1], fraction)

func _get_river_direction_at(points: PackedVector3Array, t: float) -> Vector3:
    var index_float: float = t * float(points.size() - 1)
    var index: int = int(index_float)

    var prev_idx: int = max(0, index - 1)
    var next_idx: int = min(points.size() - 1, index + 1)

    var dir: Vector3 = points[next_idx] - points[prev_idx]
    dir.y = 0.0  # Keep horizontal
    return dir.normalized()

func _get_river_width_at(width0: float, width1: float, t: float) -> float:
    return lerp(width0, width1, pow(t, 0.85))
