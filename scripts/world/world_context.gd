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
		return null

	if _layers.has(name):
		var existing: Node3D = _layers[name] as Node3D
		if existing != null and is_instance_valid(existing):
			return existing
		_layers.erase(name)

	var layer := Node3D.new()
	layer.name = name
	world_root.add_child(layer)
	_layers[name] = layer
	return layer


func clear_layers() -> void:
	_layers.clear()
