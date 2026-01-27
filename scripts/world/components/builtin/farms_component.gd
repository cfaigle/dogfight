extends WorldComponentBase
class_name FarmsComponent

## Spawns simple farm field patches around settlements.
## Uses MultiMesh for performance.

func get_priority() -> int:
    return 72

func get_optional_params() -> Dictionary:
    return {
        "farm_patch_count": 14,
        "farm_band": 2600.0,
        "farm_min_size": Vector2(140.0, 120.0),
        "farm_max_size": Vector2(520.0, 420.0),
        "farm_max_slope_deg": 12.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("FarmsComponent: missing ctx/terrain_generator")
        return
    var total: int = int(params.get("farm_patch_count", 0))
    if total <= 0:
        return
    if ctx.settlements.is_empty():
        return

    var props_layer: Node3D = ctx.get_layer("Props")
    var root := Node3D.new()
    root.name = "Farms"
    props_layer.add_child(root)

    var box := BoxMesh.new()
    box.size = Vector3(1.0, 0.4, 1.0)

    # Three crop variants (separate multimeshes so each can have its own material)
    var mmis: Array[MultiMeshInstance3D] = []
    for i in range(3):
        var mmi := MultiMeshInstance3D.new()
        mmi.name = "Fields_%d" % i
        mmi.multimesh = MultiMesh.new()
        mmi.multimesh.mesh = box
        mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
        mmi.multimesh.instance_count = total # upper bound; we'll resize later
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mmi.visible = true

        var mat := StandardMaterial3D.new()
        match i:
            0:
                mat.albedo_color = Color(0.21, 0.26, 0.12) # dark green
            1:
                mat.albedo_color = Color(0.36, 0.30, 0.14) # brown
            _:
                mat.albedo_color = Color(0.50, 0.45, 0.18) # tan
        mat.roughness = 1.0
        mat.metallic = 0.0
        mmi.material_override = mat
        root.add_child(mmi)
        mmis.append(mmi)

    # Candidate settlements (exclude water/industry-only)
    var candidates: Array = []
    for s in ctx.settlements:
        if not (s is Dictionary):
            continue
        var d := s as Dictionary
        var stype: String = str(d.get("type", ""))
        if stype == "industry":
            continue
        candidates.append(d)

    if candidates.is_empty():
        return

    var counts := [0, 0, 0]
    var max_slope_deg: float = float(params.get("farm_max_slope_deg", 12.0))
    var band: float = float(params.get("farm_band", 2600.0))
    var min_sz: Vector2 = params.get("farm_min_size", Vector2(140.0, 120.0))
    var max_sz: Vector2 = params.get("farm_max_size", Vector2(520.0, 420.0))

    # Place patches
    var tries: int = total * 18
    var placed: int = 0
    while placed < total and tries > 0:
        tries -= 1
        var d: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
        var center: Vector3 = d.get("center", Vector3.ZERO)
        var radius: float = float(d.get("radius", 350.0))
        var zones: Dictionary = d.get("zones", {}) as Dictionary
        var r0: float = radius
        var suburb_r: float = float(zones.get("suburb_radius", radius * 1.25))
        # fields start outside settlement/suburb ring
        var inner: float = maxf(suburb_r, r0) + 120.0
        var outer: float = inner + band

        var ang: float = rng.randf_range(-PI, PI)
        var rr: float = inner + sqrt(rng.randf()) * (outer - inner)
        var x: float = center.x + cos(ang) * rr
        var z: float = center.z + sin(ang) * rr
        var h: float = ctx.terrain_generator.get_height_at(x, z)
        if h < Game.sea_level + 0.65:
            continue
        if ctx.terrain_generator.get_slope_at(x, z) > max_slope_deg:
            continue

        # Optional biome gate: avoid rock/snow/beach/desert if biome generator exists
        if ctx.biome_generator != null and (ctx.biome_generator as RefCounted).has_method("classify"):
            var b: String = str((ctx.biome_generator as RefCounted).call("classify", x, z))
            if b in ["Rock", "Snow", "Beach", "Desert"]:
                continue

        var sx: float = rng.randf_range(min_sz.x, max_sz.x)
        var sz: float = rng.randf_range(min_sz.y, max_sz.y)
        var yaw: float = rng.randf_range(-PI, PI)
        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(sx, 0.6, sz))
        var t3 := Transform3D(basis, Vector3(x, h + 0.08, z))

        var idx: int = rng.randi_range(0, 2)
        var mm: MultiMesh = mmis[idx].multimesh
        mm.set_instance_transform(counts[idx], t3)
        counts[idx] += 1
        placed += 1

    # Shrink instance counts to actual
    for i in range(3):
        mmis[i].multimesh.instance_count = counts[i]
