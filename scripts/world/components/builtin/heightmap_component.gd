extends WorldComponentBase
class_name HeightmapComponent

const WorldGen = preload("res://scripts/game/world_gen.gd")

func get_priority() -> int:
    return 0

func get_required_params() -> Array[String]:
    return [
        "seed",
        "terrain_size",
        "terrain_res",
        "terrain_amp",
        "sea_level",
        "runway_len",
        "runway_w",
    ]

func get_optional_params() -> Dictionary:
    return {
        "noise_freq": 0.00085,
        "noise_oct": 5,
        "noise_gain": 0.55,
        "noise_lac": 2.0,
        "river_count": 7,
        "river_source_min": 45.0,
        "river_runway_exclusion": 650.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null:
        push_error("HeightmapComponent: missing ctx")
        return

    # WorldGen is deterministic from params.seed
    var out: Dictionary = WorldGen.generate(params)
    ctx.hmap = out.get("height", PackedFloat32Array())
    ctx.hmap_res = int(out.get("res", 0))
    ctx.hmap_step = float(out.get("step", 0.0))
    ctx.hmap_half = float(out.get("half", 0.0))
    ctx.rivers = out.get("rivers", [])
    print("  ✓ HeightmapComponent: Generated ", ctx.rivers.size(), " rivers")

    if ctx.terrain_generator != null:
        ctx.terrain_generator.set_heightmap_data(ctx.hmap, ctx.hmap_res, ctx.hmap_step, ctx.hmap_half)
        ctx.terrain_generator.set_rivers(ctx.rivers)
