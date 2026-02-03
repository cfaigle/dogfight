class_name BoatGenerator
extends RefCounted

## Generates stylized procedural boats and buoys for lake scenes

var _lake_defs
var _terrain_generator: TerrainGenerator = null

# Color theming helpers (unique-ish per lake scene)
var _used_accent_indices: Array[int] = []
var _accent_palette: Array[Color] = [
    # Bright accents (good for sails/stripes)
    Color(0.93, 0.29, 0.25), # coral red
    Color(0.98, 0.62, 0.12), # orange
    Color(0.98, 0.86, 0.20), # sun yellow
    Color(0.27, 0.74, 0.41), # fresh green
    Color(0.17, 0.76, 0.76), # cyan
    Color(0.23, 0.52, 0.92), # ocean blue
    Color(0.55, 0.33, 0.95), # purple
    Color(0.93, 0.33, 0.71), # magenta
    Color(0.93, 0.93, 0.93), # bright white (for occasional clean boats)
    Color(0.15, 0.15, 0.18), # near-black (for accents/trim)
]

var _hull_palette_dark: Array[Color] = [
    Color(0.10, 0.16, 0.24), # deep navy
    Color(0.10, 0.24, 0.22), # deep teal
    Color(0.18, 0.10, 0.16), # deep plum
    Color(0.22, 0.16, 0.10), # warm brown
    Color(0.18, 0.18, 0.20), # charcoal
    Color(0.18, 0.26, 0.14), # forest
    Color(0.28, 0.12, 0.12), # burgundy
]

# Comprehensive boat catalog with types, styles, weights, and constraints
var _boat_catalog = {
    # Small craft
    "fishing": {
        "styles": ["lobster", "workboat", "dory"],
        "style_weights": [1.0, 1.0, 0.8],
        "min_radius": 140.0,
        "spawn_weight": 1.3,
        "mesh_size": Vector3(8, 3, 4),
        "movement_pattern": "trawl"
    },
    "sailboat": {
        "styles": ["sloop", "cutter", "dinghy"],
        "style_weights": [1.2, 0.9, 0.7],
        "min_radius": 140.0,
        "spawn_weight": 1.1,
        "mesh_size": Vector3(9, 12, 4),
        "movement_pattern": "sailing"
    },
    "large_sailboat": {
        "styles": ["yacht", "ketch", "catamaran"],
        "style_weights": [1.0, 0.8, 0.6],
        "min_radius": 220.0,
        "spawn_weight": 0.45,
        "mesh_size": Vector3(14, 18, 6),
        "movement_pattern": "sailing"
    },
    "speedboat": {
        "styles": ["runabout", "sport", "cigarette"],
        "style_weights": [1.0, 1.0, 0.7],
        "min_radius": 160.0,
        "spawn_weight": 0.9,
        "mesh_size": Vector3(7, 2.5, 3),
        "movement_pattern": "racing"
    },
    "pontoon": {
        "styles": ["party", "fishing", "sunshade"],
        "style_weights": [1.0, 0.8, 0.9],
        "min_radius": 150.0,
        "spawn_weight": 0.7,
        "mesh_size": Vector3(10, 4, 5),
        "movement_pattern": "leisure"
    },
    "raft": {
        "styles": ["log_raft", "inflatable", "platform"],
        "style_weights": [0.8, 1.0, 0.7],
        "min_radius": 120.0,
        "spawn_weight": 0.65,
        "mesh_size": Vector3(6, 1.5, 5),
        "movement_pattern": "drift"
    },
    # Larger working boats
    "trawler": {
        "styles": ["stern_trawler", "side_trawler", "longliner"],
        "style_weights": [1.0, 0.8, 0.9],
        "min_radius": 220.0,
        "spawn_weight": 0.55,
        "mesh_size": Vector3(18, 8, 7),
        "movement_pattern": "trawl"
    },
    "tugboat": {
        "styles": ["harbor", "river", "work"],
        "style_weights": [1.0, 0.7, 0.8],
        "min_radius": 240.0,
        "spawn_weight": 0.18,
        "mesh_size": Vector3(16, 9, 8),
        "movement_pattern": "tug"
    },
    "barge": {
        "styles": ["flat", "covered", "container"],
        "style_weights": [1.0, 0.6, 0.8],
        "min_radius": 300.0,
        "spawn_weight": 0.15,
        "mesh_size": Vector3(35, 4, 12),
        "movement_pattern": "cargo"
    },
    # Large ships
    "transport": {
        "styles": ["container", "tanker", "ro_ro"],
        "style_weights": [1.0, 0.8, 0.6],
        "min_radius": 340.0,
        "spawn_weight": 0.25,
        "mesh_size": Vector3(60, 25, 15),
        "movement_pattern": "cargo"
    },
    "liner": {
        "styles": ["classic", "modern", "mega"],
        "style_weights": [0.8, 1.0, 0.5],
        "min_radius": 420.0,
        "spawn_weight": 0.10,
        "mesh_size": Vector3(70, 35, 18),
        "movement_pattern": "cruise"
    },
    "car_carrier": {
        "styles": ["box", "roro"],
        "style_weights": [1.0, 0.8],
        "min_radius": 460.0,
        "spawn_weight": 0.06,
        "mesh_size": Vector3(65, 30, 20),
        "movement_pattern": "cargo"
    },
    "oldtimey": {
        "styles": ["schooner", "galleon", "clipper"],
        "style_weights": [1.0, 0.6, 0.8],
        "min_radius": 360.0,
        "spawn_weight": 0.12,
        "mesh_size": Vector3(40, 35, 12),
        "movement_pattern": "sailing"
    }
}

# Track placed boats for anti-stacking
var _placed_boats: Array[Dictionary] = []

func _init():
    _lake_defs = load("res://resources/defs/lake_defs.tres")

func set_terrain_generator(terrain: TerrainGenerator) -> void:
    _terrain_generator = terrain

func set_lake_defs(defs: LakeDefs) -> void:
    _lake_defs = defs

func generate_boats_and_buoys(ctx: WorldContext, scene_root: Node3D, water_data: Dictionary, scene_type: String, params: Dictionary, rng: RandomNumberGenerator, water_type: String = "lake") -> void:
    if water_type == "river":
        _generate_river_boats_and_buoys(ctx, scene_root, water_data, scene_type, params, rng)
    else:
        _generate_lake_boats_and_buoys(ctx, scene_root, water_data, scene_type, params, rng)

func _generate_lake_boats_and_buoys(ctx: WorldContext, scene_root: Node3D, lake_data: Dictionary, scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    var lake_radius = lake_data.get("radius", 200.0)

    # Reset placed boats for this lake (anti-stacking)
    _placed_boats.clear()

    # Calculate boat count based on density and lake size
    var boat_count = _calculate_boat_count(lake_radius, scene_type, params, rng)
    boat_count = min(boat_count, params.get("max_boats_per_lake", 24))

    # Generate boats with weighted selection
    for i in range(boat_count):
        # Select boat type using weighted selection with min radius constraints
        var boat_type = _select_weighted_boat_type(scene_type, lake_radius, rng)
        if boat_type == "":
            continue

        # Try to find non-overlapping position (anti-stacking)
        var boat_pos = _generate_boat_position_with_clearance(lake_center, lake_radius, boat_type, rng)
        if boat_pos == Vector3.ZERO:
            continue  # Couldn't find clearance

        # Select style for this boat
        var style = _select_boat_style(boat_type, rng)

        # Create boat with style
        var boat = _create_stylized_boat_with_style(boat_type, style, boat_pos, lake_radius, rng)
        if not boat:
            continue

        # Record placed boat for anti-stacking
        var mesh_size = _boat_catalog[boat_type]["mesh_size"]
        _placed_boats.append({
            "position": boat_pos,
            "clearance": max(mesh_size.x, mesh_size.z) * 0.6
        })

        scene_root.add_child(boat)

        # Add collision after boat is in scene tree
        print("🚤 DEBUG: Boat '%s' added to scene" % boat.name)
        print("  - Is in tree: %s" % boat.is_inside_tree())
        print("  - Parent: %s" % (boat.get_parent().name if boat.get_parent() else "none"))
        print("  - Global position: %s" % boat.global_position)
        print("  - Has BoatDamageable child: %s" % boat.has_node("BoatDamageable"))

        if CollisionManager:
            print("  - Calling CollisionManager.add_collision_to_object...")
            CollisionManager.add_collision_to_object(boat, "boat")
        else:
            print("⚠️ WARNING: CollisionManager not available for boat '%s'" % boat.name)

    # Generate buoys
    var buoy_count = _calculate_buoy_count(lake_radius, params, rng)
    buoy_count = min(buoy_count, params.get("max_buoys_per_lake", 20))

    for i in range(buoy_count):
        var buoy_type = _select_buoy_type(rng)
        var buoy_pos = _generate_buoy_position(lake_center, lake_radius, rng)
        var buoy = _create_stylized_buoy(buoy_type, buoy_pos, rng)
        scene_root.add_child(buoy)

func _generate_river_boats_and_buoys(ctx: WorldContext, scene_root: Node3D, river_data: Dictionary, scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var points: PackedVector3Array = river_data.get("points", PackedVector3Array())
    var width0: float = float(river_data.get("width0", 12.0))
    var width1: float = float(river_data.get("width1", 44.0))

    print("    [BoatGen] River boats: points=", points.size(), " width0=", width0, " width1=", width1)

    if points.size() < 2:
        print("    [BoatGen] Skipping - too few points")
        return

    # Calculate boat count based on river length and scene type
    # For short rivers (< 10 points), use 1-2 boats max
    var base_count: int
    if points.size() < 10:
        base_count = 1
    else:
        base_count = max(2, int(points.size() / 15))  # ~1 boat per 15 points

    var boat_count: int = base_count if scene_type != "fishing" else max(1, int(base_count * 0.6))
    var min_boat_width: float = params.get("min_river_width_for_boats", 20.0)

    print("    [BoatGen] Attempting ", boat_count, " boats (scene_type: ", scene_type, ")")

    var boats_placed = 0
    # Place boats in wider sections
    for i in range(boat_count):
        var t: float = rng.randf_range(0.3, 1.0)  # Skip narrow upper sections
        var width: float = lerp(width0, width1, pow(t, 0.85))

        if width < min_boat_width:
            continue

        var pos: Vector3 = _get_river_position_at(points, t)
        var direction: Vector3 = _get_river_direction_at(points, t)

        # Offset slightly from center
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()
        var offset: float = rng.randf_range(-0.3, 0.3) * width
        pos += perpendicular * offset

        if _terrain_generator != null:
            pos.y = _terrain_generator.get_height_at(pos.x, pos.z) + 0.18

        # Choose boat type based on width (wider rivers can have bigger boats)
        var boat_type: String
        if width > 50.0:
            # Wide rivers - can have working boats
            var wide_types = ["fishing", "sailboat", "trawler", "tugboat"]
            boat_type = wide_types[rng.randi() % wide_types.size()]
        elif width > 35.0:
            var medium_types = ["fishing", "sailboat", "large_sailboat", "speedboat"]
            boat_type = medium_types[rng.randi() % medium_types.size()]
        else:
            var narrow_types = ["fishing", "raft", "pontoon"]
            boat_type = narrow_types[rng.randi() % narrow_types.size()]

        var style = _select_boat_style(boat_type, rng)
        var boat_rotation: float = atan2(direction.z, direction.x)

        var boat = _create_stylized_boat_with_style(boat_type, style, pos, width, rng)
        if boat:
            boat.rotation.y = boat_rotation
            scene_root.add_child(boat)

            # Add collision after boat is in scene tree
            print("🚤 DEBUG: River boat '%s' added to scene" % boat.name)
            print("  - Is in tree: %s" % boat.is_inside_tree())
            print("  - Parent: %s" % (boat.get_parent().name if boat.get_parent() else "none"))
            print("  - Has BoatDamageable child: %s" % boat.has_node("BoatDamageable"))

            if CollisionManager:
                print("  - Calling CollisionManager.add_collision_to_object...")
                CollisionManager.add_collision_to_object(boat, "boat")
            else:
                print("⚠️ WARNING: CollisionManager not available for river boat '%s'" % boat.name)

            boats_placed += 1

    print("    [BoatGen] Placed ", boats_placed, " boats on river")

    # Place navigation buoys at bends and wide sections
    var buoys_placed = 0
    for i in range(1, points.size() - 1):
        if rng.randf() < 0.15:  # 15% chance per point
            var pos: Vector3 = points[i]
            if _terrain_generator != null:
                pos.y = _terrain_generator.get_height_at(pos.x, pos.z) + 0.12

            var buoy = _create_stylized_buoy("navigation", pos, rng)
            scene_root.add_child(buoy)
            buoys_placed += 1

    print("    [BoatGen] Placed ", buoys_placed, " buoys on river")

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

# Public methods for creating individual boats/buoys (for ocean scattering)

func create_single_boat(position: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    var boat_type: String = config.get("type", "fishing")
    var rotation: float = config.get("rotation", 0.0)

    # For ocean, select random style
    var style = _select_boat_style(boat_type, rng)
    var boat = _create_stylized_boat_with_style(boat_type, style, position, 500.0, rng)
    if boat:
        boat.rotation.y = rotation
    return boat

func create_single_buoy(position: Vector3, buoy_type: String, rng: RandomNumberGenerator) -> Node3D:
    return _create_stylized_buoy(buoy_type, position, rng)

## NEW: Weighted boat type selection with min radius constraints
func _select_weighted_boat_type(scene_type: String, lake_radius: float, rng: RandomNumberGenerator) -> String:
    # Get allowed types for this scene
    var allowed_types = []
    match scene_type:
        "basic":
            return ""  # No boats
        "recreational":
            allowed_types = ["sailboat", "large_sailboat", "speedboat", "pontoon", "raft"]
        "fishing":
            allowed_types = ["fishing", "trawler", "raft"]
        "harbor":
            allowed_types = ["fishing", "trawler", "tugboat", "barge", "transport", "liner", "car_carrier", "oldtimey", "speedboat", "pontoon", "large_sailboat"]
        _:
            allowed_types = ["fishing", "sailboat", "speedboat", "pontoon"]

    # Filter by min radius and calculate adjusted weights
    var valid_types = []
    var weights = []

    for type in allowed_types:
        if not _boat_catalog.has(type):
            continue

        var catalog_entry = _boat_catalog[type]
        var min_r = catalog_entry["min_radius"]

        if lake_radius < min_r:
            continue  # Lake too small

        # Ramp up weight for boats near their min radius (gradual introduction)
        var weight = catalog_entry["spawn_weight"]
        var ramp = clamp(lake_radius / min_r, 0.0, 1.6)
        weight *= ramp

        valid_types.append(type)
        weights.append(weight)

    if valid_types.is_empty():
        return ""

    # Weighted random selection
    var total_weight = 0.0
    for w in weights:
        total_weight += w

    var roll = rng.randf() * total_weight
    var accumulated = 0.0
    for i in range(valid_types.size()):
        accumulated += weights[i]
        if roll <= accumulated:
            return valid_types[i]

    return valid_types[0]  # Fallback

## NEW: Select style for a boat type
func _select_boat_style(boat_type: String, rng: RandomNumberGenerator) -> String:
    if not _boat_catalog.has(boat_type):
        return "default"

    var catalog_entry = _boat_catalog[boat_type]
    var styles = catalog_entry.get("styles", [])
    var style_weights = catalog_entry.get("style_weights", [])

    if styles.is_empty():
        return "default"

    # Weighted selection
    var total_weight = 0.0
    for w in style_weights:
        total_weight += w

    var roll = rng.randf() * total_weight
    var accumulated = 0.0
    for i in range(styles.size()):
        accumulated += style_weights[i]
        if roll <= accumulated:
            return styles[i]

    return styles[0]

## NEW: Generate boat position with anti-stacking clearance
func _generate_boat_position_with_clearance(center: Vector3, radius: float, boat_type: String, rng: RandomNumberGenerator) -> Vector3:
    var mesh_size = _boat_catalog[boat_type]["mesh_size"]
    var clearance = max(mesh_size.x, mesh_size.z) * 0.6

    # Try up to 12 times to find clear spot
    for attempt in range(12):
        var angle = rng.randf() * TAU
        var dist = rng.randf_range(radius * 0.3, radius * 0.85)
        var pos = center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

        # Check clearance from other boats
        var clear = true
        for placed in _placed_boats:
            var dist_to_placed = pos.distance_to(placed["position"])
            if dist_to_placed < (clearance + placed["clearance"]):
                clear = false
                break

        if clear:
            return pos

    return Vector3.ZERO  # Failed to find clearance

## NEW: Create boat with style support
func _create_stylized_boat_with_style(boat_type: String, style: String, position: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Node3D:
    var boat_root = Node3D.new()
    boat_root.position = position
    # Use instance ID to ensure truly unique name (prevents Godot auto-rename to @Node3D@xxxxx)
    boat_root.name = "Boat_" + boat_type + "_" + str(boat_root.get_instance_id())

    # Store metadata
    var mesh_size = _boat_catalog[boat_type]["mesh_size"]
    var movement_pattern = _boat_catalog[boat_type]["movement_pattern"]

    # Generate enhanced color scheme
    var scheme = _generate_enhanced_color_scheme(boat_type, style, rng)

    boat_root.set_meta("boat_type", boat_type)
    boat_root.set_meta("boat_style", style)
    boat_root.set_meta("color_scheme", scheme)
    boat_root.set_meta("accent_color", scheme.get("accent", Color(1, 1, 1)))
    boat_root.set_meta("mesh_size", mesh_size)
    boat_root.set_meta("movement_pattern", movement_pattern)
    boat_root.set_meta("original_position", position)

    # Create geometry based on type and style
    match boat_type:
        "fishing":
            _create_stylized_fishing_boat_new(boat_root, style, scheme, rng)
        "sailboat":
            _create_stylized_sailboat_new(boat_root, style, scheme, rng)
        "large_sailboat":
            _create_stylized_large_sailboat(boat_root, style, scheme, rng)
        "speedboat":
            _create_stylized_speedboat_new(boat_root, style, scheme, rng)
        "pontoon":
            _create_stylized_pontoon_new(boat_root, style, scheme, rng)
        "raft":
            _create_stylized_raft(boat_root, style, scheme, rng)
        "trawler":
            _create_stylized_trawler(boat_root, style, scheme, rng)
        "tugboat":
            _create_stylized_tugboat(boat_root, style, scheme, rng)
        "barge":
            _create_stylized_barge(boat_root, style, scheme, rng)
        "transport":
            _create_stylized_transport(boat_root, style, scheme, rng)
        "liner":
            _create_stylized_liner(boat_root, style, scheme, rng)
        "car_carrier":
            _create_stylized_car_carrier(boat_root, style, scheme, rng)
        "oldtimey":
            _create_stylized_oldtimey_ship(boat_root, style, scheme, rng)
        _:
            _create_generic_boat_fallback(boat_root, scheme, rng)

    # Attach smart movement controller
    _attach_movement_controller(boat_root, boat_type, movement_pattern, lake_radius)

    # === ADD DAMAGE SYSTEM ===

    # Create and attach damageable component
    # NOTE: Collision is registered by calling code AFTER boat is added to scene tree
    # (see add_collision_to_object calls after scene_root.add_child(boat))
    var boat_damageable = BoatDamageableObject.new()
    boat_damageable.name = "BoatDamageable"
    boat_damageable.boat_type = boat_type
    boat_root.add_child(boat_damageable)

    return boat_root

## Attach smart movement controller to boat
func _attach_movement_controller(boat: Node3D, boat_type: String, pattern: String, area_radius: float) -> void:
    var movement_script = load("res://scripts/world/boat/smart_boat_movement.gd")
    if movement_script == null:
        return

    var controller = movement_script.new()
    controller.name = "Movement"
    controller.boat_type = boat_type
    controller.movement_pattern = pattern
    controller.area_radius = area_radius

    # Set speed based on boat type
    match boat_type:
        "speedboat", "racing":
            controller.base_speed = 25.0
        "liner", "transport", "car_carrier", "barge":
            controller.base_speed = 8.0
        "tugboat", "trawler":
            controller.base_speed = 10.0
        "sailboat", "large_sailboat", "oldtimey":
            controller.base_speed = 15.0
        "raft", "drift":
            controller.base_speed = 5.0
        _:
            controller.base_speed = 12.0

    boat.add_child(controller)

    # Setup terrain reference (will be set later)
    if _terrain_generator != null:
        controller.setup(_terrain_generator, Game.sea_level)

## Enhanced color scheme generator
func _generate_enhanced_color_scheme(boat_type: String, style: String, rng: RandomNumberGenerator) -> Dictionary:
    var scheme = {}

    # Base hull color
    var hull_base: Color
    if boat_type in ["liner", "sailboat", "large_sailboat"]:
        # Brighter hulls for passenger/sail craft
        hull_base = Color(0.92, 0.92, 0.94)
    elif boat_type in ["tugboat", "trawler", "barge", "transport", "car_carrier"]:
        # Darker working boat hulls
        hull_base = _hull_palette_dark[rng.randi() % _hull_palette_dark.size()]
    else:
        # Mixed
        if rng.randf() < 0.4:
            hull_base = Color(0.88, 0.88, 0.90)
        else:
            hull_base = _hull_palette_dark[rng.randi() % _hull_palette_dark.size()]

    # Accent color (unique per boat)
    var accent: Color
    if _used_accent_indices.size() < _accent_palette.size():
        var idx = rng.randi() % _accent_palette.size()
        while _used_accent_indices.has(idx):
            idx = (idx + 1) % _accent_palette.size()
        _used_accent_indices.append(idx)
        accent = _accent_palette[idx]
    else:
        # Procedural HSV accent when palette exhausted
        accent = Color.from_hsv(rng.randf(), rng.randf_range(0.6, 0.9), rng.randf_range(0.7, 0.95))

    # Style-specific adjustments
    match style:
        "clipper":
            hull_base = hull_base.darkened(0.3)
        "inflatable":
            hull_base = Color(0.15, 0.15, 0.18)
            accent = Color(0.95, 0.55, 0.15)
        "catamaran":
            # More accent in hull
            hull_base = hull_base.lerp(accent, 0.15)
        "tanker":
            # Industrial dark
            hull_base = hull_base.darkened(0.4)
            accent = accent.darkened(0.3)

    scheme["hull"] = hull_base
    scheme["accent"] = accent
    scheme["deck"] = hull_base.lightened(0.2)
    scheme["cabin"] = hull_base.darkened(0.1)
    scheme["trim"] = accent

    return scheme

## HELPER FUNCTIONS for procedural geometry
func _add_box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mesh_inst = MeshInstance3D.new()
    mesh_inst.name = name
    var box = BoxMesh.new()
    box.size = size
    mesh_inst.mesh = box
    mesh_inst.material_override = mat
    mesh_inst.position = pos
    parent.add_child(mesh_inst)
    return mesh_inst

func _add_cylinder(parent: Node3D, name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
    var mesh_inst = MeshInstance3D.new()
    mesh_inst.name = name
    var cyl = CylinderMesh.new()
    cyl.top_radius = top_r
    cyl.bottom_radius = bottom_r
    cyl.height = height
    cyl.radial_segments = 12
    mesh_inst.mesh = cyl
    mesh_inst.material_override = mat
    mesh_inst.position = pos
    parent.add_child(mesh_inst)
    return mesh_inst

func _add_plane(parent: Node3D, name: String, size: Vector2, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
    var mesh_inst = MeshInstance3D.new()
    mesh_inst.name = name
    var plane = PlaneMesh.new()
    plane.size = size
    mesh_inst.mesh = plane
    mesh_inst.material_override = mat
    mesh_inst.position = pos
    mesh_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0) + rot
    parent.add_child(mesh_inst)
    return mesh_inst

func _create_simple_material(color: Color) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.6
    mat.metallic = 0.1
    return mat

## NEW BOAT GEOMETRY BUILDERS

func _create_stylized_fishing_boat_new(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var accent_mat = _create_simple_material(scheme["accent"])
    var cabin_mat = _create_simple_material(scheme["cabin"])

    # Hull
    _add_box(parent, "Hull", Vector3(8, 2, 3.5), Vector3(0, 0, 0), hull_mat)
    # Cabin
    _add_box(parent, "Cabin", Vector3(3, 1.8, 2.8), Vector3(0, 1.4, -1), cabin_mat)
    # Stripe
    _add_box(parent, "Stripe", Vector3(8.2, 0.3, 3.6), Vector3(0, 1.0, 0), accent_mat)

func _create_stylized_sailboat_new(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var sail_mat = _create_simple_material(scheme["accent"])

    # Hull
    _add_box(parent, "Hull", Vector3(9, 2, 3.8), Vector3(0, 0, 0), hull_mat)

    # Mast
    _add_cylinder(parent, "Mast", 0.15, 0.15, 10, Vector3(0, 5, 0), hull_mat.duplicate())

    # Sail (varies by style)
    var sail_height = 7.0 if style == "sloop" else 6.0
    _add_plane(parent, "Sail", Vector2(6, sail_height), Vector3(0, 5, 0), Vector3(0, 0, 0), sail_mat)

    # Cutter gets jib
    if style == "cutter":
        _add_plane(parent, "Jib", Vector2(3, 4), Vector3(0, 3, 2.5), Vector3(10, 0, 0), sail_mat)

func _create_stylized_large_sailboat(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var sail_mat = _create_simple_material(scheme["accent"])

    if style == "catamaran":
        # Twin hulls
        _add_box(parent, "HullLeft", Vector3(12, 2.5, 2), Vector3(-3, 0, 0), hull_mat)
        _add_box(parent, "HullRight", Vector3(12, 2.5, 2), Vector3(3, 0, 0), hull_mat)
        # Deck platform
        _add_box(parent, "Deck", Vector3(12, 0.5, 6), Vector3(0, 2, 0), hull_mat.duplicate())
    else:
        # Single hull
        _add_box(parent, "Hull", Vector3(14, 3, 5.5), Vector3(0, 0, 0), hull_mat)

    # Main mast
    _add_cylinder(parent, "Mast1", 0.2, 0.2, 15, Vector3(0, 7.5, 0), hull_mat.duplicate())
    _add_plane(parent, "MainSail", Vector2(9, 12), Vector3(0, 7.5, 0), Vector3(0, 0, 0), sail_mat)

    # Ketch gets second mast
    if style == "ketch":
        _add_cylinder(parent, "Mast2", 0.15, 0.15, 10, Vector3(0, 5, -4), hull_mat.duplicate())
        _add_plane(parent, "MizzenSail", Vector2(5, 8), Vector3(0, 5, -4), Vector3(0, 0, 0), sail_mat)

func _create_stylized_speedboat_new(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var accent_mat = _create_simple_material(scheme["accent"])

    # Sleek hull
    _add_box(parent, "Hull", Vector3(7, 1.5, 3), Vector3(0, 0, 0), hull_mat)
    # Windscreen
    _add_box(parent, "Windscreen", Vector3(2, 1, 2.5), Vector3(1, 1, 0), accent_mat)
    # Racing stripe
    _add_box(parent, "Stripe", Vector3(7.2, 0.2, 0.4), Vector3(0, 0.8, 0), accent_mat)

func _create_stylized_pontoon_new(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var deck_mat = _create_simple_material(scheme["deck"])

    # Twin pontoons
    _add_cylinder(parent, "PontoonL", 0.6, 0.6, 10, Vector3(-2, -0.5, 0), hull_mat)
    _add_cylinder(parent, "PontoonR", 0.6, 0.6, 10, Vector3(2, -0.5, 0), hull_mat)
    _add_cylinder(parent, "PontoonL", 0.6, 0.6, 10, Vector3(-2, -0.5, 0), hull_mat).rotation_degrees = Vector3(0, 0, 90)
    _add_cylinder(parent, "PontoonR", 0.6, 0.6, 10, Vector3(2, -0.5, 0), hull_mat).rotation_degrees = Vector3(0, 0, 90)

    # Deck
    _add_box(parent, "Deck", Vector3(10, 0.3, 4.5), Vector3(0, 0.3, 0), deck_mat)

func _create_stylized_raft(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var deck_mat = _create_simple_material(scheme["deck"])

    if style == "log_raft":
        # Log cylinders
        for i in range(5):
            var x_offset = (i - 2) * 1.2
            _add_cylinder(parent, "Log" + str(i), 0.35, 0.35, 6, Vector3(x_offset, 0, 0), hull_mat).rotation_degrees = Vector3(0, 0, 90)
    elif style == "inflatable":
        # Inflatable tubes
        var tube_mat = _create_simple_material(Color(0.15, 0.15, 0.18))
        _add_cylinder(parent, "TubeL", 0.5, 0.5, 6, Vector3(-1.5, 0, 0), tube_mat).rotation_degrees = Vector3(0, 0, 90)
        _add_cylinder(parent, "TubeR", 0.5, 0.5, 6, Vector3(1.5, 0, 0), tube_mat).rotation_degrees = Vector3(0, 0, 90)
        _add_box(parent, "Floor", Vector3(5, 0.2, 3), Vector3(0, 0, 0), deck_mat)
    else:  # platform
        _add_box(parent, "Platform", Vector3(6, 0.4, 5), Vector3(0, 0, 0), deck_mat)

func _create_stylized_trawler(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var cabin_mat = _create_simple_material(scheme["cabin"])
    var accent_mat = _create_simple_material(scheme["accent"])

    # Hull
    _add_box(parent, "Hull", Vector3(18, 3, 6.5), Vector3(0, 0, 0), hull_mat)

    # Cabin position varies by style
    var cabin_z = 2.0 if style == "stern_trawler" else 0.0
    _add_box(parent, "Cabin", Vector3(6, 4, 5), Vector3(0, 3.5, cabin_z), cabin_mat)

    # Superstructure
    _add_box(parent, "Bridge", Vector3(4, 2, 4), Vector3(0, 6, cabin_z), cabin_mat)

    # Accent stripe
    _add_box(parent, "Stripe", Vector3(18.2, 0.4, 6.6), Vector3(0, 1.5, 0), accent_mat)

func _create_stylized_tugboat(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var cabin_mat = _create_simple_material(scheme["cabin"])
    var accent_mat = _create_simple_material(scheme["accent"])

    # Hull
    _add_box(parent, "Hull", Vector3(16, 4, 7.5), Vector3(0, 0, 0), hull_mat)

    # Tall superstructure (distinctive tug profile)
    _add_box(parent, "Cabin", Vector3(8, 5, 6), Vector3(0, 4.5, 0), cabin_mat)
    _add_box(parent, "Bridge", Vector3(6, 2.5, 5), Vector3(0, 7.75, 0), cabin_mat)

    # Fenders (harbor style gets more)
    var fender_count = 4 if style == "harbor" else 2
    for i in range(fender_count):
        var z_pos = (i - fender_count / 2.0) * 3.0
        _add_cylinder(parent, "Fender" + str(i), 0.8, 0.8, 2, Vector3(8.5, 0, z_pos), accent_mat).rotation_degrees = Vector3(0, 0, 90)

func _create_stylized_barge(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var cargo_mat = _create_simple_material(scheme["deck"])

    # Flat hull
    _add_box(parent, "Hull", Vector3(35, 2, 11.5), Vector3(0, 0, 0), hull_mat)

    if style == "covered":
        # Covered cargo hold
        _add_box(parent, "CargoHold", Vector3(30, 3, 10), Vector3(0, 2.5, 0), cargo_mat)
        # Small wheelhouse
        _add_box(parent, "Wheelhouse", Vector3(4, 2, 4), Vector3(-14, 4.5, 0), hull_mat)
    elif style == "container":
        # Container stacks
        for i in range(6):
            var x_pos = (i - 2.5) * 5.5
            _add_box(parent, "Container" + str(i), Vector3(5, 2.5, 8), Vector3(x_pos, 2.25, 0), cargo_mat)

func _create_stylized_transport(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var cargo_mat = _create_simple_material(scheme["deck"])
    var accent_mat = _create_simple_material(scheme["accent"])

    # Large hull
    _add_box(parent, "Hull", Vector3(60, 6, 14), Vector3(0, 0, 0), hull_mat)

    # Superstructure at stern
    _add_box(parent, "Superstructure", Vector3(12, 10, 12), Vector3(-24, 8, 0), hull_mat)

    if style == "tanker":
        # Deck tanks
        for i in range(4):
            var x_pos = (i - 1.5) * 12.0
            _add_cylinder(parent, "Tank" + str(i), 4, 4, 45, Vector3(x_pos, 5, 0), cargo_mat).rotation_degrees = Vector3(0, 0, 90)
    elif style == "ro_ro":
        # Big ro-ro box
        _add_box(parent, "RoRoBox", Vector3(50, 12, 13), Vector3(5, 9, 0), cargo_mat)
    else:  # container
        # Container stacks
        for row in range(5):
            for col in range(2):
                var x_pos = (row - 2) * 11.0
                var y_pos = 5 + col * 2.6
                _add_box(parent, "Container_" + str(row) + "_" + str(col), Vector3(10, 2.4, 12), Vector3(x_pos, y_pos, 0), cargo_mat)

func _create_stylized_liner(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var super_mat = _create_simple_material(scheme["cabin"])
    var accent_mat = _create_simple_material(scheme["accent"])

    # Large hull
    _add_box(parent, "Hull", Vector3(70, 8, 17), Vector3(0, 0, 0), hull_mat)

    # Superstructure layers (mega gets more)
    var layers = 5 if style == "mega" else (4 if style == "modern" else 3)
    for i in range(layers):
        var width = 60 - i * 8
        var y_pos = 8 + i * 5
        _add_box(parent, "Deck" + str(i), Vector3(width, 4.5, 15), Vector3(-5, y_pos, 0), super_mat)

    # Funnel
    _add_cylinder(parent, "Funnel", 3, 2, 12, Vector3(-25, 20, 0), accent_mat)

    # Stripe
    _add_box(parent, "Stripe", Vector3(70.2, 1.2, 17.2), Vector3(0, 4, 0), accent_mat)

func _create_stylized_car_carrier(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var box_mat = _create_simple_material(scheme["deck"])

    # Hull
    _add_box(parent, "Hull", Vector3(65, 7, 19), Vector3(0, 0, 0), hull_mat)

    # Superstructure at stern
    _add_box(parent, "Superstructure", Vector3(14, 12, 16), Vector3(-25.5, 9.5, 0), hull_mat)

    # Car carrier box (proportion varies)
    var box_height = 22 if style == "box" else 18
    _add_box(parent, "CarrierBox", Vector3(48, box_height, 18.5), Vector3(7, box_height / 2.0 + 5, 0), box_mat)

func _create_stylized_oldtimey_ship(parent: Node3D, style: String, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    var sail_mat = _create_simple_material(scheme["accent"])

    # Hull
    _add_box(parent, "Hull", Vector3(40, 5, 11), Vector3(0, 0, 0), hull_mat)

    # Masts (galleon gets 3, others get 2)
    var mast_count = 3 if style == "galleon" else 2
    for i in range(mast_count):
        var x_pos = (i - mast_count / 2.0 + 0.5) * 15.0
        var mast_height = 30 if i == mast_count / 2 else 25
        _add_cylinder(parent, "Mast" + str(i), 0.4, 0.4, mast_height, Vector3(x_pos, mast_height / 2.0 + 4, 0), hull_mat.duplicate())

        # Sails
        var sail_height = mast_height * 0.7
        _add_plane(parent, "Sail" + str(i), Vector2(10, sail_height), Vector3(x_pos, mast_height / 2.0 + 4, 0), Vector3(0, 0, 0), sail_mat)

func _create_generic_boat_fallback(parent: Node3D, scheme: Dictionary, rng: RandomNumberGenerator) -> void:
    var hull_mat = _create_simple_material(scheme["hull"])
    _add_box(parent, "Hull", Vector3(10, 3, 5), Vector3(0, 0, 0), hull_mat)

# Internal boat/buoy creation methods (LEGACY - being replaced)

func _create_stylized_boat(boat_type: String, position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var boat_root = Node3D.new()
    boat_root.position = position
    boat_root.name = "Boat_" + boat_type

    # Per-boat color scheme (stored for LOD + any future animation/variants)
    var scheme := _generate_boat_color_scheme(boat_type, rng)
    boat_root.set_meta("color_scheme", scheme)
    boat_root.set_meta("accent_color", scheme.get("accent", Color(1, 1, 1)))
    
    var boat_config = _lake_defs.boat_types[boat_type]
    
    match boat_type:
        "fishing":
            boat_root = _create_stylized_fishing_boat(boat_root, boat_config, rng, scheme)
        "sailboat":
            boat_root = _create_stylized_sailboat(boat_root, boat_config, rng, scheme)
        "speedboat":
            boat_root = _create_stylized_speedboat(boat_root, boat_config, rng, scheme)
        "pontoon":
            boat_root = _create_stylized_pontoon(boat_root, boat_config, rng, scheme)
    
    # Add movement-ready components (static for now)
    _add_movement_readiness(boat_root, boat_type)
    
    return boat_root

func _create_stylized_fishing_boat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> Node3D:
    # Stylized hull with exaggerated fishing boat features
    var hull_mesh = _create_fishing_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.name = "Hull"
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("fishing", scheme)
    parent.add_child(hull_instance)
    
    # Stylized cabin
    var cabin_mesh = _create_stylized_fishing_cabin(config, rng)
    var cabin_instance = MeshInstance3D.new()
    cabin_instance.name = "Cabin"
    cabin_instance.mesh = cabin_mesh
    cabin_instance.position = Vector3(0, 2.0, -2.0)
    cabin_instance.material_override = _create_stylized_cabin_material(scheme)
    parent.add_child(cabin_instance)
    
    # Fishing equipment (stylized)
    _add_stylized_fishing_gear(parent, rng)
    
    return parent

func _create_stylized_sailboat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> Node3D:
    # Sleek stylized hull
    var hull_mesh = _create_sailboat_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.name = "Hull"
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("sailboat", scheme)
    parent.add_child(hull_instance)
    
    # Stylized mast and sail
    var mast_system = _create_stylized_mast_system(config, rng, scheme)
    mast_system.position = Vector3(0, 0, 0)
    parent.add_child(mast_system)
    
    return parent

func _create_stylized_speedboat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> Node3D:
    # Aerodynamic hull
    var hull_mesh = _create_speedboat_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.name = "Hull"
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("speedboat", scheme)
    parent.add_child(hull_instance)
    
    # Windshield and cockpit
    _add_speedboat_cockpit(parent, config, rng)
    
    # Engine area
    _add_speedboat_engine(parent, config, rng)
    
    return parent

func _create_stylized_pontoon(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> Node3D:
    # Main deck platform
    var deck_mesh = _create_pontoon_deck_mesh(config, rng)
    var deck_instance = MeshInstance3D.new()
    deck_instance.name = "Deck"
    deck_instance.mesh = deck_mesh
    deck_instance.material_override = _create_stylized_boat_material("pontoon", scheme)
    parent.add_child(deck_instance)
    
    # Pontoon tubes
    _add_pontoon_tubes(parent, config, rng, scheme)
    
    # Railings
    _add_pontoon_railings(parent, config, rng)
    
    return parent

func _create_stylized_buoy(buoy_type: String, position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var buoy_root = Node3D.new()
    buoy_root.position = position
    buoy_root.name = "Buoy_" + buoy_type
    
    var buoy_config = _lake_defs.buoy_types[buoy_type]
    
    # Main buoy body
    var body_mesh = CylinderMesh.new()
    body_mesh.height = buoy_config.height
    body_mesh.top_radius = buoy_config.radius
    body_mesh.bottom_radius = buoy_config.radius
    body_mesh.radial_segments = 12
    
    var body_instance = MeshInstance3D.new()
    body_instance.mesh = body_mesh
    body_instance.position = Vector3(0, buoy_config.height * 0.5, 0)
    body_instance.material_override = _create_buoy_material(buoy_config.color)
    buoy_root.add_child(body_instance)
    
    # Add light if specified
    if buoy_config.get("has_light", false):
        _add_buoy_light(buoy_root, buoy_config)
    
    return buoy_root

# --- Boat mesh creation helpers ---

func _create_fishing_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create stylized fishing boat hull (wider, more stable)
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    # Hull vertices (simplified)
    var half_length = size.z * 0.5
    var half_width = size.x * 0.5
    var height = size.y * 0.5
    
    # Bottom hull
    vertices.append(Vector3(-half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    vertices.append(Vector3(-half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.8, height, -half_width * 0.9))
    vertices.append(Vector3(half_length * 1.2, height, -half_width * 0.9))
    vertices.append(Vector3(half_length * 1.2, height, half_width * 0.9))
    vertices.append(Vector3(-half_length * 0.8, height, half_width * 0.9))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(0); indices.append(2); indices.append(3)
    indices.append(4); indices.append(7); indices.append(6)
    indices.append(4); indices.append(6); indices.append(5)
    
    # Side faces
    for i in range(4):
        var next = (i + 1) % 4
        indices.append(i)
        indices.append(next)
        indices.append(i + 4)
        indices.append(next)
        indices.append(next + 4)
        indices.append(i + 4)

    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _create_sailboat_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create sleek sailboat hull (narrower, deeper)
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    var half_length = size.z * 0.5
    var half_width = size.x * 0.4  # Narrower
    var height = size.y * 0.6  # Deeper
    
    # Hull vertices (pointed bow)
    vertices.append(Vector3(-half_length, -height, 0))  # Bow point
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.8, height, 0))  # Top bow
    vertices.append(Vector3(half_length * 1.1, height, -half_width * 0.8))
    vertices.append(Vector3(half_length * 1.1, height, half_width * 0.8))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(3); indices.append(5); indices.append(4)
    
    # Side faces
    indices.append(0); indices.append(3); indices.append(4)
    indices.append(0); indices.append(4); indices.append(1)
    indices.append(1); indices.append(4); indices.append(5)
    indices.append(1); indices.append(5); indices.append(2)
    indices.append(2); indices.append(5); indices.append(3)
    indices.append(2); indices.append(3); indices.append(0)

    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _create_speedboat_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create aerodynamic speedboat hull
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    var half_length = size.z * 0.5
    var half_width = size.x * 0.5
    var height = size.y * 0.4
    
    # Hull vertices (sleek, pointed)
    vertices.append(Vector3(-half_length, -height * 0.5, 0))  # Bow
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.9, height * 0.8, 0))  # Cockpit area
    vertices.append(Vector3(half_length * 1.1, height, -half_width * 0.7))
    vertices.append(Vector3(half_length * 1.1, height, half_width * 0.7))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(3); indices.append(5); indices.append(4)
    
    # Side faces
    indices.append(0); indices.append(3); indices.append(4)
    indices.append(0); indices.append(4); indices.append(1)
    indices.append(1); indices.append(4); indices.append(5)
    indices.append(1); indices.append(5); indices.append(2)
    indices.append(2); indices.append(5); indices.append(3)
    indices.append(2); indices.append(3); indices.append(0)

    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _create_pontoon_deck_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size

    # Create flat deck platform
    var deck_mesh = BoxMesh.new()
    deck_mesh.size = Vector3(size.x * 0.8, 0.3, size.z * 0.9)
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, deck_mesh.get_mesh_arrays())
    return mesh

# --- Boat feature helpers ---

func _create_stylized_fishing_cabin(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var cabin_mesh = BoxMesh.new()
    cabin_mesh.size = Vector3(4.0, 2.5, 3.0)
    var mesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cabin_mesh.get_mesh_arrays())
    return mesh

func _create_stylized_mast_system(config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> Node3D:
    var mast_root = Node3D.new()
    mast_root.name = "MastSystem"
    
    # Mast
    var mast_mesh = CylinderMesh.new()
    mast_mesh.height = config.mesh_size.y * 2.5
    mast_mesh.top_radius = 0.1
    mast_mesh.bottom_radius = 0.15
    
    var mast_instance = MeshInstance3D.new()
    mast_instance.name = "Mast"
    mast_instance.mesh = mast_mesh
    mast_instance.position = Vector3(0, config.mesh_size.y * 1.25, 0)
    mast_instance.material_override = _create_mast_material(scheme)
    mast_root.add_child(mast_instance)
    
    # Sail (stylized triangular sail)
    var sail_mesh = PrismMesh.new()
    sail_mesh.size = Vector3(config.mesh_size.z * 0.6, config.mesh_size.y * 1.8, 0.1)
    sail_mesh.subdivide_width = 2
    sail_mesh.subdivide_depth = 2
    
    var sail_instance = MeshInstance3D.new()
    sail_instance.name = "Sail"
    sail_instance.mesh = sail_mesh
    sail_instance.position = Vector3(config.mesh_size.z * 0.2, config.mesh_size.y * 0.9, 0)
    sail_instance.material_override = _create_sail_material(scheme)
    mast_root.add_child(sail_instance)
    
    return mast_root

func _add_stylized_fishing_gear(parent: Node3D, rng: RandomNumberGenerator) -> void:
    # Fishing nets (stylized)
    var net_mesh = BoxMesh.new()
    net_mesh.size = Vector3(2.0, 0.1, 4.0)
    
    var net_instance = MeshInstance3D.new()
    net_instance.mesh = net_mesh
    net_instance.position = Vector3(0, 1.8, 2.0)
    net_instance.material_override = _create_net_material()
    parent.add_child(net_instance)
    
    # Fishing poles
    for i in range(2):
        var pole_mesh = CylinderMesh.new()
        pole_mesh.height = 3.0
        pole_mesh.top_radius = 0.05
        pole_mesh.bottom_radius = 0.08
        
        var pole_instance = MeshInstance3D.new()
        pole_instance.mesh = pole_mesh
        pole_instance.position = Vector3(1.0 - i * 2.0, 2.5, -1.0)
        pole_instance.rotation_degrees = Vector3(15, 0, 10 - i * 20)
        pole_instance.material_override = _create_pole_material()
        parent.add_child(pole_instance)


func _add_speedboat_cockpit(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Windshield
    var windshield_mesh = PrismMesh.new()
    windshield_mesh.size = Vector3(3.0, 1.5, 0.1)
    
    var windshield_instance = MeshInstance3D.new()
    windshield_instance.mesh = windshield_mesh
    windshield_instance.position = Vector3(0, 1.2, 2.0)
    windshield_instance.rotation_degrees = Vector3(20, 0, 0)
    windshield_instance.material_override = _create_windshield_material()
    parent.add_child(windshield_instance)
    
    # Dashboard
    var dash_mesh = BoxMesh.new()
    dash_mesh.size = Vector3(2.5, 0.1, 1.0)
    
    var dash_instance = MeshInstance3D.new()
    dash_instance.mesh = dash_mesh
    dash_instance.position = Vector3(0, 0.8, 1.5)
    dash_instance.material_override = _create_dashboard_material()
    parent.add_child(dash_instance)


func _add_speedboat_engine(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Engine housing
    var engine_mesh = BoxMesh.new()
    engine_mesh.size = Vector3(1.5, 0.8, 1.2)
    
    var engine_instance = MeshInstance3D.new()
    engine_instance.mesh = engine_mesh
    engine_instance.position = Vector3(0, 0.4, -3.0)
    engine_instance.material_override = _create_engine_material()
    parent.add_child(engine_instance)


func _add_pontoon_tubes(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator, scheme: Dictionary) -> void:
    var size = config.mesh_size
    
    # Left pontoon
    var left_tube = CylinderMesh.new()
    left_tube.height = size.z * 0.8
    left_tube.top_radius = 0.4
    left_tube.bottom_radius = 0.4
    
    var left_instance = MeshInstance3D.new()
    left_instance.name = "PontoonLeft"
    left_instance.mesh = left_tube
    left_instance.position = Vector3(-size.x * 0.4, -0.5, 0)
    left_instance.rotation_degrees = Vector3(90, 0, 0)
    left_instance.material_override = _create_pontoon_material(scheme)
    parent.add_child(left_instance)
    
    # Right pontoon
    var right_instance = MeshInstance3D.new()
    right_instance.name = "PontoonRight"
    right_instance.mesh = left_tube
    right_instance.position = Vector3(size.x * 0.4, -0.5, 0)
    right_instance.rotation_degrees = Vector3(90, 0, 0)
    right_instance.material_override = _create_pontoon_material(scheme)
    parent.add_child(right_instance)


func _add_pontoon_railings(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var size = config.mesh_size
    
    # Simple railing posts
    for i in range(4):
        var post_mesh = CylinderMesh.new()
        post_mesh.height = 1.0
        post_mesh.top_radius = 0.05
        post_mesh.bottom_radius = 0.05
        
        var post_instance = MeshInstance3D.new()
        post_instance.mesh = post_mesh
        post_instance.position = Vector3(
            -size.x * 0.3 + i * size.x * 0.2,
            0.5,
            -size.z * 0.3
        )
        post_instance.material_override = _create_railing_material()
        parent.add_child(post_instance)


# --- Material creation helpers ---

func _jitter_color(c: Color, rng: RandomNumberGenerator, amount: float) -> Color:
    return Color(
        clamp(c.r + rng.randf_range(-amount, amount), 0.0, 1.0),
        clamp(c.g + rng.randf_range(-amount, amount), 0.0, 1.0),
        clamp(c.b + rng.randf_range(-amount, amount), 0.0, 1.0),
        c.a
    )

func _pick_unique_accent_color(rng: RandomNumberGenerator) -> Color:
    if _accent_palette.is_empty():
        return Color(1, 1, 1)

    # Try to avoid repeating accents within this lake scene.
    var chosen_idx := -1
    for _t in range(_accent_palette.size()):
        var candidate := rng.randi_range(0, _accent_palette.size() - 1)
        if not _used_accent_indices.has(candidate):
            chosen_idx = candidate
            break
    if chosen_idx < 0:
        chosen_idx = rng.randi_range(0, _accent_palette.size() - 1)
    if not _used_accent_indices.has(chosen_idx):
        _used_accent_indices.append(chosen_idx)
    return _accent_palette[chosen_idx]

func _generate_boat_color_scheme(boat_type: String, rng: RandomNumberGenerator) -> Dictionary:
    # "Scheme" is a dictionary of Colors keyed by role (hull, accent, sail, etc).
    # Stored on the boat node as metadata so the LOD system can reuse it.
    var scheme: Dictionary = {}

    var accent := _pick_unique_accent_color(rng)
    var accent_dark := accent.darkened(0.35)
    var accent_light := accent.lerp(Color(1, 1, 1), 0.35)

    var boat_white := Color(0.93, 0.93, 0.92)
    var cabin_offwhite := Color(0.88, 0.87, 0.85)
    var wood := Color(0.55, 0.46, 0.36)

    scheme["accent"] = accent
    scheme["trim"] = accent_dark
    scheme["mast"] = wood.lerp(accent_dark, 0.08)

    match boat_type:
        "sailboat":
            # Clean white hull + bright sail.
            scheme["hull"] = _jitter_color(boat_white.lerp(accent, 0.06), rng, 0.02)
            scheme["cabin"] = _jitter_color(Color(0.96, 0.96, 0.95), rng, 0.015)
            scheme["sail"] = _jitter_color(accent_light, rng, 0.02)
        "speedboat":
            # Bold hull; slightly darker trim.
            scheme["hull"] = _jitter_color(accent, rng, 0.03)
            scheme["cabin"] = _jitter_color(cabin_offwhite.lerp(accent_light, 0.08), rng, 0.02)
            scheme["sail"] = accent_light
        "pontoon":
            # Light deck; darker tubes. Keep the look cohesive.
            var deck := _jitter_color(Color(0.86, 0.86, 0.87).lerp(accent, 0.04), rng, 0.02)
            scheme["deck"] = deck
            scheme["hull"] = deck
            scheme["cabin"] = deck
            scheme["tube"] = _jitter_color(accent_dark.lerp(Color(0.22, 0.22, 0.25), 0.35), rng, 0.02)
            scheme["sail"] = accent_light
        "fishing", _:
            # Practical darker hull; cabin slightly warm/off-white with a hint of accent.
            var base := _hull_palette_dark[rng.randi() % _hull_palette_dark.size()]
            scheme["hull"] = _jitter_color(base.lerp(accent_dark, 0.12), rng, 0.02)
            scheme["cabin"] = _jitter_color(cabin_offwhite.lerp(accent_light, 0.06), rng, 0.02)
            scheme["sail"] = accent_light

    return scheme

func _create_stylized_boat_material(boat_type: String, scheme: Dictionary) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()

    var hull_color: Color = scheme.get("hull", Color(0.5, 0.5, 0.5))
    var deck_color: Color = scheme.get("deck", hull_color)
    
    match boat_type:
        "fishing":
            mat.albedo_color = hull_color
            mat.roughness = 0.8
        "sailboat":
            mat.albedo_color = hull_color
            mat.roughness = 0.3
            mat.metallic = 0.1
        "speedboat":
            mat.albedo_color = hull_color
            mat.roughness = 0.18
            mat.metallic = 0.25
        "pontoon":
            mat.albedo_color = deck_color
            mat.roughness = 0.4
        _:
            mat.albedo_color = hull_color
            mat.roughness = 0.5
    
    return mat

func _create_stylized_cabin_material(scheme: Dictionary) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = scheme.get("cabin", Color(0.86, 0.84, 0.80))
    mat.roughness = 0.7
    return mat

func _create_mast_material(scheme: Dictionary) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = scheme.get("mast", Color(0.6, 0.5, 0.4))
    mat.roughness = 0.6
    return mat

func _create_sail_material(scheme: Dictionary) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = scheme.get("sail", scheme.get("accent", Color(0.95, 0.95, 0.9)))
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color.a = 0.9
    mat.roughness = 0.8
    return mat

func _create_net_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.3, 0.1)
    mat.roughness = 0.9
    return mat

func _create_pole_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.2)
    mat.roughness = 0.7
    return mat

func _create_windshield_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.85, 0.9)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color.a = 0.3
    mat.roughness = 0.1
    mat.metallic = 0.1
    return mat

func _create_dashboard_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.1, 0.1)
    mat.roughness = 0.3
    mat.metallic = 0.2
    return mat

func _create_engine_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)
    mat.roughness = 0.4
    mat.metallic = 0.5
    return mat

func _create_pontoon_material(scheme: Dictionary) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = scheme.get("tube", scheme.get("trim", Color(0.7, 0.7, 0.7)))
    mat.roughness = 0.3
    mat.metallic = 0.35
    return mat

func _create_railing_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.8, 0.8)
    mat.roughness = 0.2
    mat.metallic = 0.6
    return mat

func _create_buoy_material(color: Color) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.6
    return mat

# --- Positioning and calculation helpers ---

func _get_boat_types_for_scene(scene_type: String) -> Array[String]:
    # NOTE: Keep this script parse-safe even if the LakeDefs class isn't registered as a global class.
    # We load a .tres Resource and then read its `lake_types` property via Object.get().
    var scene_config: Dictionary = {}
    if _lake_defs != null:
        var lake_types = _lake_defs.get("lake_types")
        if typeof(lake_types) == TYPE_DICTIONARY:
            scene_config = lake_types.get(scene_type, {})
    var boat_types_any = scene_config.get("boat_types", ["fishing"])

    # Convert to a typed Array[String] without relying on Array[String](...) casts (which can break parsing).
    var out: Array[String] = []
    if typeof(boat_types_any) == TYPE_ARRAY:
        for t in boat_types_any:
            out.append(String(t))
    else:
        out.append("fishing")
    return out


func _calculate_boat_count(lake_radius: float, scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> int:
    var base_density = params.get("boat_density_per_lake", 0.4)
    var radius_factor = lake_radius / 200.0  # Normalize to 200m radius
    var count = int(base_density * radius_factor * 4.0)  # Scale by radius
    
    # Adjust based on scene type
    match scene_type:
        "harbor":
            count = int(count * 1.5)  # More boats in harbors
        "fishing":
            count = int(count * 0.8)  # Fewer boats in fishing lakes
        "recreational":
            count = int(count * 1.2)  # More boats in recreational areas
    
    return max(1, count)

func _calculate_buoy_count(lake_radius: float, params: Dictionary, rng: RandomNumberGenerator) -> int:
    var density = params.get("buoy_density_per_radius", 2.0)
    return int(density * lake_radius / 100.0)

func _generate_boat_position(lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Vector3:
    # Generate position within lake, avoiding edges
    var angle = rng.randf() * TAU
    var distance = rng.randf_range(lake_radius * 0.2, lake_radius * 0.8)
    
    var pos = lake_center + Vector3(
        cos(angle) * distance,
        0,
        sin(angle) * distance
    )
    
    return pos

func _generate_buoy_position(lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Vector3:
    # Buoys tend to be closer to shore or in navigation channels
    var angle = rng.randf() * TAU
    var distance = rng.randf_range(lake_radius * 0.6, lake_radius * 0.95)
    
    var pos = lake_center + Vector3(
        cos(angle) * distance,
        0,
        sin(angle) * distance
    )
    
    return pos

func _select_buoy_type(rng: RandomNumberGenerator) -> String:
    var types = ["navigation", "marker", "racing", "mooring"]
    var weights = [0.4, 0.3, 0.2, 0.1]  # Navigation buoys most common
    
    var total_weight = 0.0
    for w in weights:
        total_weight += w
    
    var roll = rng.randf() * total_weight
    var current_weight = 0.0
    
    for i in range(types.size()):
        current_weight += weights[i]
        if roll <= current_weight:
            return types[i]
    
    return "marker"

func _get_movement_pattern(boat_type: String) -> String:
    var boat_config = _lake_defs.boat_types.get(boat_type, {})
    return boat_config.get("movement_pattern", "static")

func _add_movement_readiness(boat_root: Node3D, boat_type: String) -> void:
    # Add components for future boat movement (static for now)
    var movement_controller = Node3D.new()
    movement_controller.name = "MovementController"
    movement_controller.set_meta("boat_type", boat_type)
    movement_controller.set_meta("is_static", true)  # Start as static
    boat_root.add_child(movement_controller)

func _add_buoy_light(parent: Node3D, config: Dictionary) -> void:
    var light = OmniLight3D.new()
    light.position = Vector3(0, config.height + 0.5, 0)
    light.light_color = config.get("light_color", Color.WHITE)
    light.light_energy = 1.5
    light.omni_range = 10.0
    parent.add_child(light)
