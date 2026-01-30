extends RefCounted
class_name WorldContext

## Shared context passed through the modular world generation pipeline.
## Holds deterministic RNG, parameters, caches, and cross-component outputs.

# Core
var world_root: Node3D = null
var rng: RandomNumberGenerator = null
var params: Dictionary = {}

# Determinism / identity
var seed: int = 0

# Optional shared systems
var assets: RefCounted = null
var mesh_cache: Dictionary = {}
var material_cache: Dictionary = {}
var building_kits: Dictionary = {}
var parametric_system: RefCounted = null
var unified_building_system: RefCounted = null

# Generators (set by WorldBuilder)
var terrain_generator: TerrainGenerator = null
var settlement_generator: SettlementGenerator = null
var prop_generator: PropGenerator = null

# Data outputs
var hmap: PackedFloat32Array = PackedFloat32Array()
var hmap_res: int = 0
var hmap_step: float = 0.0
var hmap_half: float = 0.0
var rivers: Array = []

var settlements: Array = []
var prop_lod_groups: Array = []

var runway_spawn: Vector3 = Vector3.ZERO
var terrain_render_root: Node3D = null

# New: world classification / feature outputs
var biome_generator: RefCounted = null
var biome_map: Image = null

var lakes: Array = []
var roads: Array = []

# New: optional helper generators (kept generic to avoid type-hint issues)
var water_bodies_generator: RefCounted = null
var road_network_generator: RefCounted = null
var zoning_generator: RefCounted = null

# World layers: name -> Node3D
var _layers: Dictionary = {}


func setup(root: Node3D, rng_in: RandomNumberGenerator, params_in: Dictionary) -> void:
    world_root = root
    rng = rng_in
    params = params_in
    # Keep a copy of the seed on the context for components that need a stable seed value.
    # (Some generators use this instead of reading RandomNumberGenerator.seed directly.)
    seed = int(rng_in.seed)


func get_layer(name: String) -> Node3D:
    if world_root == null:
        push_error("❌ WorldContext.get_layer: world_root is null!")
        return null

    if _layers.has(name):
        var existing: Node3D = _layers[name] as Node3D
        if existing != null and is_instance_valid(existing):
            # DEBUG: Verify layer is properly connected
            # CRITICAL FIX: Only reattach if layer is genuinely orphaned, not temporarily detached
            if existing.get_parent() == null:
                push_warning("⚠️ Layer '" + name + "' has no parent, reattaching to world_root")
                world_root.add_child(existing)
            elif existing.get_parent() != world_root:
                push_error("❌ Layer '" + name + "' is attached to wrong parent - leaving as-is to avoid data loss")
                print("   🔧 DEBUG: Layer '" + name + "' parent is '", existing.get_parent().name, "' instead of world_root")
            # DO NOT remove and reattach - this causes data loss!
            return existing
        _layers.erase(name)

    var layer := Node3D.new()
    layer.name = name
    
    # DEBUG: Verify world_root is valid before adding child
    if not is_instance_valid(world_root):
        push_error("❌ WorldContext.get_layer: world_root is not valid!")
        return null
    
    world_root.add_child(layer)
    _layers[name] = layer

    return layer


func clear_layers() -> void:
    _layers.clear()

# Custom data storage
var _custom_data: Dictionary = {}

func set_data(key: String, value: Variant) -> void:
    _custom_data[key] = value

func get_data(key: String) -> Variant:
    return _custom_data.get(key, null)

func has_data(key: String) -> bool:
    return _custom_data.has(key)


## Check if a 2D point is inside any lake
func is_in_lake(x: float, z: float, buffer: float = 0.0) -> bool:
    if lakes.is_empty():
        return false

    for lake_data in lakes:
        if not (lake_data is Dictionary):
            continue
        var lake: Dictionary = lake_data as Dictionary
        var center: Vector3 = lake.get("center", Vector3.ZERO)
        var radius: float = float(lake.get("radius", 200.0))

        # Check 2D distance from lake center
        var dx: float = x - center.x
        var dz: float = z - center.z
        var dist_sq: float = dx * dx + dz * dz
        var check_radius: float = radius + buffer

        if dist_sq <= check_radius * check_radius:
            return true

    return false

## Check if a 2D point is too close to any road
func is_on_road(x: float, z: float, buffer: float = 8.0) -> bool:
    var road_lines: Array = []
    if has_data("settlement_road_lines"):
        road_lines = get_data("settlement_road_lines")
    if road_lines.is_empty():
        return false

    for road_data in road_lines:
        if not (road_data is Dictionary):
            continue
        var road: Dictionary = road_data as Dictionary
        var path: PackedVector3Array = road.get("path", PackedVector3Array())
        var width: float = road.get("width", 12.0)
        var check_dist: float = (width * 0.5) + buffer

        # Check distance to each road segment
        for i in range(path.size() - 1):
            var p0: Vector3 = path[i]
            var p1: Vector3 = path[i + 1]
            var dist: float = _distance_to_segment_2d(x, z, p0.x, p0.z, p1.x, p1.z)
            if dist < check_dist:
                return true

    return false


## Distance from point (px, pz) to line segment (ax, az) -> (bx, bz) in 2D
func _distance_to_segment_2d(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    var dx: float = bx - ax
    var dz: float = bz - az
    var len_sq: float = dx * dx + dz * dz

    if len_sq < 0.0001:
        # Segment is a point
        var dpx: float = px - ax
        var dpz: float = pz - az
        return sqrt(dpx * dpx + dpz * dpz)

    # Project point onto line
    var t: float = ((px - ax) * dx + (pz - az) * dz) / len_sq
    t = clamp(t, 0.0, 1.0)

    var closest_x: float = ax + t * dx
    var closest_z: float = az + t * dz

    var dist_x: float = px - closest_x
    var dist_z: float = pz - closest_z
    return sqrt(dist_x * dist_x + dist_z * dist_z)
