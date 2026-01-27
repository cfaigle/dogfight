class_name RoadNetworkGenerator
extends RefCounted

## Builds the inter-settlement road/highway network.

var _terrain: TerrainGenerator = null

func set_terrain_generator(t: TerrainGenerator) -> void:
    _terrain = t

func generate(ctx: WorldContext, params: Dictionary, rng: RandomNumberGenerator) -> Array:
    var roads: Array = []
    if _terrain == null:
        return roads
    if ctx.settlements.is_empty():
        return roads

    var enable_roads: bool = bool(params.get("enable_roads", true))
    if not enable_roads:
        return roads

    var road_width: float = float(params.get("road_width", 18.0))
    var highway_width: float = float(params.get("highway_width", road_width * 1.6))
    var smooth: bool = bool(params.get("road_smooth", true))
    var allow_bridges: bool = bool(params.get("allow_bridges", true))

    var road_module := RoadModule.new()
    road_module.set_terrain_generator(_terrain)
    road_module.world_ctx = ctx
    road_module.road_width = road_width
    road_module.road_smooth = smooth
    road_module.allow_bridges = allow_bridges

    # Determine hub = biggest settlement (prefer city)
    var hub: Dictionary = ctx.settlements[0] as Dictionary
    for s in ctx.settlements:
        var sd: Dictionary = s as Dictionary
        if sd.get("type", "") == "city":
            hub = sd
            break

    var hub_center: Vector3 = hub.get("center", Vector3.ZERO)
    if hub_center == Vector3.ZERO:
        return roads

    # Material (cached)
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.roughness = 0.95
    mat.metallic = 0.0
    mat.albedo_color = Color(0.08, 0.08, 0.085)
    mat.uv1_scale = Vector3(0.5, 0.5, 0.5)

    # Create roads root
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var root := Node3D.new()
    root.name = "RoadNetwork"
    infra.add_child(root)

    # Connect hub to all others (trunk)
    for i in range(ctx.settlements.size()):
        var s: Dictionary = ctx.settlements[i] as Dictionary
        if s == hub:
            continue
        var c: Vector3 = s.get("center", Vector3.ZERO)
        if c == Vector3.ZERO:
            continue

        var is_highway: bool = (s.get("type", "") == "town") and hub_center.distance_to(c) > 9000.0
        var w: float = highway_width if is_highway else road_width
        var pts: PackedVector3Array = road_module.generate_road(hub_center, c, {"smooth": smooth, "allow_bridges": allow_bridges})
        var mi: MeshInstance3D = road_module.create_road_mesh(pts, w, mat)
        if mi != null:
            mi.name = "Highway" if is_highway else "Road"
            root.add_child(mi)
            roads.append({"from": hub_center, "to": c, "points": pts, "width": w})

    # Optional: spur roads between nearby non-hub settlements (adds a bit more density)
    var max_spurs: int = int(params.get("road_spur_count", 18))
    for _j in range(max_spurs):
        var a: Dictionary = ctx.settlements[rng.randi_range(0, ctx.settlements.size() - 1)] as Dictionary
        var b: Dictionary = ctx.settlements[rng.randi_range(0, ctx.settlements.size() - 1)] as Dictionary
        if a == b:
            continue
        var pa: Vector3 = a.get("center", Vector3.ZERO)
        var pb: Vector3 = b.get("center", Vector3.ZERO)
        if pa == Vector3.ZERO or pb == Vector3.ZERO:
            continue
        if pa.distance_to(pb) < 2500.0 or pa.distance_to(pb) > 6500.0:
            continue
        var pts2: PackedVector3Array = road_module.generate_road(pa, pb, {"smooth": smooth, "allow_bridges": allow_bridges})
        var mi2: MeshInstance3D = road_module.create_road_mesh(pts2, road_width * 0.85, mat)
        if mi2 != null:
            mi2.name = "Spur"
            root.add_child(mi2)
            roads.append({"from": pa, "to": pb, "points": pts2, "width": road_width * 0.85})

    return roads
