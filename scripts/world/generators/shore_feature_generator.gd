class_name ShoreFeatureGenerator
extends RefCounted

## Generates stylized shore features like beaches, concessions, and picnic areas

var _lake_defs: LakeDefs
var _terrain_generator: TerrainGenerator

func _init():
    _lake_defs = load("res://resources/defs/lake_defs.tres") as LakeDefs

func set_terrain_generator(terrain: TerrainGenerator) -> void:
    _terrain_generator = terrain

func set_lake_defs(defs: LakeDefs) -> void:
    _lake_defs = defs

func generate_shore_features(ctx: WorldContext, scene_root: Node3D, water_data: Dictionary, scene_type: String, rng: RandomNumberGenerator, water_type: String = "lake") -> void:
    print("    [ShoreGen] Generating shore features for ", water_type, " (scene_type: ", scene_type, ")")

    # Get available shore feature types for this scene type
    var available_feature_types = _get_shore_feature_types_for_scene(scene_type)
    print("    [ShoreGen] Available feature types: ", available_feature_types)

    # Sample shore points (different logic for lakes vs rivers)
    var shore_samples: Array[Vector3] = []
    if water_type == "river":
        shore_samples = _sample_river_shore_points(ctx, water_data, 12, rng)
    else:
        var lake_center = water_data.get("center", Vector3.ZERO)
        var lake_radius = water_data.get("radius", 200.0)
        shore_samples = _sample_shore_points(ctx, lake_center, lake_radius, 24, rng)

    print("    [ShoreGen] Sampled ", shore_samples.size(), " shore points")

    var features_placed = 0
    # Generate shore features
    for shore_point in shore_samples:
        if available_feature_types.is_empty():
            break

        # Randomly select feature type
        var feature_type = available_feature_types[rng.randi() % available_feature_types.size()]

        # Generate the feature
        match feature_type:
            "beach":
                _create_beach_area(scene_root, shore_point, water_data, rng)
                features_placed += 1
            "concession":
                _create_concession_stand(scene_root, shore_point, rng)
                features_placed += 1
            "picnic_area":
                _create_picnic_area(scene_root, shore_point, rng)
                features_placed += 1

    print("    [ShoreGen] Placed ", features_placed, " shore features")

func _create_beach_area(parent: Node3D, shore_point: Vector3, lake_data: Dictionary, rng: RandomNumberGenerator) -> void:
    var beach_root = Node3D.new()
    beach_root.name = "BeachArea"
    beach_root.position = shore_point
    
    var beach_config = _lake_defs.shore_features.beach
    var beach_width = rng.randf_range(beach_config.width_min, beach_config.width_max)
    var beach_length = rng.randf_range(15.0, 35.0)
    
    # Beach surface
    var beach_mesh = BoxMesh.new()
    beach_mesh.size = Vector3(beach_length, 0.1, beach_width)
    
    var beach_instance = MeshInstance3D.new()
    beach_instance.mesh = beach_mesh
    beach_instance.position = Vector3(0, 0, 0)
    beach_instance.material_override = _create_sand_material(beach_config.sand_color)
    beach_root.add_child(beach_instance)
    
    # Beach accessories (towel areas, umbrellas)
    var accessory_count = rng.randi_range(2, 6)
    for i in range(accessory_count):
        var pos = Vector3(
            rng.randf_range(-beach_length * 0.4, beach_length * 0.4),
            0.1,
            rng.randf_range(-beach_width * 0.3, beach_width * 0.3)
        )
        
        if beach_config.get("has_umbrellas", false) and rng.randf() < 0.6:
            _create_beach_umbrella(beach_root, pos, rng)
        elif beach_config.get("has_towels", false):
            _create_towel_area(beach_root, pos, rng)
    
    # Add beach vegetation
    _add_beach_vegetation(beach_root, beach_length, beach_width, rng)
    
    parent.add_child(beach_root)

func _create_concession_stand(parent: Node3D, shore_point: Vector3, rng: RandomNumberGenerator) -> void:
    var concession_root = Node3D.new()
    concession_root.name = "ConcessionStand"
    concession_root.position = shore_point
    
    var concession_config = _lake_defs.shore_features.concession
    
    # Main building
    var building_mesh = BoxMesh.new()
    building_mesh.size = Vector3(concession_config.size.x, 3.0, concession_config.size.y)
    
    var building_instance = MeshInstance3D.new()
    building_instance.mesh = building_mesh
    building_instance.position = Vector3(0, 1.5, 0)
    building_instance.material_override = _create_concession_building_material(concession_config.building_color)
    concession_root.add_child(building_instance)
    
    # Roof
    var roof_mesh = PrismMesh.new()
    roof_mesh.size = Vector3(concession_config.size.x + 1.0, 2.0, concession_config.size.y + 1.0)
    
    var roof_instance = MeshInstance3D.new()
    roof_instance.mesh = roof_mesh
    roof_instance.position = Vector3(0, 3.5, 0)
    roof_instance.material_override = _create_concession_roof_material()
    concession_root.add_child(roof_instance)
    
    # Counter if specified
    if concession_config.get("has_counter", false):
        _create_concession_counter(concession_root, concession_config, rng)
    
    # Sign if specified
    if concession_config.get("has_sign", false):
        _create_concession_sign(concession_root, concession_config, rng)
    
    # Optional umbrella
    if concession_config.get("has_umbrella", false):
        var umbrella_pos = Vector3(concession_config.size.x * 0.3, 0, -concession_config.size.y * 0.3)
        _create_beach_umbrella(concession_root, umbrella_pos, rng)
    
    parent.add_child(concession_root)

func _create_picnic_area(parent: Node3D, shore_point: Vector3, rng: RandomNumberGenerator) -> void:
    var picnic_root = Node3D.new()
    picnic_root.name = "PicnicArea"
    picnic_root.position = shore_point
    
    var picnic_config = _lake_defs.shore_features.picnic_area
    
    # Create picnic tables
    var table_count = picnic_config.table_count
    for i in range(table_count):
        var table_pos = Vector3(
            rng.randf_range(-8.0, 8.0),
            0,
            rng.randf_range(-8.0, 8.0)
        )
        _create_picnic_table(picnic_root, table_pos, picnic_config.table_material, rng)
    
    # Add tree shade if specified
    if picnic_config.get("tree_shade", false):
        _add_picnic_trees(picnic_root, table_count, rng)
    
    # Add grills if specified
    if picnic_config.get("has_grills", false):
        _add_picnic_grills(picnic_root, table_count, rng)
    
    parent.add_child(picnic_root)

# --- Beach feature helpers ---

func _create_beach_umbrella(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var umbrella_root = Node3D.new()
    umbrella_root.name = "BeachUmbrella"
    umbrella_root.position = position
    
    # Pole
    var pole_mesh = CylinderMesh.new()
    pole_mesh.height = 3.0
    pole_mesh.top_radius = 0.1
    pole_mesh.bottom_radius = 0.15
    
    var pole_instance = MeshInstance3D.new()
    pole_instance.mesh = pole_mesh
    pole_instance.position = Vector3(0, 1.5, 0)
    pole_instance.material_override = _create_umbrella_pole_material()
    umbrella_root.add_child(pole_instance)
    
    # Canopy
    var canopy_mesh = CylinderMesh.new()
    canopy_mesh.height = 0.2
    canopy_mesh.top_radius = 2.5
    canopy_mesh.bottom_radius = 2.5
    canopy_mesh.radial_segments = 8
    
    var canopy_instance = MeshInstance3D.new()
    canopy_instance.mesh = canopy_mesh
    canopy_instance.position = Vector3(0, 3.0, 0)
    canopy_instance.material_override = _create_umbrella_canopy_material(rng)
    umbrella_root.add_child(canopy_instance)
    
    parent.add_child(umbrella_root)

func _create_towel_area(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var towel_root = Node3D.new()
    towel_root.name = "TowelArea"
    towel_root.position = position
    
    # Towel
    var towel_mesh = BoxMesh.new()
    towel_mesh.size = Vector3(2.0, 0.02, 1.5)
    
    var towel_instance = MeshInstance3D.new()
    towel_instance.mesh = towel_mesh
    towel_instance.position = Vector3(0, 0.01, 0)
    towel_instance.rotation_degrees = Vector3(0, rng.randf() * 360.0, 0)
    towel_instance.material_override = _create_towel_material(rng)
    towel_root.add_child(towel_instance)
    
    # Beach bag
    var bag_mesh = BoxMesh.new()
    bag_mesh.size = Vector3(0.6, 0.4, 0.4)
    
    var bag_instance = MeshInstance3D.new()
    bag_instance.mesh = bag_mesh
    bag_instance.position = Vector3(0.5, 0.2, 0.3)
    bag_instance.material_override = _create_beach_bag_material(rng)
    towel_root.add_child(bag_instance)
    
    parent.add_child(towel_root)

func _add_beach_vegetation(parent: Node3D, beach_length: float, beach_width: float, rng: RandomNumberGenerator) -> void:
    var vegetation_count = rng.randi_range(2, 5)
    
    for i in range(vegetation_count):
        var pos = Vector3(
            rng.randf_range(-beach_length * 0.5, beach_length * 0.5),
            0,
            rng.randf_range(-beach_width * 0.5, beach_width * 0.5)
        )
        
        # Place vegetation at beach edges
        if abs(pos.x) > beach_length * 0.3 or abs(pos.z) > beach_width * 0.3:
            _create_beach_grass(parent, pos, rng)

func _create_beach_grass(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var grass_mesh = BoxMesh.new()
    grass_mesh.size = Vector3(0.3, 0.8, 0.3)
    
    var grass_instance = MeshInstance3D.new()
    grass_instance.mesh = grass_mesh
    grass_instance.position = Vector3(position.x, 0.4, position.z)
    grass_instance.material_override = _create_beach_grass_material()
    parent.add_child(grass_instance)

# --- Concession feature helpers ---

func _create_concession_counter(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var counter_mesh = BoxMesh.new()
    counter_mesh.size = Vector3(config.size.x * 0.8, 1.2, 1.0)
    
    var counter_instance = MeshInstance3D.new()
    counter_instance.mesh = counter_mesh
    counter_instance.position = Vector3(0, 0.6, config.size.y * 0.4)
    counter_instance.material_override = _create_concession_counter_material()
    parent.add_child(counter_instance)
    
    # Add some items on counter
    _add_counter_items(parent, config, rng)

func _create_concession_sign(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var sign_root = Node3D.new()
    sign_root.name = "ConcessionSign"
    sign_root.position = Vector3(0, 2.5, -config.size.y * 0.6)
    
    # Sign board
    var sign_mesh = BoxMesh.new()
    sign_mesh.size = Vector3(4.0, 1.5, 0.1)
    
    var sign_instance = MeshInstance3D.new()
    sign_instance.mesh = sign_mesh
    sign_instance.position = Vector3(0, 0, 0)
    sign_instance.material_override = _create_sign_material()
    sign_root.add_child(sign_instance)
    
    # Sign post
    var post_mesh = CylinderMesh.new()
    post_mesh.height = 2.0
    post_mesh.top_radius = 0.08
    post_mesh.bottom_radius = 0.1
    
    var post_instance = MeshInstance3D.new()
    post_instance.mesh = post_mesh
    post_instance.position = Vector3(0, -1.0, 0)
    post_instance.material_override = _create_sign_post_material()
    sign_root.add_child(post_instance)
    
    parent.add_child(sign_root)

func _add_counter_items(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Add some stylized items on the counter
    var item_positions = [
        Vector3(-config.size.x * 0.2, 1.2, config.size.y * 0.4),
        Vector3(0, 1.2, config.size.y * 0.4),
        Vector3(config.size.x * 0.2, 1.2, config.size.y * 0.4)
    ]
    
    for i in range(item_positions.size()):
        if rng.randf() < 0.7:  # 70% chance for each item
            var item_pos = item_positions[i]
            _create_counter_item(parent, item_pos, rng)

func _create_counter_item(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var item_types = ["drink", "food", "napkin"]
    var item_type = item_types[rng.randi() % item_types.size()]
    
    var item_mesh = BoxMesh.new()
    match item_type:
        "drink":
            item_mesh.size = Vector3(0.15, 0.4, 0.15)
        "food":
            item_mesh.size = Vector3(0.3, 0.1, 0.2)
        "napkin":
            item_mesh.size = Vector3(0.2, 0.05, 0.15)
    
    var item_instance = MeshInstance3D.new()
    item_instance.mesh = item_mesh
    item_instance.position = position
    item_instance.material_override = _create_counter_item_material(item_type)
    parent.add_child(item_instance)

# --- Picnic feature helpers ---

func _create_picnic_table(parent: Node3D, position: Vector3, table_material: String, rng: RandomNumberGenerator) -> void:
    var table_root = Node3D.new()
    table_root.name = "PicnicTable"
    table_root.position = position
    table_root.rotation_degrees = Vector3(0, rng.randf() * 360.0, 0)
    
    # Table top
    var tabletop_mesh = BoxMesh.new()
    tabletop_mesh.size = Vector3(2.0, 0.1, 1.2)
    
    var tabletop_instance = MeshInstance3D.new()
    tabletop_instance.mesh = tabletop_mesh
    tabletop_instance.position = Vector3(0, 0.8, 0)
    tabletop_instance.material_override = _create_picnic_table_material(table_material)
    table_root.add_child(tabletop_instance)
    
    # Table benches
    for bench_side in [-1, 1]:
        var bench_mesh = BoxMesh.new()
        bench_mesh.size = Vector3(1.8, 0.1, 0.3)
        
        var bench_instance = MeshInstance3D.new()
        bench_instance.mesh = bench_mesh
        bench_instance.position = Vector3(0, 0.5, bench_side * 0.6)
        bench_instance.material_override = _create_picnic_bench_material(table_material)
        table_root.add_child(bench_instance)
    
    # Table legs
    for leg_x in [-0.8, 0.8]:
        for leg_z in [-0.5, 0.5]:
            var leg_mesh = CylinderMesh.new()
            leg_mesh.height = 0.8
            leg_mesh.top_radius = 0.05
            leg_mesh.bottom_radius = 0.05
            
            var leg_instance = MeshInstance3D.new()
            leg_instance.mesh = leg_mesh
            leg_instance.position = Vector3(leg_x, 0.4, leg_z)
            leg_instance.material_override = _create_picnic_leg_material()
            table_root.add_child(leg_instance)
    
    parent.add_child(table_root)

func _add_picnic_trees(parent: Node3D, table_count: int, rng: RandomNumberGenerator) -> void:
    var tree_count = min(table_count, rng.randi_range(1, 3))
    
    for i in range(tree_count):
        var tree_pos = Vector3(
            rng.randf_range(-10.0, 10.0),
            0,
            rng.randf_range(-10.0, 10.0)
        )
        _create_picnic_tree(parent, tree_pos, rng)

func _create_picnic_tree(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var tree_root = Node3D.new()
    tree_root.name = "PicnicTree"
    tree_root.position = position
    
    # Trunk
    var trunk_mesh = CylinderMesh.new()
    trunk_mesh.height = 4.0
    trunk_mesh.top_radius = 0.3
    trunk_mesh.bottom_radius = 0.4
    
    var trunk_instance = MeshInstance3D.new()
    trunk_instance.mesh = trunk_mesh
    trunk_instance.position = Vector3(0, 2.0, 0)
    trunk_instance.material_override = _create_tree_trunk_material()
    tree_root.add_child(trunk_instance)
    
    # Foliage
    var foliage_mesh = SphereMesh.new()
    foliage_mesh.radius = 2.5
    foliage_mesh.height = 3.0
    foliage_mesh.radial_segments = 8
    foliage_mesh.rings = 6
    
    var foliage_instance = MeshInstance3D.new()
    foliage_instance.mesh = foliage_mesh
    foliage_instance.position = Vector3(0, 4.5, 0)
    foliage_instance.material_override = _create_tree_foliage_material()
    tree_root.add_child(foliage_instance)
    
    parent.add_child(tree_root)

func _add_picnic_grills(parent: Node3D, table_count: int, rng: RandomNumberGenerator) -> void:
    var grill_count = min(table_count / 2, rng.randi_range(1, 2))
    
    for i in range(grill_count):
        var grill_pos = Vector3(
            rng.randf_range(-8.0, 8.0),
            0,
            rng.randf_range(-8.0, 8.0)
        )
        _create_picnic_grill(parent, grill_pos, rng)

func _create_picnic_grill(parent: Node3D, position: Vector3, rng: RandomNumberGenerator) -> void:
    var grill_root = Node3D.new()
    grill_root.name = "PicnicGrill"
    grill_root.position = position
    
    # Grill base
    var base_mesh = BoxMesh.new()
    base_mesh.size = Vector3(0.8, 0.6, 0.8)
    
    var base_instance = MeshInstance3D.new()
    base_instance.mesh = base_mesh
    base_instance.position = Vector3(0, 0.3, 0)
    base_instance.material_override = _create_grill_base_material()
    grill_root.add_child(base_instance)
    
    # Grill grate
    var grate_mesh = BoxMesh.new()
    grate_mesh.size = Vector3(0.7, 0.02, 0.7)
    
    var grate_instance = MeshInstance3D.new()
    grate_instance.mesh = grate_mesh
    grate_instance.position = Vector3(0, 0.6, 0)
    grate_instance.material_override = _create_grill_grate_material()
    grill_root.add_child(grate_instance)
    
    parent.add_child(grill_root)

# --- Material creation helpers ---

func _create_sand_material(sand_color: Color) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = sand_color
    mat.roughness = 0.8
    return mat

func _create_umbrella_pole_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.2)
    mat.roughness = 0.3
    mat.metallic = 0.4
    return mat

func _create_umbrella_canopy_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    var colors = [Color(1.0, 0.2, 0.2), Color(0.2, 1.0, 0.2), Color(0.2, 0.2, 1.0), Color(1.0, 1.0, 0.2)]
    mat.albedo_color = colors[rng.randi() % colors.size()]
    mat.roughness = 0.6
    return mat

func _create_towel_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    var colors = [Color(1.0, 0.8, 0.8), Color(0.8, 0.8, 1.0), Color(1.0, 1.0, 0.8), Color(0.8, 1.0, 0.8)]
    mat.albedo_color = colors[rng.randi() % colors.size()]
    mat.roughness = 0.7
    return mat

func _create_beach_bag_material(rng: RandomNumberGenerator) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    var colors = [Color(0.8, 0.2, 0.2), Color(0.2, 0.2, 0.8), Color(0.8, 0.4, 0.2)]
    mat.albedo_color = colors[rng.randi() % colors.size()]
    mat.roughness = 0.6
    return mat

func _create_beach_grass_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.6, 0.1)
    mat.roughness = 0.8
    return mat

func _create_concession_building_material(building_color: Color) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = building_color
    mat.roughness = 0.7
    return mat

func _create_concession_roof_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.2, 0.1)
    mat.roughness = 0.6
    return mat

func _create_concession_counter_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.3)
    mat.roughness = 0.4
    mat.metallic = 0.2
    return mat

func _create_sign_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 1.0, 0.0)
    mat.roughness = 0.3
    return mat

func _create_sign_post_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.2)
    mat.roughness = 0.3
    mat.metallic = 0.4
    return mat

func _create_counter_item_material(item_type: String) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    match item_type:
        "drink":
            mat.albedo_color = Color(0.2, 0.4, 0.8)
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.albedo_color.a = 0.8
        "food":
            mat.albedo_color = Color(0.8, 0.6, 0.2)
        "napkin":
            mat.albedo_color = Color(0.9, 0.9, 0.9)
        _:
            mat.albedo_color = Color(0.5, 0.5, 0.5)
    
    mat.roughness = 0.5
    return mat

func _create_picnic_table_material(table_material: String) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    match table_material:
        "wood":
            mat.albedo_color = Color(0.4, 0.3, 0.2)
            mat.roughness = 0.7
        _:
            mat.albedo_color = Color(0.5, 0.5, 0.5)
            mat.roughness = 0.5
    return mat

func _create_picnic_bench_material(table_material: String) -> StandardMaterial3D:
    return _create_picnic_table_material(table_material)

func _create_picnic_leg_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.2)
    mat.roughness = 0.3
    mat.metallic = 0.3
    return mat

func _create_tree_trunk_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.2, 0.1)
    mat.roughness = 0.8
    return mat

func _create_tree_foliage_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.6, 0.1)
    mat.roughness = 0.7
    return mat

func _create_grill_base_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.1, 0.1)
    mat.roughness = 0.3
    mat.metallic = 0.5
    return mat

func _create_grill_grate_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.4, 0.4)
    mat.roughness = 0.2
    mat.metallic = 0.6
    return mat

# --- Positioning and calculation helpers ---

func _get_shore_feature_types_for_scene(scene_type: String) -> Array[String]:
    var scene_config = _lake_defs.lake_types.get(scene_type, {})
    var shore_types_raw = scene_config.get("shore_types", ["beach"])
    var shore_types: Array[String] = []
    for type in shore_types_raw:
        shore_types.append(type)
    return shore_types

func _sample_shore_points(ctx: WorldContext, lake_center: Vector3, lake_radius: float, sample_count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
    var shore_points: Array[Vector3] = []

    for i in range(sample_count):
        var angle = (TAU / sample_count) * i + rng.randf() * 0.3
        var distance = lake_radius + rng.randf_range(3.0, 12.0)

        var test_point = lake_center + Vector3(
            cos(angle) * distance,
            0,
            sin(angle) * distance
        )

        # Check if this is a suitable shore point
        if ctx.terrain_generator != null:
            var height = ctx.terrain_generator.get_height_at(test_point.x, test_point.z)
            if height > Game.sea_level + 1.0:  # Above water level
                test_point.y = height
                shore_points.append(test_point)

    return shore_points

func _sample_river_shore_points(ctx: WorldContext, river_data: Dictionary, sample_count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
    var shore_points: Array[Vector3] = []
    var points: PackedVector3Array = river_data.get("points", PackedVector3Array())
    var width0: float = float(river_data.get("width0", 12.0))
    var width1: float = float(river_data.get("width1", 44.0))

    if points.size() < 2:
        return shore_points

    # Adjust sample count for short rivers
    var actual_sample_count = min(sample_count, max(2, points.size() - 1))

    # Sample along both banks
    for i in range(actual_sample_count):
        var t: float = float(i) / float(actual_sample_count - 1)

        # For short rivers, don't skip sections
        if points.size() > 5 and t < 0.2:
            continue

        var pos: Vector3 = _get_river_position_at(points, t)
        var direction: Vector3 = _get_river_direction_at(points, t)
        var width: float = lerp(width0, width1, pow(t, 0.85))

        # Calculate perpendicular for bank offset
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()

        # Place on both banks (randomly choose one)
        var side: float = 1.0 if rng.randf() < 0.5 else -1.0
        var bank_offset: float = (width * 0.5) + rng.randf_range(2.0, 8.0)

        var shore_pos: Vector3 = pos + perpendicular * side * bank_offset
        if ctx.terrain_generator != null:
            shore_pos.y = ctx.terrain_generator.get_height_at(shore_pos.x, shore_pos.z)

        if shore_pos.y > Game.sea_level + 1.0:
            shore_points.append(shore_pos)

    return shore_points

# Helper functions for river parameterization

func _get_river_position_at(points: PackedVector3Array, t: float) -> Vector3:
    if points.size() < 2:
        return Vector3.ZERO

    var index_float: float = t * float(points.size() - 1)
    var index: int = int(index_float)
    var fraction: float = index_float - float(index)

    if index >= points.size() - 1:
        return points[points.size() - 1]

    return points[index].lerp(points[index + 1], fraction)

func _get_river_direction_at(points: PackedVector3Array, t: float) -> Vector3:
    var index_float: float = t * float(points.size() - 1)
    var index: int = int(index_float)

    var prev_idx: int = max(0, index - 1)
    var next_idx: int = min(points.size() - 1, index + 1)

    var dir: Vector3 = points[next_idx] - points[prev_idx]
    dir.y = 0.0  # Keep horizontal
    return dir.normalized()