extends RefCounted
class_name WorldGen

# Procedural world generator: builds a cached heightmap (for mesh + collision), and generates rivers.
# All outputs are deterministic from the provided seed.

static func generate(params: Dictionary) -> Dictionary:
    var seed: int = int(params.get("seed", 0))
    var size: float = float(params.get("terrain_size", 12000.0))
    var res: int = int(params.get("terrain_res", 192))
    var amp: float = float(params.get("terrain_amp", 180.0))  # Reduced from 260 for less extreme terrain
    var sea_level: float = float(params.get("sea_level", 0.0))
    var runway_len: float = float(params.get("runway_len", 900.0))
    var runway_w: float = float(params.get("runway_w", 80.0))

    var half: float = size * 0.5
    var step: float = size / float(res)

    var rng := RandomNumberGenerator.new()
    rng.seed = seed

    # Base rolling noise - gentler terrain
    var n_base := FastNoiseLite.new()
    n_base.seed = seed
    n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX
    n_base.frequency = float(params.get("noise_freq", 0.0006))  # Reduced frequency for larger features
    n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
    n_base.fractal_octaves = int(params.get("noise_oct", 4))  # Reduced octaves for smoother terrain
    n_base.fractal_gain = float(params.get("noise_gain", 0.45))  # Reduced gain
    n_base.fractal_lacunarity = float(params.get("noise_lac", 2.0))

    # Low frequency mask to create archipelagos (no single boring island).
    var n_mask := FastNoiseLite.new()
    n_mask.seed = seed + 101
    n_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX
    n_mask.frequency = 0.00018
    n_mask.fractal_type = FastNoiseLite.FRACTAL_FBM
    n_mask.fractal_octaves = 3
    n_mask.fractal_gain = 0.60
    n_mask.fractal_lacunarity = 2.2

    # Ridged component for mountains - more localized
    var n_ridge := FastNoiseLite.new()
    n_ridge.seed = seed + 202
    n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
    n_ridge.frequency = 0.0004  # Reduced frequency for larger mountain ranges
    n_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
    n_ridge.fractal_octaves = 3  # Fewer octaves for smoother mountains
    n_ridge.fractal_gain = 0.4   # Reduced gain
    n_ridge.fractal_lacunarity = 2.1

    var hmap := PackedFloat32Array()
    hmap.resize((res + 1) * (res + 1))

    print("  🗺️  WorldGen: Starting heightmap generation (", res + 1, "x", res + 1, " = ", (res + 1) * (res + 1), " cells)")
    # Precompute heightmap.
    for iz in range(res + 1):
        var z: float = -half + float(iz) * step
        for ix in range(res + 1):
            var x: float = -half + float(ix) * step

            # rolling terrain
            var n1: float = n_base.get_noise_2d(x, z)
            var n2: float = n_base.get_noise_2d(x * 0.22, z * 0.22)
            var h: float = (n1 * 0.58 + n2 * 0.42) * amp

            # archipelago mask (0..1-ish) - INCREASED LAND AREA
            var m: float = 0.5 + 0.5 * n_mask.get_noise_2d(x, z)
            # central falloff (keeps readable coastline but allows islands)
            var d: float = Vector2(x, z).length()
            var fall: float = clamp(1.0 - d / (size * 0.80), 0.0, 1.0)  # Increased falloff distance
            var island: float = smoothstep(0.25, 0.65, m) * fall  # More land (lower thresholds)
            h *= island

            # mountains: ridge |noise|^p, mostly inland - more localized
            var r: float = absf(n_ridge.get_noise_2d(x * 0.85, z * 0.85))
            r = pow(r, 2.2)  # Higher power for more defined mountains
            var inland: float = smoothstep(0.25, 0.70, island)
            h += r * amp * 0.6 * inland  # Reduced mountain influence

            # runway flatten rectangle
            var fx: float = clamp(1.0 - absf(x) / (runway_w * 1.55), 0.0, 1.0)
            var fz: float = clamp(1.0 - absf(z) / (runway_len * 0.70), 0.0, 1.0)
            var flat: float = fx * fz
            h = lerp(h, 2.0, flat)

            # sea shaping - GENTLER underwater areas
            if h < sea_level:
                h = sea_level - 8.0 + h * 0.40  # Less aggressive underwater shaping

            hmap[iz * (res + 1) + ix] = h

    print("  ✓ Heightmap generation complete")
    # Rivers: trace downhill on the grid and carve channels.
    # DISABLED: River generation is currently disabled due to performance/quality issues
    print("  🌊 Generating rivers... (DISABLED)")
    var rivers: Array = []  # Empty array - no rivers generated
    # var rivers: Array = _generate_rivers(rng, hmap, res, step, half, sea_level, runway_len, runway_w, params)
    print("    Generated ", rivers.size(), " rivers (DISABLED)")

    # Generate terrain region map for adaptive settlement placement
    var terrain_regions = _generate_terrain_regions(hmap, res, step, sea_level)
    
    return {
        "size": size,
        "res": res,
        "step": step,
        "half": half,
        "sea_level": sea_level,
        "height": hmap,
        "rivers": rivers,
        "terrain_regions": terrain_regions,
    }

# Helper function to get terrain regions for use by other systems
static func get_terrain_regions(world_data: Dictionary) -> Dictionary:
    return world_data.get("terrain_regions", {})


static func _idx(ix: int, iz: int, res: int) -> int:
    return iz * (res + 1) + ix

static func _in_bounds(ix: int, iz: int, res: int) -> bool:
    return ix >= 0 and iz >= 0 and ix <= res and iz <= res

static func _cell_pos(ix: int, iz: int, step: float, half: float) -> Vector2:
    return Vector2(-half + float(ix) * step, -half + float(iz) * step)

static func _height_at(hmap: PackedFloat32Array, ix: int, iz: int, res: int) -> float:
    return float(hmap[_idx(ix, iz, res)])

static func _set_height(hmap: PackedFloat32Array, ix: int, iz: int, res: int, v: float) -> void:
    hmap[_idx(ix, iz, res)] = v

# Classify terrain into regions for adaptive settlement placement
static func _generate_terrain_regions(hmap: PackedFloat32Array, res: int, step: float, sea_level: float) -> Dictionary:
    var regions = {
        "plains": [],
        "hills": [],
        "mountains": [],
        "valleys": []
    }
    
    # Sample terrain at regular intervals
    var sample_step = max(8, res / 24)  # Sample every 8th cell or 24 samples total
    
    for iz in range(0, res + 1, sample_step):
        for ix in range(0, res + 1, sample_step):
            var height = _height_at(hmap, ix, iz, res)
            var slope = _calculate_slope_at(hmap, ix, iz, res, step)
            
            var pos = Vector2i(ix, iz)
            
            # Classify based on height and slope
            if height < sea_level + 5.0:
                if slope < 0.2:
                    regions.plains.append(pos)
                else:
                    regions.valleys.append(pos)
            elif height < sea_level + 40.0:
                if slope < 0.3:
                    regions.plains.append(pos)
                elif slope < 0.6:
                    regions.hills.append(pos)
                else:
                    regions.mountains.append(pos)
            else:
                if slope < 0.4:
                    regions.hills.append(pos)
                else:
                    regions.mountains.append(pos)
    
    print("  🏞️  Terrain regions: Plains=", regions.plains.size(), 
          " Hills=", regions.hills.size(), 
          " Mountains=", regions.mountains.size(),
          " Valleys=", regions.valleys.size())
    
    return regions

# Calculate slope at a grid point
static func _calculate_slope_at(hmap: PackedFloat32Array, ix: int, iz: int, res: int, step: float) -> float:
    var center_h = _height_at(hmap, ix, iz, res)
    
    # Sample neighboring points
    var dx = 1
    var dz = 1
    
    var h_n = center_h
    var h_s = center_h
    var h_e = center_h
    var h_w = center_h
    
    if ix > 0:
        h_w = _height_at(hmap, ix - dx, iz, res)
    if ix < res:
        h_e = _height_at(hmap, ix + dx, iz, res)
    if iz > 0:
        h_n = _height_at(hmap, ix, iz - dz, res)
    if iz < res:
        h_s = _height_at(hmap, ix, iz + dz, res)
    
    # Calculate gradient
    var grad_x = (h_e - h_w) / (2.0 * step)
    var grad_z = (h_s - h_n) / (2.0 * step)
    
    return sqrt(grad_x * grad_x + grad_z * grad_z)


static func _generate_rivers(
        rng: RandomNumberGenerator,
        hmap: PackedFloat32Array,
        res: int,
        step: float,
        half: float,
        sea_level: float,
        runway_len: float,
        runway_w: float,
        params: Dictionary
    ) -> Array:

    print("    → _generate_rivers() called")
    var river_count: int = int(params.get("river_count", 7))
    var min_source_h: float = float(params.get("river_source_min", sea_level + 95.0))

    var runway_excl: float = float(params.get("river_runway_exclusion", 650.0))

    print("    River generation params: count=", river_count, " min_source_h=", min_source_h, " sea_level=", sea_level)

    var rivers: Array = []
    var attempts: int = 0
    var max_attempts: int = river_count * 50
    var failed_height: int = 0
    var failed_runway: int = 0
    var failed_length: int = 0

    while rivers.size() < river_count and attempts < max_attempts:
        attempts += 1

        var ix: int = rng.randi_range(int(res * 0.15), int(res * 0.85))
        var iz: int = rng.randi_range(int(res * 0.15), int(res * 0.85))
        var p2: Vector2 = _cell_pos(ix, iz, step, half)

        # keep away from runway
        if p2.length() < runway_excl:
            failed_runway += 1
            continue

        var h0: float = _height_at(hmap, ix, iz, res)
        if h0 < min_source_h:
            failed_height += 1
            continue

        if failed_height + failed_runway + failed_length < 3:
            print("      Starting river trace from h=", h0, " at attempt #", attempts)
        # downhill trace
        var path_cells: Array[Vector2i] = []
        var visited := {} # Dictionary as set

        var cur := Vector2i(ix, iz)
        var max_steps: int = int(res * 6)
        var ok: bool = true

        for _s in range(max_steps):
            if visited.has(cur):
                ok = false
                break
            visited[cur] = true
            path_cells.append(cur)

            var ch: float = _height_at(hmap, cur.x, cur.y, res)
            if ch <= sea_level + 0.5:
                if failed_length < 3:
                    print("      River reached sea at h=", ch, " after ", path_cells.size(), " cells")
                break

            var best := cur
            var best_h: float = ch

            for dz in [-1, 0, 1]:
                for dx in [-1, 0, 1]:
                    if dx == 0 and dz == 0:
                        continue
                    var nx: int = cur.x + dx
                    var nz: int = cur.y + dz
                    if not _in_bounds(nx, nz, res):
                        continue
                    var nh: float = _height_at(hmap, nx, nz, res)
                    if nh < best_h:
                        best_h = nh
                        best = Vector2i(nx, nz)

            if best == cur:
                # Local minimum
                if failed_length < 3:
                    print("      River stuck at local minimum: h=", ch, " after ", path_cells.size(), " cells")
                # If we're still well above sea level and near the runway,
                # try to escape by moving away from center toward the sea.
                if ch > sea_level + 1.5:
                    var cur_pos: Vector2 = _cell_pos(cur.x, cur.y, step, half)
                    var dist_from_center: float = cur_pos.length()

                    # If we're in the runway area (flat plateau), try to move outward
                    if dist_from_center < runway_len * 0.8:
                        var away_dir: Vector2 = cur_pos.normalized()
                        # Try to step in the direction away from center
                        var try_dx: int = int(sign(away_dir.x))
                        var try_dz: int = int(sign(away_dir.y))

                        var try_x: int = cur.x + try_dx
                        var try_z: int = cur.y + try_dz

                        if _in_bounds(try_x, try_z, res):
                            var try_h: float = _height_at(hmap, try_x, try_z, res)
                            # Accept if not uphill
                            if try_h <= ch + 0.1:
                                cur = Vector2i(try_x, try_z)
                                continue

                # True local minimum or couldn't escape; stop
                break
            cur = best

        if not ok:
            continue

        var min_length: int = int(res * 0.01)  # Lowered from 0.18 to allow short rivers on steep terrain
        if path_cells.size() < min_length:
            if failed_length < 3:
                print("      River attempt #", attempts, " failed length: ", path_cells.size(), " < ", min_length, " (started at h=", h0, ")")
            failed_length += 1
            continue

        # Convert to world polyline (decimate to keep it smooth).
        print("      ✓ River attempt #", attempts, " passed all checks! Length: ", path_cells.size(), " cells")
        var pts := PackedVector3Array()
        var stride: int = 3
        for i in range(0, path_cells.size(), stride):
            var c: Vector2i = path_cells[i]
            var w: Vector2 = _cell_pos(c.x, c.y, step, half)
            pts.append(Vector3(w.x, 0.0, w.y))

        if pts.size() < 2:
            if failed_length < 5:
                print("      River rejected after decimation: ", pts.size(), " points < 2")
            failed_length += 1
            continue

        # Carve a channel along the path.
        _carve_river_channel(rng, hmap, res, step, half, sea_level, path_cells)

        rivers.append({
            "points": pts,
            "width0": rng.randf_range(10.0, 16.0),
            "width1": rng.randf_range(34.0, 58.0),
        })

    print("    River generation complete: ", rivers.size(), " rivers created from ", attempts, " attempts")
    print("    Failed reasons: height=", failed_height, " runway=", failed_runway, " length=", failed_length)
    return rivers


static func _carve_river_channel(
        rng: RandomNumberGenerator,
        hmap: PackedFloat32Array,
        res: int,
        step: float,
        half: float,
        sea_level: float,
        cells: Array[Vector2i]
    ) -> void:

    var n: int = cells.size()
    if n < 8:
        return

    for i in range(n):
        var c: Vector2i = cells[i]
        var t: float = float(i) / float(max(1, n - 1))

        var base_w: float = 8.0
        var end_w: float = 26.0
        var w: float = lerp(base_w, end_w, pow(t, 0.85))
        w += rng.randf_range(-1.0, 1.0)
        w = max(4.0, w)

        var depth: float = lerp(4.0, 14.0, pow(t, 0.90))

        var radius_cells: int = int(ceil((w * 1.15) / step))
        radius_cells = clampi(radius_cells, 1, 20)

        var ch: float = _height_at(hmap, c.x, c.y, res)
        var target_center: float = ch - depth
        target_center = max(target_center, sea_level - 0.75)

        for dz in range(-radius_cells, radius_cells + 1):
            for dx in range(-radius_cells, radius_cells + 1):
                var ix: int = c.x + dx
                var iz: int = c.y + dz
                if not _in_bounds(ix, iz, res):
                    continue

                var dist: float = Vector2(float(dx), float(dz)).length() * step
                if dist > w:
                    continue

                # Smooth carve profile.
                var k: float = 1.0 - (dist / w)
                k = clamp(k, 0.0, 1.0)
                k = k * k * (3.0 - 2.0 * k) # smoothstep

                var h0: float = _height_at(hmap, ix, iz, res)
                var carved: float = lerp(h0, target_center, k * 0.65)
                if carved < h0:
                    _set_height(hmap, ix, iz, res, carved)
