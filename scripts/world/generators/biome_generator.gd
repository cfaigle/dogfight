class_name BiomeGenerator
extends RefCounted

## Lightweight biome classifier.
##
## This intentionally keeps the logic simple and stable (no shader dependency):
## components can query `get_biome_at(x,z)` to drive placement decisions.

enum Biome {
    OCEAN,
    BEACH,
    GRASSLAND,
    FOREST,
    WETLAND,
    DESERT,
    ROCK,
    SNOW,
}

var _terrain: TerrainGenerator = null
var _seed: int = 0
var _sea_level: float = 0.0

var _temp_noise: FastNoiseLite = FastNoiseLite.new()
var _moist_noise: FastNoiseLite = FastNoiseLite.new()

var _temp_scale: float = 0.00013
var _moist_scale: float = 0.00018

var _coast_radius: float = 220.0
var _snow_height: float = 420.0

func setup(seed: int, terrain: TerrainGenerator, params: Dictionary) -> void:
    _seed = seed
    _terrain = terrain
    _sea_level = float(params.get("sea_level", float(Game.sea_level)))
    _temp_scale = float(params.get("biome_temp_scale", _temp_scale))
    _moist_scale = float(params.get("biome_moist_scale", _moist_scale))
    _coast_radius = float(params.get("biome_coast_radius", _coast_radius))
    _snow_height = float(params.get("biome_snow_height", _snow_height))

    _temp_noise.seed = seed ^ 0x51A7
    _temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _temp_noise.frequency = 1.0

    _moist_noise.seed = seed ^ 0xC0FF
    _moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _moist_noise.frequency = 1.0

func get_biome_at(x: float, z: float) -> int:
    if _terrain == null:
        return Biome.GRASSLAND

    var h: float = _terrain.get_height_at(x, z)
    if h < _sea_level - 0.5:
        return Biome.OCEAN

    # Coast / beach band
    if _terrain.is_near_coast(x, z, _coast_radius) and h < _sea_level + 8.0 and _terrain.get_slope_at(x, z) < 22.0:
        return Biome.BEACH

    var slope: float = _terrain.get_slope_at(x, z)
    if slope > 38.0:
        return Biome.ROCK

    # Temperature & moisture fields
    var t: float = _norm01(_temp_noise.get_noise_2d(x * _temp_scale, z * _temp_scale))
    var m: float = _norm01(_moist_noise.get_noise_2d(x * _moist_scale, z * _moist_scale))

    # Altitude pushes toward cold
    var cold: float = clamp((h - (_sea_level + 80.0)) / 420.0, 0.0, 1.0)
    t = clamp(t - cold * 0.55, 0.0, 1.0)

    if h > _snow_height and t < 0.35:
        return Biome.SNOW

    if m > 0.72 and t > 0.45:
        return Biome.WETLAND
    if m > 0.55:
        return Biome.FOREST
    if m < 0.22 and t > 0.55:
        return Biome.DESERT

    return Biome.GRASSLAND

## Compatibility helper: returns biome as a human-readable string.
## Several generators/components expect this method.
func classify(x: float, z: float) -> String:
    var b: int = get_biome_at(x, z)
    return biome_to_string(b)

func biome_to_string(b: int) -> String:
    match b:
        Biome.OCEAN:
            return "Ocean"
        Biome.BEACH:
            return "Beach"
        Biome.GRASSLAND:
            return "Grassland"
        Biome.FOREST:
            return "Forest"
        Biome.WETLAND:
            return "Wetland"
        Biome.DESERT:
            return "Desert"
        Biome.ROCK:
            return "Rock"
        Biome.SNOW:
            return "Snow"
    return "Grassland"

## Builds a biome map image for debug/overlay.
## Called by BiomesComponent; safe to call after setup().
func generate_biome_map(ctx, params: Dictionary) -> Image:
    if _terrain == null and ctx != null and ctx.terrain_generator != null:
        setup(int(ctx.seed), ctx.terrain_generator, params)
    var res: int = int(params.get("biome_map_res", 256))
    var half: float = float(params.get("terrain_size", 18000.0)) * 0.5
    return build_biome_map(res, half)

func is_forest_like(b: int) -> bool:
    return b == Biome.FOREST or b == Biome.WETLAND

func is_water_like(b: int) -> bool:
    return b == Biome.OCEAN

func get_biome_color(b: int) -> Color:
    match b:
        Biome.OCEAN:
            return Color(0.05, 0.10, 0.16)
        Biome.BEACH:
            return Color(0.76, 0.71, 0.52)
        Biome.GRASSLAND:
            return Color(0.22, 0.36, 0.20)
        Biome.FOREST:
            return Color(0.08, 0.24, 0.12)
        Biome.WETLAND:
            return Color(0.12, 0.28, 0.22)
        Biome.DESERT:
            return Color(0.74, 0.64, 0.40)
        Biome.ROCK:
            return Color(0.25, 0.25, 0.25)
        Biome.SNOW:
            return Color(0.90, 0.92, 0.95)
        _:
            return Color(0.50, 0.50, 0.50)

## Debug helper: build a color biome-map image (not used by renderers by default).
func build_biome_map(res: int, world_half_extent: float) -> Image:
    var r: int = max(16, res)
    var img := Image.create(r, r, false, Image.FORMAT_RGBA8)
    for y in range(r):
        for x in range(r):
            var wx: float = lerp(-world_half_extent, world_half_extent, float(x) / float(r - 1))
            var wz: float = lerp(-world_half_extent, world_half_extent, float(y) / float(r - 1))
            var b: int = get_biome_at(wx, wz)
            img.set_pixel(x, y, get_biome_color(b))
    return img

func _norm01(v: float) -> float:
    return clamp(v * 0.5 + 0.5, 0.0, 1.0)
