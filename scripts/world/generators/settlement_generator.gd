class_name SettlementGenerator
extends RefCounted

## Handles settlement placement, building generation, and roads
## Extracted from main.gd for modularity

var _settlements: Array = []
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _building_kits: Dictionary = {}
var _parametric_system: BuildingParametricSystem = null

func set_mesh_cache(cache: Dictionary) -> void:
	_mesh_cache = cache

func set_material_cache(cache: Dictionary) -> void:
	_material_cache = cache

func set_building_kits(kits: Dictionary) -> void:
	_building_kits = kits

func set_parametric_system(system: BuildingParametricSystem) -> void:
	_parametric_system = system

## Main generation entry point
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Settlement generation stub
	# Original logic from main.gd _build_set_dressing() will be moved here
	pass

## Build roads between settlements
func build_roads(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Road generation stub
	pass

## Get generated settlements
func get_settlements() -> Array:
	return _settlements
