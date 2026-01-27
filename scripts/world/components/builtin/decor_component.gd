extends WorldComponentBase
class_name DecorComponent

## Adds additional set dressing: suburbs, rural houses, small industrial props, beach huts.
## Everything is MultiMesh-based to stay fast.

func get_priority() -> int:
    return 76

func get_optional_params() -> Dictionary:
    return {
        "suburb_house_count": 1800,
        "rural_house_count": 420,
        "industrial_prop_count": 180,
        "beach_hut_count": 260,
        "decor_max_slope_deg": 20.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("DecorComponent: missing ctx/terrain_generator")
        return

    var max_slope: float = float(params.get("decor_max_slope_deg", 20.0))
    var props_layer: Node3D = ctx.get_layer("Props")
    var root := Node3D.new()
    root.name = "Decor"
    props_layer.add_child(root)

    var house_mesh := BoxMesh.new()
    house_mesh.size = Vector3(1.0, 1.0, 1.0)
    var warehouse_mesh := BoxMesh.new()
    warehouse_mesh.size = Vector3(1.0, 1.0, 1.0)

    # --- Suburb houses
    var suburb_total: int = int(params.get("suburb_house_count", 0))
    if suburb_total > 0 and not ctx.settlements.is_empty():
        var mmi := _make_mmi(root, "SuburbHouses", house_mesh, suburb_total, Color(0.46, 0.45, 0.44))
        var placed: int = _place_suburb_houses(mmi.multimesh, suburb_total, max_slope, rng)
        mmi.multimesh.instance_count = placed

    # --- Rural houses (scattered away from settlements)
    var rural_total: int = int(params.get("rural_house_count", 0))
    if rural_total > 0:
        var mmi2 := _make_mmi(root, "RuralHouses", house_mesh, rural_total, Color(0.40, 0.38, 0.36))
        var placed2: int = _place_rural_houses(mmi2.multimesh, rural_total, max_slope, rng)
        mmi2.multimesh.instance_count = placed2

    # --- Industrial props near industry zones (warehouses)
    var ind_total: int = int(params.get("industrial_prop_count", 0))
    if ind_total > 0 and not ctx.settlements.is_empty():
        var mmi3 := _make_mmi(root, "Industry", warehouse_mesh, ind_total, Color(0.22, 0.22, 0.23))
        var placed3: int = _place_industry(mmi3.multimesh, ind_total, max_slope, rng)
        mmi3.multimesh.instance_count = placed3

    # --- Beach huts along coast (simple boxes)
    var beach_total: int = int(params.get("beach_hut_count", 0))
    if beach_total > 0 and ctx.biome_generator != null:
        var mmi4 := _make_mmi(root, "BeachHuts", house_mesh, beach_total, Color(0.65, 0.60, 0.48))
        var placed4: int = _place_beach_huts(mmi4.multimesh, beach_total, max_slope, rng)
        mmi4.multimesh.instance_count = placed4


func _make_mmi(parent: Node3D, name: String, mesh: Mesh, capacity: int, color: Color) -> MultiMeshInstance3D:
    var mmi := MultiMeshInstance3D.new()
    mmi.name = name
    mmi.multimesh = MultiMesh.new()
    mmi.multimesh.mesh = mesh
    mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
    mmi.multimesh.instance_count = capacity
    mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.95
    mmi.material_override = mat
    parent.add_child(mmi)
    return mmi


func _settlement_avoid(p: Vector3, buffer: float) -> bool:
    for s in ctx.settlements:
        if not (s is Dictionary):
            continue
        var d := s as Dictionary
        var c: Vector3 = d.get("center", Vector3.ZERO)
        var r: float = float(d.get("radius", 350.0))
        if p.distance_to(c) < r + buffer:
            return true
    return false


func _place_suburb_houses(mm: MultiMesh, target: int, max_slope: float, rng: RandomNumberGenerator) -> int:
    var candidates: Array = []
    for s in ctx.settlements:
        if not (s is Dictionary):
            continue
        var d := s as Dictionary
        var stype: String = str(d.get("type", ""))
        if stype in ["town", "city"]:
            candidates.append(d)
    if candidates.is_empty():
        return 0

    var placed: int = 0
    var tries: int = target * 10
    while placed < target and tries > 0:
        tries -= 1
        var d: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
        var center: Vector3 = d.get("center", Vector3.ZERO)
        var radius: float = float(d.get("radius", 500.0))
        var zones: Dictionary = d.get("zones", {}) as Dictionary
        var core_r: float = float(zones.get("core_radius", radius * 0.4))
        var suburb_r: float = float(zones.get("suburb_radius", radius * 1.2))
        var inner: float = maxf(core_r, radius * 0.55)
        var outer: float = suburb_r

        var ang: float = rng.randf_range(-PI, PI)
        var rr: float = inner + sqrt(rng.randf()) * maxf(1.0, outer - inner)
        var x: float = center.x + cos(ang) * rr
        var z: float = center.z + sin(ang) * rr
        var h: float = ctx.terrain_generator.get_height_at(x, z)
        if h < Game.sea_level + 0.45:
            continue
        if ctx.terrain_generator.get_slope_at(x, z) > max_slope:
            continue

        var w: float = rng.randf_range(6.0, 12.0)
        var dpth: float = rng.randf_range(6.0, 12.0)
        var hh: float = rng.randf_range(5.5, 10.0)
        var yaw: float = rng.randf_range(-PI, PI)
        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(w, hh, dpth))
        mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, h + hh * 0.5, z)))
        placed += 1

    return placed


func _place_rural_houses(mm: MultiMesh, target: int, max_slope: float, rng: RandomNumberGenerator) -> int:
    var placed: int = 0
    var half: float = float(ctx.params.get("terrain_size", 18000.0)) * 0.5
    var tries: int = target * 18
    var biome_ok := true
    var biomes: RefCounted = ctx.biome_generator if ctx.biome_generator != null else null

    while placed < target and tries > 0:
        tries -= 1
        var x: float = rng.randf_range(-half, half)
        var z: float = rng.randf_range(-half, half)
        var h: float = ctx.terrain_generator.get_height_at(x, z)
        if h < Game.sea_level + 0.55:
            continue
        if ctx.terrain_generator.get_slope_at(x, z) > max_slope:
            continue
        if _settlement_avoid(Vector3(x, h, z), 420.0):
            continue
        if biomes != null and biomes.has_method("classify"):
            var b: String = str(biomes.call("classify", x, z))
            biome_ok = not (b in ["Rock", "Snow", "Desert", "Beach", "Ocean"])
            if not biome_ok:
                continue

        var w: float = rng.randf_range(6.0, 13.0)
        var dpth: float = rng.randf_range(6.0, 13.0)
        var hh: float = rng.randf_range(5.0, 9.0)
        var yaw: float = rng.randf_range(-PI, PI)
        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(w, hh, dpth))
        mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, h + hh * 0.5, z)))
        placed += 1

    return placed


func _place_industry(mm: MultiMesh, target: int, max_slope: float, rng: RandomNumberGenerator) -> int:
    # Use industry centers if zoning ran; else drop near city centers.
    var candidates: Array = []
    for s in ctx.settlements:
        if not (s is Dictionary):
            continue
        var d := s as Dictionary
        var stype: String = str(d.get("type", ""))
        if stype in ["city", "town"]:
            candidates.append(d)
    if candidates.is_empty():
        return 0

    var placed: int = 0
    var tries: int = target * 14
    while placed < target and tries > 0:
        tries -= 1
        var d: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
        var center: Vector3 = d.get("center", Vector3.ZERO)
        var radius: float = float(d.get("radius", 600.0))
        var zones: Dictionary = d.get("zones", {}) as Dictionary
        var ic: Vector3 = zones.get("industry_center", center) as Vector3
        var ir: float = float(zones.get("industry_radius", radius * 0.6))
        var ang: float = rng.randf_range(-PI, PI)
        var rr: float = rng.randf_range(0.0, ir)
        var x: float = ic.x + cos(ang) * rr
        var z: float = ic.z + sin(ang) * rr
        var h: float = ctx.terrain_generator.get_height_at(x, z)
        if h < Game.sea_level + 0.45:
            continue
        if ctx.terrain_generator.get_slope_at(x, z) > max_slope:
            continue

        var w: float = rng.randf_range(18.0, 40.0)
        var dpth: float = rng.randf_range(14.0, 34.0)
        var hh: float = rng.randf_range(8.0, 16.0)
        var yaw: float = rng.randf_range(-PI, PI)
        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(w, hh, dpth))
        mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, h + hh * 0.5, z)))
        placed += 1

    return placed


func _place_beach_huts(mm: MultiMesh, target: int, max_slope: float, rng: RandomNumberGenerator) -> int:
    var biomes: RefCounted = ctx.biome_generator as RefCounted
    if biomes == null or not biomes.has_method("classify"):
        return 0
    var half: float = float(ctx.params.get("terrain_size", 18000.0)) * 0.5
    var placed: int = 0
    var tries: int = target * 28

    while placed < target and tries > 0:
        tries -= 1
        var x: float = rng.randf_range(-half, half)
        var z: float = rng.randf_range(-half, half)
        var b: String = str(biomes.call("classify", x, z))
        if b != "Beach":
            continue
        var h: float = ctx.terrain_generator.get_height_at(x, z)
        if h < Game.sea_level + 0.35:
            continue
        if ctx.terrain_generator.get_slope_at(x, z) > max_slope:
            continue
        # Don't clutter right next to big towns
        if _settlement_avoid(Vector3(x, h, z), 600.0):
            continue

        var w: float = rng.randf_range(7.0, 14.0)
        var dpth: float = rng.randf_range(6.0, 12.0)
        var hh: float = rng.randf_range(4.0, 8.0)
        var yaw: float = rng.randf_range(-PI, PI)
        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(w, hh, dpth))
        mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, h + hh * 0.5, z)))
        placed += 1

    return placed
