class_name PropGenerator
extends RefCounted

## Handles prop generation: trees, rocks, fields, ponds, barns, boats, beach shacks, WW2 props
## Extracted from main.gd for modularity

var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _prop_lod_roots: Array[Node3D] = []
var _assets = null

func set_mesh_cache(cache: Dictionary) -> void:
	_mesh_cache = cache

func set_material_cache(cache: Dictionary) -> void:
	_material_cache = cache

func set_assets(assets) -> void:
	_assets = assets

## Main generation entry point
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Prop generation stub
	# Original logic from various _build_* functions will be moved here
	pass

## Build WW2 era props (tanks, guns, etc.)
func build_ww2_props(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# WW2 props stub
	pass

## Get prop LOD roots for LOD updates
func get_lod_roots() -> Array[Node3D]:
	return _prop_lod_roots
