class_name WaterBodiesGenerator
extends RefCounted

## Carves lakes/ponds into the heightmap and returns metadata for water meshes.

var _terrain: TerrainGenerator = null

func set_terrain_generator(t: TerrainGenerator) -> void:
    _terrain = t

func carve_lakes(ctx: WorldContext, params: Dictionary, rng: RandomNumberGenerator) -> Array:
    # DISABLED: Lake generation is currently disabled due to performance/quality issues
    # Return empty array immediately - no lakes generated
    return []

    # ORIGINAL CODE (COMMENTED OUT TO PREVENT COMPILATION):
    # var lakes: Array = []
    # if _terrain == null:
    #     return lakes
    # if ctx.hmap_res <= 0 or ctx.hmap.is_empty():
    #     return lakes
    #
    # var lake_count: int = int(params.get("lake_count", 0))
    # if lake_count <= 0:
    #     return lakes
    #
    # var sea_level: float = float(params.get("sea_level", float(Game.sea_level)))
    # var min_h: float = float(params.get("lake_min_height", sea_level + 35.0))
    # # UI param is in degrees; TerrainGenerator.find_land_point expects slope gradient.
    # var max_slope_deg: float = float(params.get("lake_max_slope", 10.0))
    # var max_slope_grad: float = tan(deg_to_rad(max_slope_deg))
    # var min_r: float = float(params.get("lake_min_radius", 180.0))
    # var max_r: float = float(params.get("lake_max_radius", 620.0))
    # var depth_min: float = float(params.get("lake_depth_min", 8.0))
    # var depth_max: float = float(params.get("lake_depth_max", 30.0))
    #
    # # Carve directly into ctx.hmap (PackedFloat32Array). TerrainGenerator will be updated by the caller.
    # var w: int = ctx.hmap_res + 1
    # for _i in range(lake_count):
    #     var center: Vector3 = _terrain.find_land_point(rng, min_h, max_slope_grad, false)
    #     if center == Vector3.ZERO:
    #         continue
    #     var radius: float = rng.randf_range(min_r, max_r)
    #     var depth: float = rng.randf_range(depth_min, depth_max)
    #     var water_level: float = _terrain.get_height_at(center.x, center.z) - rng.randf_range(1.0, 6.0)
    #     water_level = maxf(water_level, sea_level + 2.0)
    #
    #     _carve_circle(ctx.hmap, w, ctx.hmap_res, ctx.hmap_step, ctx.hmap_half, center.x, center.z, radius, water_level, depth)
    #     lakes.append({
    #         "center": center,
    #         "radius": radius,
    #         "water_level": water_level,
    #         "depth": depth,  # Pass carving depth to visualization
    #     })
    #
    # return lakes

func _carve_circle(hmap: PackedFloat32Array, w: int, res: int, step: float, half: float, cx: float, cz: float, radius: float, water_level: float, depth: float) -> void:
    var r2: float = radius * radius
    var x0: int = int(clamp(floor((cx - radius + half) / step), 0, res))
    var x1: int = int(clamp(ceil((cx + radius + half) / step), 0, res))
    var z0: int = int(clamp(floor((cz - radius + half) / step), 0, res))
    var z1: int = int(clamp(ceil((cz + radius + half) / step), 0, res))

    for z in range(z0, z1 + 1):
        var wz: float = float(z) * step - half
        for x in range(x0, x1 + 1):
            var wx: float = float(x) * step - half
            var dx: float = wx - cx
            var dz: float = wz - cz
            var d2: float = dx * dx + dz * dz
            if d2 > r2:
                continue
            var t: float = sqrt(d2) / radius
            # Bowl profile: deep center, gentle edges
            var bowl: float = 1.0 - t
            bowl = bowl * bowl
            var target: float = water_level - depth * bowl
            var idx: int = z * w + x
            var cur: float = float(hmap[idx])
            if target < cur:
                hmap[idx] = target
