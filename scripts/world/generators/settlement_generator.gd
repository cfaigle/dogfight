class_name SettlementGenerator
extends RefCounted

const RoadModule = preload("res://scripts/world/modules/road_module.gd")
const BUILDING_STYLE_DEFS_RES = preload("res://resources/defs/building_style_defs.tres")

var _terrain: TerrainGenerator = null
var _assets: RefCounted = null
var _world_ctx: RefCounted = null

var _settlements: Array = []
var _prop_lod_groups: Array = []
var _building_style_defs: BuildingStyleDefs = null
var _style_rotation_index: int = 0  # For round-robin style distribution
var _shuffled_styles: Array[String] = []  # Shuffled deck of styles

func set_terrain_generator(t: TerrainGenerator) -> void:
    _terrain = t

    # Load building style definitions (data lives in the .tres; logic lives in the script).
    _building_style_defs = BUILDING_STYLE_DEFS_RES.duplicate(true) as BuildingStyleDefs
    if _building_style_defs != null:
        _building_style_defs.ensure_defaults()

func set_assets(a: RefCounted) -> void:
    _assets = a

func get_settlements() -> Array:
    return _settlements

func get_prop_lod_groups() -> Array:
    return _prop_lod_groups

## PHASE 1: Plan settlement locations (no buildings)
func plan_settlements(params: Dictionary, rng: RandomNumberGenerator, world_ctx: RefCounted) -> Array:
    _settlements = []
    _world_ctx = world_ctx

    if _terrain == null:
        push_error("SettlementGenerator: terrain generator is null")
        return []

    var city_buildings: int = int(params.get("city_buildings", 600))
    var town_count: int = int(params.get("town_count", 5))
    var hamlet_count: int = int(params.get("hamlet_count", 12))

    # City location
    var city_center: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.50, true)
    if city_center == Vector3.ZERO:
        city_center = Vector3(0.0, _terrain.get_height_at(0.0, 0.0), 0.0)
    var city_radius: float = rng.randf_range(520.0, 820.0)
    _settlements.append({
        "type": "city",
        "center": city_center,
        "radius": city_radius,
        "building_count": city_buildings,
        "population": int(float(city_buildings) * 3.5)
    })

    # Town locations
    for _i in range(town_count):
        var c: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.55, false)
        if c == Vector3.ZERO:
            continue
        if _too_close_to_settlements(c, 1200.0):
            continue
        var rad: float = rng.randf_range(300.0, 520.0)
        _settlements.append({
            "type": "town",
            "center": c,
            "radius": rad,
            "building_count": rng.randi_range(220, 420),
            "population": int(float(rng.randi_range(220, 420)) * 3.5)
        })

    # Hamlet locations
    for _i2 in range(hamlet_count):
        var c2: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.65, false)
        if c2 == Vector3.ZERO:
            continue
        if _too_close_to_settlements(c2, 650.0):
            continue
        var rad2: float = rng.randf_range(150.0, 280.0)
        _settlements.append({
            "type": "hamlet",
            "center": c2,
            "radius": rad2,
            "building_count": rng.randi_range(40, 110),
            "population": int(float(rng.randi_range(40, 110)) * 3.5)
        })

    # Print settlement distribution for debugging
    print("🏘️ SettlementGenerator: Generated ", _settlements.size(), " settlements")
    print("   Settlement positions:")
    for i in range(_settlements.size()):
        var settlement = _settlements[i]
        print("     ", i, ": type='", settlement.type, "' pos=(", settlement.center.x, ", ", settlement.center.z, ")")

    return _settlements

## PHASE 2: Place buildings along roads (called after all roads exist)
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator, parametric_system: RefCounted, world_ctx: RefCounted) -> Dictionary:
    _settlements = []
    _prop_lod_groups = []
    _world_ctx = world_ctx

    if _terrain == null:
        push_error("SettlementGenerator: terrain generator is null")
        return {"settlements": _settlements, "prop_lod_groups": _prop_lod_groups}

    if _building_style_defs == null:
        _building_style_defs = BUILDING_STYLE_DEFS_RES.duplicate(true) as BuildingStyleDefs
        if _building_style_defs != null:
            _building_style_defs.ensure_defaults()
    var infra_root: Node3D = world_root
    var props_root: Node3D = infra_root.get_parent() if infra_root.get_parent() is Node3D else infra_root
    # Prefer dedicated Props layer if it exists
    if props_root != infra_root and props_root.get_node_or_null("Props") is Node3D:
        props_root = props_root.get_node("Props")

    var sd := Node3D.new()
    sd.name = "Settlements"
    props_root.add_child(sd)

    # --- Materials / meshes (fast, no external assets required)
    var city_mesh := BoxMesh.new()
    var house_mesh := BoxMesh.new()
    var ind_mesh := BoxMesh.new()

    var mat_city := StandardMaterial3D.new()
    mat_city.albedo_color = Color(0.18, 0.18, 0.20)
    mat_city.roughness = 0.95

    var mat_house := StandardMaterial3D.new()
    mat_house.albedo_color = Color(0.20, 0.20, 0.22)
    mat_house.roughness = 0.95

    var mat_ind := StandardMaterial3D.new()
    mat_ind.albedo_color = Color(0.16, 0.17, 0.16)
    mat_ind.roughness = 0.96

    # --- City
    var city_buildings: int = int(params.get("city_buildings", 600))
    var town_count: int = int(params.get("town_count", 5))
    var hamlet_count: int = int(params.get("hamlet_count", 12))

    var city_center: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.50, true)
    if city_center == Vector3.ZERO:
        city_center = Vector3(0.0, _terrain.get_height_at(0.0, 0.0), 0.0)

    var city_radius: float = rng.randf_range(520.0, 820.0)
    if parametric_system != null:
        _build_cluster_parametric(sd, city_center, city_radius, city_buildings, "commercial", "american_art_deco", parametric_system, rng, 22.0, true, world_ctx)
    else:
        _build_cluster(sd, city_center, city_radius, city_buildings, city_mesh, mat_city, rng, 22.0, true, true)

    # Estimate population: ~3.5 people per building for cities
    var city_population: int = int(float(city_buildings) * 3.5)
    _settlements.append({"type": "city", "center": city_center, "radius": city_radius, "population": city_population})

    # --- Towns
    for _i in range(town_count):
        var c: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.55, false)
        if c == Vector3.ZERO:
            continue
        if _too_close_to_settlements(c, 1200.0):
            continue
        var rad: float = rng.randf_range(300.0, 520.0)
        var town_buildings: int = rng.randi_range(220, 420)

        # Select town style based on regional development level (declare outside if/else for reuse)
        var dev_level: int = _get_development_level()
        var style_label: String = "ww2_european"  # Default for parametric

        if parametric_system != null:
            _build_cluster_parametric(sd, c, rad, town_buildings, "residential", "ww2_european", parametric_system, rng, 26.0, false, world_ctx)
        else:
            # Use round-robin style selection to ensure all styles are used
            var style_id: String = _get_next_style(dev_level, "town", rng)
            var style: BuildingStyle = null
            if _building_style_defs != null:
                style = _building_style_defs.get_style(style_id)

            # Use style-specific material and mesh variations
            var town_mesh: Mesh = _get_style_mesh(style_id, "house")
            var town_mat: Material = _get_style_material(style)

            _build_cluster(sd, c, rad, town_buildings, town_mesh, town_mat, rng, 26.0, false, true)
            style_label = style.display_name if style != null else style_id

        # Estimate population: ~3.0 people per building for towns
        var town_population: int = int(float(town_buildings) * 3.0)
        _settlements.append({"type": "town", "center": c, "radius": rad, "style": style_label, "population": town_population})
            
        # Add small houses around town for variety
        for _i3 in range(3):
            var c3 := c + Vector3(rng.randf_range(-rad, rad), 0.0, rng.randf_range(-rad, rad))
            c3.y = _terrain.get_height_at(c3.x, c3.z)
            if c3.y < Game.sea_level + 6.0:
                continue
            if _terrain.get_slope_at(c3.x, c3.z) > 20.0:
                continue
            if _too_close_to_settlements(c3, 400.0):
                continue

            # Use round-robin style selection for small houses
            var small_house_id: String = _get_next_style(dev_level, "town", rng)
            var small_house_style: BuildingStyle = _building_style_defs.get_style(small_house_id)
            var small_house_mesh: Mesh = _get_style_mesh(small_house_id, "house")
            var small_house_mat: Material = _get_style_material(small_house_style)

            var house_buildings: int = rng.randi_range(12, 30)
            _build_cluster(sd, c3, rng.randf_range(60.0, 120.0), house_buildings, small_house_mesh, small_house_mat, rng, 20.0, false, true)

            # Estimate population: ~3.0 people per building for houses
            var house_population: int = int(float(house_buildings) * 3.0)
            _settlements.append({"type": "house", "center": c3, "radius": 90.0, "style": small_house_id, "population": house_population})

    # --- Hamlets
    for _i2 in range(hamlet_count):
        var c2: Vector3 = _terrain.find_land_point(rng, Game.sea_level + 6.0, 0.65, false)
        if c2 == Vector3.ZERO:
            continue
        if _too_close_to_settlements(c2, 650.0):
            continue
        var rad2: float = rng.randf_range(150.0, 280.0)
        var hamlet_buildings: int = rng.randi_range(40, 110)

        var hamlet_style_id: String = ""  # Declare outside if/else for use in append

        if parametric_system != null:
            _build_cluster_parametric(sd, c2, rad2, hamlet_buildings, "residential", "ww2_european", parametric_system, rng, 30.0, false, world_ctx)
            hamlet_style_id = "ww2_european"
        else:
            # Use round-robin style selection for hamlets too
            var hamlet_dev_level: int = _get_development_level()
            hamlet_style_id = _get_next_style(hamlet_dev_level, "hamlet", rng)
            var hamlet_style: BuildingStyle = _building_style_defs.get_style(hamlet_style_id) if _building_style_defs != null else null
            var hamlet_mesh: Mesh = _get_style_mesh(hamlet_style_id, "house")
            var hamlet_mat: Material = _get_style_material(hamlet_style)

            _build_cluster(sd, c2, rad2, hamlet_buildings, hamlet_mesh, hamlet_mat, rng, 30.0, false, false)

        # Estimate population: ~3.0 people per building for hamlets
        var hamlet_population: int = int(float(hamlet_buildings) * 3.0)
        _settlements.append({"type": "hamlet", "center": c2, "radius": rad2, "style": hamlet_style_id, "population": hamlet_population})

    # --- Small industrial sites near city
    for _j in range(int(params.get("industry_sites", 6))):
        var c3 := city_center + Vector3(rng.randf_range(-1100.0, 1100.0), 0.0, rng.randf_range(-1100.0, 1100.0))
        c3.y = _terrain.get_height_at(c3.x, c3.z)
        if c3.y < Game.sea_level + 6.0:
            continue

        var industry_buildings: int = rng.randi_range(40, 90)
        if parametric_system != null:
            _build_cluster_parametric(sd, c3, rng.randf_range(180.0, 320.0), industry_buildings, "industrial", "industrial_modern", parametric_system, rng, 30.0, false, world_ctx)
        else:
            _build_cluster(sd, c3, rng.randf_range(180.0, 320.0), industry_buildings, ind_mesh, mat_ind, rng, 30.0, false, false)

        # Estimate population: ~2.5 people per building for industry (workers)
        var industry_population: int = int(float(industry_buildings) * 2.5)
        _settlements.append({"type": "industry", "center": c3, "radius": 260.0, "population": industry_population})

    # Print settlement distribution for debugging
    print("🏘️ SettlementGenerator (Phase 2): Generated ", _settlements.size(), " settlements")
    print("   Settlement positions:")
    for i in range(_settlements.size()):
        var settlement = _settlements[i]
        print("     ", i, ": type='", settlement.type, "' pos=(", settlement.center.x, ", ", settlement.center.z, ")")

    return {"settlements": _settlements, "prop_lod_groups": _prop_lod_groups}

func _get_development_level() -> int:
    # Simple heuristic: more cities => more developed architecture options.
    var city_count: int = 0
    for s in _settlements:
        if typeof(s) == TYPE_DICTIONARY and s.get("type", "") == "city":
            city_count += 1

    if city_count < 3:
        return 0
    elif city_count < 6:
        return 1
    elif city_count < 10:
        return 2
    return 3


## Get next building style in round-robin rotation (ensures all styles are used)
func _get_next_style(era: int, settlement_type: String, rng: RandomNumberGenerator) -> String:
    var available_styles: Array[String] = []

    if settlement_type == "town":
        available_styles = _get_town_styles_for_era(era)
    elif settlement_type == "hamlet":
        available_styles = _get_hamlet_styles_for_era(era)
    else:
        available_styles = _get_town_styles_for_era(era)  # Fallback

    if available_styles.is_empty():
        return "medieval_hut"  # Default fallback

    # If shuffled deck is empty or doesn't match current styles, recreate it
    if _shuffled_styles.is_empty() or _shuffled_styles.size() != available_styles.size():
        _shuffled_styles = available_styles.duplicate()
        _shuffled_styles.shuffle()
        _style_rotation_index = 0

    # Get next style from shuffled deck
    var style: String = _shuffled_styles[_style_rotation_index]
    _style_rotation_index = (_style_rotation_index + 1) % _shuffled_styles.size()

    # Reshuffle when we complete a full rotation
    if _style_rotation_index == 0:
        _shuffled_styles.shuffle()

    return style

func _get_town_styles_for_era(era: int) -> Array[String]:
    var styles: Array[String] = []

    if era == 0:  # Medieval towns - 8 styles
        styles = [
            "medieval_hut", "timber_cabin", "stone_cottage", "blacksmith", 
            "windmill", "castle_keep", "market_stall", "monastery"
        ]
    elif era == 1:  # Renaissance towns - 6 styles
        styles = [
            "fjord_house", "white_stucco_house", "stone_farmhouse", 
            "log_chalet", "church", "barn"
        ]
    elif era == 2:  # Industrial towns - 7 styles
        styles = [
            "victorian_mansion", "factory_building", "train_station", 
            "lighthouse", "warehouse", "power_station", "gas_station"
        ]
    else:  # Modern towns - 6 styles
        styles = [
            "trailer_park", "modular_home", "school", "gas_station", 
            "warehouse", "power_station"
        ]

    return styles

func _get_style_mesh(style_id: String, building_type: String) -> Mesh:
    # TODO: swap in real meshes / parametric variants per style.
    var mesh := BoxMesh.new()

    if building_type == "industrial":
        mesh.size = Vector3(10.0, 6.0, 14.0)
    elif building_type == "commercial":
        mesh.size = Vector3(9.0, 10.0, 9.0)
    else:
        mesh.size = Vector3(7.0, 6.0, 7.0)

    return mesh

func _get_style_material(style: BuildingStyle) -> Material:
    var mat := StandardMaterial3D.new()
    mat.roughness = 0.95

    if style == null:
        mat.albedo_color = Color(0.20, 0.20, 0.22)
        return mat

    var props: Dictionary = style.properties if style.properties != null else {}

    if "wall_color" in props:
        mat.albedo_color = props.wall_color
    elif "roof_color" in props:
        mat.albedo_color = props.roof_color
    else:
        mat.albedo_color = Color(0.20, 0.20, 0.22)

    return mat

func _build_cluster(parent: Node3D, center: Vector3, radius: float, count: int, mesh: Mesh, mat: Material, rng: RandomNumberGenerator, max_slope_deg: float, tall: bool, allow_variety: bool) -> void:
    var mmi := MultiMeshInstance3D.new()
    mmi.name = "Cluster_%s" % str(parent.get_child_count())
    mmi.multimesh = MultiMesh.new()
    mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
    mmi.multimesh.instance_count = 0
    mmi.multimesh.mesh = mesh
    mmi.material_override = mat
    parent.add_child(mmi)

    var transforms: Array[Transform3D] = []
    transforms.resize(count)
    var written: int = 0

    # Get/create spatial collision grid for buildings
    var collision_grid: Dictionary = {}
    var grid_cell_size: float = 15.0  # 15m cells for collision detection
    if _world_ctx != null:
        if _world_ctx.has_data("building_collision_grid"):
            collision_grid = _world_ctx.get_data("building_collision_grid")
        else:
            _world_ctx.set_data("building_collision_grid", collision_grid)

    # Get ALL roads from master planner (unified network)
    var all_roads: Array = []
    if _world_ctx != null:
        if _world_ctx.has_data("master_roads"):
            all_roads = _world_ctx.get_data("master_roads")
        # Fallback to old system if master_roads not available
        elif _world_ctx.has_data("regional_roads"):
            all_roads.append_array(_world_ctx.get_data("regional_roads"))
            if _world_ctx.has_data("settlement_road_lines"):
                var settlement_lines: Array = _world_ctx.get_data("settlement_road_lines")
                all_roads.append_array(settlement_lines)

    var tries: int = 0
    var max_tries: int = count * 12  # More tries since we're stricter about placement
    while written < count and tries < max_tries:
        tries += 1

        # 95% chance to place along road (STRONGLY prefer road placement for vehicles)
        var use_road: bool = all_roads.size() > 0 and rng.randf() < 0.95
        var x: float
        var z: float
        var yaw: float

        if use_road:
            # Place building along a random road (regional or settlement)
            var road_data: Dictionary = all_roads[rng.randi() % all_roads.size()]
            var road_path: PackedVector3Array = road_data.get("path", PackedVector3Array())
            if road_path.size() < 2:
                use_road = false
            else:
                # Pick random point along road
                var road_idx: int = rng.randi_range(0, road_path.size() - 1)
                var road_point: Vector3 = road_path[road_idx]

                # Check if road point is within settlement radius
                if road_point.distance_to(center) > radius:
                    use_road = false
                else:
                    # Place building offset from road (setback for frontage + parking)
                    var road_width: float = road_data.get("width", 12.0)
                    var setback: float = rng.randf_range(road_width + 4.0, road_width + 12.0)  # 4-12m setback

                    # Calculate road direction for perpendicular offset
                    var road_dir: Vector3
                    if road_idx < road_path.size() - 1:
                        road_dir = (road_path[road_idx + 1] - road_point).normalized()
                    elif road_idx > 0:
                        road_dir = (road_point - road_path[road_idx - 1]).normalized()
                    else:
                        road_dir = Vector3.RIGHT

                    # Perpendicular offset (left or right of road)
                    var perp: Vector3 = Vector3(-road_dir.z, 0, road_dir.x).normalized()
                    var offset_dir: Vector3 = perp if rng.randf() < 0.5 else -perp

                    x = road_point.x + offset_dir.x * setback
                    z = road_point.z + offset_dir.z * setback

                    # Building faces the road
                    yaw = atan2(-offset_dir.x, -offset_dir.z)

        if not use_road:
            # Random placement (fallback)
            var ang: float = rng.randf_range(0.0, TAU)
            var r: float = radius * sqrt(rng.randf())
            x = center.x + cos(ang) * r
            z = center.z + sin(ang) * r
            yaw = rng.randf_range(-PI, PI)

        # Validate placement
        var h: float = _terrain.get_height_at(x, z)
        if h < Game.sea_level + 0.45:
            continue
        if _terrain.get_slope_at(x, z) > max_slope_deg:
            continue

        # Check if in lake
        if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
            if _world_ctx.is_in_lake(x, z, 10.0):
                continue

        # Create building transform
        var base_w: float = rng.randf_range(8.0, 16.0)
        var base_d: float = rng.randf_range(8.0, 16.0)
        var base_h: float = rng.randf_range(10.0, 22.0)
        if tall:
            base_h = rng.randf_range(18.0, 68.0)
        if allow_variety and rng.randf() < 0.18:
            base_w *= 1.8
            base_d *= 1.4
            base_h *= 0.55

        # Check collision with other buildings (using spatial grid)
        var footprint_radius: float = sqrt(base_w * base_w + base_d * base_d) * 0.5 + 2.0  # +2m buffer
        if _check_building_collision(collision_grid, x, z, footprint_radius, grid_cell_size):
            continue  # Collision detected, skip this placement

        var basis := Basis(Vector3.UP, yaw)
        basis = basis.scaled(Vector3(base_w, base_h, base_d))
        var t3 := Transform3D(basis, Vector3(x, h + base_h * 0.5, z))
        transforms[written] = t3
        written += 1

        # Mark this area as occupied in the collision grid
        _mark_building_in_grid(collision_grid, x, z, footprint_radius, grid_cell_size)

    mmi.multimesh.instance_count = written
    for i in range(written):
        mmi.multimesh.set_instance_transform(i, transforms[i])

func _build_cluster_parametric(
    parent: Node3D,
    center: Vector3,
    radius: float,
    count: int,
    building_type: String,  # "residential", "commercial", "industrial"
    style: String,  # "ww2_european", "american_art_deco", "industrial_modern"
    parametric_system: RefCounted,
    rng: RandomNumberGenerator,
    max_slope_deg: float,
    tall: bool,
    world_ctx: RefCounted = null
) -> void:
    if parametric_system == null:
        return

    # Get/create spatial collision grid for buildings
    var collision_grid: Dictionary = {}
    var grid_cell_size: float = 15.0  # 15m cells for collision detection
    if world_ctx != null:
        if world_ctx.has_data("building_collision_grid"):
            collision_grid = world_ctx.get_data("building_collision_grid")
        else:
            world_ctx.set_data("building_collision_grid", collision_grid)

    var placed: int = 0
    var tries: int = 0
    var max_tries: int = count * 8
    var skipped_on_road: int = 0

    while placed < count and tries < max_tries:
        tries += 1

        # Find position (existing logic)
        var ang: float = rng.randf_range(0.0, TAU)
        var r: float = radius * sqrt(rng.randf())
        var x: float = center.x + cos(ang) * r
        var z: float = center.z + sin(ang) * r
        var h: float = _terrain.get_height_at(x, z)

        # Slope/water checks (existing)
        if h < Game.sea_level + 0.45:
            continue
        if _terrain.get_slope_at(x, z) > max_slope_deg:
            continue

        # Check if in lake (avoid placing buildings in lakes)
        if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
            if _world_ctx.is_in_lake(x, z, 10.0):  # 10m buffer from lake edge
                continue

        # Check if on road (avoid placing buildings on roads)
        if world_ctx != null and world_ctx.has_method("is_on_road"):
            if world_ctx.is_on_road(x, z, 12.0):  # 12m buffer from road
                skipped_on_road += 1
                continue

        # Building dimensions
        var width: float = rng.randf_range(8.0, 16.0)
        var depth: float = rng.randf_range(8.0, 16.0)
        var height: float = rng.randf_range(12.0, 24.0) if tall else rng.randf_range(8.0, 18.0)
        var floors: int = max(1, int(height / 4.0))  # Multi-story!

        # Check collision with other buildings (using spatial grid)
        var footprint_radius: float = sqrt(width * width + depth * depth) * 0.5 + 2.0  # +2m buffer
        if _check_building_collision(collision_grid, x, z, footprint_radius, grid_cell_size):
            continue  # Collision detected, skip this placement

        # Generate parametric building
        var mesh: Mesh = parametric_system.create_parametric_building(
            building_type,
            style,
            width,
            depth,
            height,
            floors,
            1  # quality level (0=low, 1=medium, 2=high)
        )

        if mesh != null:
            var mi := MeshInstance3D.new()
            mi.mesh = mesh
            mi.position = Vector3(x, h, z)
            mi.rotation.y = rng.randf_range(-PI, PI)
            parent.add_child(mi)
            placed += 1

            # Mark this area as occupied in the collision grid
            _mark_building_in_grid(collision_grid, x, z, footprint_radius, grid_cell_size)

func _too_close_to_settlements(p: Vector3, buffer: float) -> bool:
    for s in _settlements:
        if not (s is Dictionary):
            continue
        var c: Vector3 = (s as Dictionary).get("center", Vector3.ZERO)
        var r: float = float((s as Dictionary).get("radius", 300.0))
        if p.distance_to(c) < (r + buffer):
            return true
    return false

# Helper functions for style-based building generation
func _get_hamlet_styles_for_era(era: int) -> Array[String]:
    var styles: Array[String] = []
    
    if era == 0:  # Medieval hamlets - 6 styles
        styles = [
            "log_chalet", "viking_longhouse", "sauna_building",
            "medieval_hut", "stone_cottage", "blacksmith"
        ]
    elif era == 1:  # Renaissance hamlets - 5 styles
        styles = [
            "fjord_house", "white_stucco_house", "stone_farmhouse",
            "log_chalet", "barn"
        ]
    else:  # Modern hamlets - 5 styles
        styles = [
            "trailer_park", "modular_home", "school",
            "gas_station", "warehouse"
        ]
    
    return styles

# Helper functions for style-based building generation

## Check if a building at (x, z) with given radius would collide with existing buildings
func _check_building_collision(grid: Dictionary, x: float, z: float, radius: float, cell_size: float) -> bool:
    # Check all grid cells that this building overlaps
    var min_gx: int = int(floor((x - radius) / cell_size))
    var max_gx: int = int(floor((x + radius) / cell_size))
    var min_gz: int = int(floor((z - radius) / cell_size))
    var max_gz: int = int(floor((z + radius) / cell_size))

    for gx in range(min_gx, max_gx + 1):
        for gz in range(min_gz, max_gz + 1):
            var cell_key: String = "%d,%d" % [gx, gz]
            if grid.has(cell_key):
                # Cell occupied - check if any building in cell collides
                var buildings: Array = grid[cell_key]
                for building in buildings:
                    if not building is Dictionary:
                        continue
                    var bx: float = building.get("x", 0.0)
                    var bz: float = building.get("z", 0.0)
                    var br: float = building.get("radius", 0.0)

                    # Simple circle-circle collision
                    var dist: float = sqrt((x - bx) * (x - bx) + (z - bz) * (z - bz))
                    if dist < (radius + br):
                        return true  # Collision!

    return false  # No collision


## Mark a building in the spatial grid
func _mark_building_in_grid(grid: Dictionary, x: float, z: float, radius: float, cell_size: float) -> void:
    # Add building to all grid cells it overlaps
    var min_gx: int = int(floor((x - radius) / cell_size))
    var max_gx: int = int(floor((x + radius) / cell_size))
    var min_gz: int = int(floor((z - radius) / cell_size))
    var max_gz: int = int(floor((z - radius) / cell_size))

    var building_data: Dictionary = {
        "x": x,
        "z": z,
        "radius": radius
    }

    for gx in range(min_gx, max_gx + 1):
        for gz in range(min_gz, max_gz + 1):
            var cell_key: String = "%d,%d" % [gx, gz]
            if not grid.has(cell_key):
                grid[cell_key] = []
            grid[cell_key].append(building_data)
