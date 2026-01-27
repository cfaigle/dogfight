extends WorldComponentBase
class_name TerrainMeshComponent

func get_priority() -> int:
    return 20

func get_required_params() -> Array[String]:
    return ["terrain_chunk_cells", "terrain_lod_enabled", "terrain_lod0_r", "terrain_lod1_r"]

func get_optional_params() -> Dictionary:
    return {
        "terrain_chunk_cells": 32,
        "terrain_lod_enabled": true,
        "terrain_lod0_r": 6500.0,
        "terrain_lod1_r": 16000.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("TerrainMeshComponent: missing ctx/terrain_generator")
        return

    ctx.terrain_render_root = ctx.terrain_generator.build_terrain(world_root, params, rng)
