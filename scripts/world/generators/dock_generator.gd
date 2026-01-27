class_name DockGenerator
extends RefCounted

## Generates stylized procedural docks and harbor infrastructure

var _lake_defs: LakeDefs
var _terrain_generator: TerrainGenerator = null

func _init():
    _lake_defs = load("res://resources/defs/lake_defs.tres") as LakeDefs

func set_terrain_generator(terrain: TerrainGenerator) -> void:
    _terrain_generator = terrain

func set_lake_defs(defs: LakeDefs) -> void:
    _lake_defs = defs

## Public method to create a single dock at a specific position (for rivers)
func create_single_dock(position: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    var dock_root = Node3D.new()
    dock_root.position = position
    dock_root.name = "Dock_" + config.get("type", "fishing_pier")

    var dock_type: String = config.get("type", "fishing_pier")
    if not _lake_defs.dock_types.has(dock_type):
        dock_type = "fishing_pier"

    var dock_config = _lake_defs.dock_types[dock_type]

    # Use provided rotation or calculate one
    var rotation: float = config.get("rotation", 0.0)
    dock_root.rotation.y = rotation

    # Create dock structure based on type
    match dock_type:
        "fishing_pier":
            _create_stylized_fishing_pier(dock_root, dock_config, rng)
        "boat_launch":
            _create_stylized_boat_launch(dock_root, dock_config, rng)
        "marina_dock":
            _create_stylized_marina_dock(dock_root, dock_config, rng)
        "swimming_dock":
            _create_stylized_swimming_dock(dock_root, dock_config, rng)
        _:
            _create_stylized_fishing_pier(dock_root, dock_config, rng)

    return dock_root

func generate_docks(ctx: WorldContext, scene_root: Node3D, lake_data: Dictionary, scene_type: String, rng: RandomNumberGenerator) -> void:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    var lake_radius = lake_data.get("radius", 200.0)
    
    # Get available dock types for this scene type
    var available_dock_types = _get_dock_types_for_scene(scene_type)
    
    # Find suitable shore points for docks
    var shore_points = _find_shore_points(ctx, lake_center, lake_radius, rng)
    
    # Determine dock count based on lake size and type
    var dock_count = _calculate_dock_count(lake_radius, scene_type, rng)
    dock_count = min(dock_count, shore_points.size())
    
    # Generate docks
    for i in range(dock_count):
        if shore_points.is_empty() or available_dock_types.is_empty():
            break
        
        var shore_point = shore_points.pop_at(rng.randi() % shore_points.size())
        var dock_type = available_dock_types[rng.randi() % available_dock_types.size()]
        var dock = _create_stylized_dock(dock_type, shore_point, lake_data, rng)
        scene_root.add_child(dock)
    
    # Generate harbor infrastructure for harbor scenes
    if scene_type == "harbor":
        _generate_harbor_infrastructure(ctx, scene_root, lake_data, rng)

func generate_river_docks(ctx: WorldContext, scene_root: Node3D, river_data: Dictionary, scene_type: String, rng: RandomNumberGenerator) -> void:
    var points: PackedVector3Array = river_data.get("points", PackedVector3Array())
    var width0: float = float(river_data.get("width0", 12.0))
    var width1: float = float(river_data.get("width1", 44.0))

    print("    [DockGen] River docks: points=", points.size(), " scene_type=", scene_type)

    if points.size() < 2:
        print("    [DockGen] Skipping - too few points")
        return

    var dock_count: int = 2 if scene_type == "harbor" else 1
    print("    [DockGen] Attempting ", dock_count, " docks")

    var docks_placed = 0
    for i in range(dock_count):
        var t: float = rng.randf_range(0.4, 0.9)  # Middle to lower sections
        var width: float = lerp(width0, width1, pow(t, 0.85))

        if width < 25.0:  # Minimum width for docks
            continue

        var pos: Vector3 = _get_river_position_at(points, t)
        var direction: Vector3 = _get_river_direction_at(points, t)
        var perpendicular: Vector3 = direction.cross(Vector3.UP).normalized()

        # Place on one bank
        var side: float = 1.0 if rng.randf() < 0.5 else -1.0
        var dock_offset: float = (width * 0.5) + 3.0
        var dock_pos: Vector3 = pos + perpendicular * side * dock_offset

        if _terrain_generator != null:
            dock_pos.y = _terrain_generator.get_height_at(dock_pos.x, dock_pos.z)

        if dock_pos.y < Game.sea_level + 0.5:
            continue

        var dock_type: String = "fishing_pier" if t < 0.7 else "marina_dock"
        var dock_config = {
            "type": dock_type,
            "length": rng.randf_range(15.0, 25.0),
            "width": rng.randf_range(4.0, 6.0),
            "rotation": atan2(direction.z, direction.x) + (PI * 0.5 * side)
        }

        var dock_node = create_single_dock(dock_pos, dock_config, rng)
        if dock_node != null:
            scene_root.add_child(dock_node)
            docks_placed += 1

    print("    [DockGen] Placed ", docks_placed, " docks on river")

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

func _create_stylized_dock(dock_type: String, shore_point: Vector3, lake_data: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    var dock_root = Node3D.new()
    dock_root.position = shore_point
    dock_root.name = "Dock_" + dock_type
    
    var dock_config = _lake_defs.dock_types[dock_type]
    
    # Calculate dock orientation (perpendicular to shore)
    var dock_orientation = _calculate_dock_orientation(shore_point, lake_data, rng)
    dock_root.rotation_degrees = Vector3(0, dock_orientation, 0)
    
    match dock_type:
        "fishing_pier":
            dock_root = _create_stylized_fishing_pier(dock_root, dock_config, rng)
        "boat_launch":
            dock_root = _create_stylized_boat_launch(dock_root, dock_config, rng)
        "marina_dock":
            dock_root = _create_stylized_marina_dock(dock_root, dock_config, rng)
        "swimming_dock":
            dock_root = _create_stylized_swimming_dock(dock_root, dock_config, rng)
    
    return dock_root

func _create_stylized_fishing_pier(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Main pier structure
    var pier_mesh = BoxMesh.new()
    pier_mesh.size = Vector3(config.length, 0.3, config.width)
    
    var pier_instance = MeshInstance3D.new()
    pier_instance.mesh = pier_mesh
    pier_instance.material_override = _create_dock_material(config.material)
    parent.add_child(pier_instance)
    
    # Support posts
    _add_pier_support_posts(parent, config, rng)
    
    # Fishing shed if specified
    if config.get("has_shed", false):
        _add_fishing_shed(parent, config, rng)
    
    # Railings if specified
    if config.get("has_railing", false):
        _add_dock_railings(parent, config, rng)
    
    # Lighting if specified
    if config.get("has_lighting", false):
        _add_dock_lighting(parent, config, rng)
    
    return parent

func _create_stylized_boat_launch(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Main launch area
    var launch_mesh = BoxMesh.new()
    launch_mesh.size = Vector3(config.length, 0.4, config.width)
    
    var launch_instance = MeshInstance3D.new()
    launch_instance.mesh = launch_mesh
    launch_instance.material_override = _create_dock_material(config.material)
    parent.add_child(launch_instance)
    
    # Boat ramp if specified
    if config.get("has_ramp", false):
        _add_boat_ramp(parent, config, rng)
    
    # Parking area if specified
    if config.get("has_parking", false):
        _add_launch_parking(parent, config, rng)
    
    return parent

func _create_stylized_marina_dock(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Main marina dock
    var dock_mesh = BoxMesh.new()
    dock_mesh.size = Vector3(config.length, 0.3, config.width)
    
    var dock_instance = MeshInstance3D.new()
    dock_instance.mesh = dock_mesh
    dock_instance.material_override = _create_dock_material(config.material)
    parent.add_child(dock_instance)
    
    # Utility posts if specified
    if config.get("has_posts", false):
        _add_marina_posts(parent, config, rng)
    
    # Utilities if specified
    if config.get("has_utilities", false):
        _add_marina_utilities(parent, config, rng)
    
    # Lighting if specified
    if config.get("has_lighting", false):
        _add_dock_lighting(parent, config, rng)
    
    return parent

func _create_stylized_swimming_dock(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Swimming platform
    var platform_mesh = BoxMesh.new()
    platform_mesh.size = Vector3(config.length, 0.2, config.width)
    
    var platform_instance = MeshInstance3D.new()
    platform_instance.mesh = platform_mesh
    platform_instance.material_override = _create_dock_material(config.material)
    parent.add_child(platform_instance)
    
    # Ladder if specified
    if config.get("has_ladder", false):
        _add_swimming_ladder(parent, config, rng)
    
    # Railings if specified
    if config.get("has_railing", false):
        _add_dock_railings(parent, config, rng)
    
    return parent

# --- Harbor infrastructure ---

func _generate_harbor_infrastructure(ctx: WorldContext, scene_root: Node3D, lake_data: Dictionary, rng: RandomNumberGenerator) -> void:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    var lake_radius = lake_data.get("radius", 200.0)
    
    # Generate breakwater
    _generate_breakwater(scene_root, lake_center, lake_radius, rng)
    
    # Generate harbor buildings
    _generate_harbor_buildings(scene_root, lake_center, lake_radius, rng)
    
    # Generate navigation aids
    _generate_navigation_aids(scene_root, lake_center, lake_radius, rng)

func _generate_breakwater(parent: Node3D, lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> void:
    var breakwater_root = Node3D.new()
    breakwater_root.name = "Breakwater"
    
    # Create curved breakwater around part of the lake
    var breakwater_length = lake_radius * 0.6
    var breakwater_segments = 8
    var segment_length = breakwater_length / breakwater_segments
    
    var start_angle = rng.randf() * TAU
    var angle_span = PI * 0.4  # 72 degrees of coverage
    
    for i in range(breakwater_segments):
        var angle = start_angle + (angle_span * i / breakwater_segments)
        var distance = lake_radius * 0.85
        
        var segment_pos = lake_center + Vector3(
            cos(angle) * distance,
            0,
            sin(angle) * distance
        )
        
        var segment = _create_breakwater_segment(segment_length, angle, rng)
        segment.position = segment_pos
        breakwater_root.add_child(segment)
        
        # Add navigation lights every few segments
        if i % 3 == 0:
            _add_breakwater_light(segment, rng)
    
    parent.add_child(breakwater_root)

func _generate_harbor_buildings(parent: Node3D, lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> void:
    var buildings_root = Node3D.new()
    buildings_root.name = "HarborBuildings"
    
    # Harbor office
    var office_pos = lake_center + Vector3(lake_radius * 0.4, 0, lake_radius * 0.3)
    var office = _create_harbor_office(office_pos, rng)
    buildings_root.add_child(office)
    
    # Warehouse
    var warehouse_pos = lake_center + Vector3(-lake_radius * 0.3, 0, lake_radius * 0.4)
    var warehouse = _create_harbor_warehouse(warehouse_pos, rng)
    buildings_root.add_child(warehouse)
    
    parent.add_child(buildings_root)

func _generate_navigation_aids(parent: Node3D, lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> void:
    var nav_root = Node3D.new()
    nav_root.name = "NavigationAids"
    
    # Channel markers
    var marker_count = 4
    for i in range(marker_count):
        var angle = (TAU / marker_count) * i
        var distance = lake_radius * 0.7
        
        var marker_pos = lake_center + Vector3(
            cos(angle) * distance,
            0,
            sin(angle) * distance
        )
        
        var marker = _create_channel_marker(marker_pos, i % 2 == 0, rng)
        nav_root.add_child(marker)
    
    parent.add_child(nav_root)

# --- Dock feature helpers ---

func _add_pier_support_posts(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var post_count = int(config.length / 5.0) + 1
    
    for i in range(post_count):
        var post_mesh = CylinderMesh.new()
        post_mesh.height = 4.0
        post_mesh.top_radius = 0.2
        post_mesh.bottom_radius = 0.25
        
        var post_instance = MeshInstance3D.new()
        post_instance.mesh = post_mesh
        post_instance.position = Vector3(
            -config.length * 0.5 + i * (config.length / (post_count - 1)),
            2.0,
            0
        )
        post_instance.material_override = _create_post_material()
        parent.add_child(post_instance)

func _add_fishing_shed(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var shed_root = Node3D.new()
    shed_root.name = "FishingShed"
    shed_root.position = Vector3(config.length * 0.3, 1.0, 0)
    
    # Shed building
    var shed_mesh = BoxMesh.new()
    shed_mesh.size = Vector3(6.0, 3.0, 4.0)
    
    var shed_instance = MeshInstance3D.new()
    shed_instance.mesh = shed_mesh
    shed_instance.position = Vector3(0, 1.5, 0)
    shed_instance.material_override = _create_shed_material()
    shed_root.add_child(shed_instance)
    
    # Roof
    var roof_mesh = PrismMesh.new()
    roof_mesh.size = Vector3(7.0, 2.0, 5.0)
    
    var roof_instance = MeshInstance3D.new()
    roof_instance.mesh = roof_mesh
    roof_instance.position = Vector3(0, 3.5, 0)
    roof_instance.material_override = _create_roof_material()
    shed_root.add_child(roof_instance)
    
    parent.add_child(shed_root)

func _add_boat_ramp(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var ramp_mesh = ArrayMesh.new()
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    # Create inclined ramp
    var ramp_length = 8.0
    var ramp_width = config.width * 0.8
    var ramp_height = 2.0
    
    # Ramp vertices
    vertices.append(Vector3(0, 0, -ramp_width * 0.5))
    vertices.append(Vector3(ramp_length, -ramp_height, -ramp_width * 0.5))
    vertices.append(Vector3(ramp_length, -ramp_height, ramp_width * 0.5))
    vertices.append(Vector3(0, 0, ramp_width * 0.5))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(0); indices.append(2); indices.append(3)

    var arrays = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    ramp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    
    var ramp_instance = MeshInstance3D.new()
    ramp_instance.mesh = ramp_mesh
    ramp_instance.position = Vector3(config.length * 0.5, 0.2, 0)
    ramp_instance.material_override = _create_ramp_material()
    parent.add_child(ramp_instance)

func _add_launch_parking(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var parking_root = Node3D.new()
    parking_root.name = "LaunchParking"
    parking_root.position = Vector3(-config.length * 0.3, 0, 0)
    
    # Parking surface
    var parking_mesh = BoxMesh.new()
    parking_mesh.size = Vector3(10.0, 0.1, 15.0)
    
    var parking_instance = MeshInstance3D.new()
    parking_instance.mesh = parking_mesh
    parking_instance.material_override = _create_parking_material()
    parking_root.add_child(parking_instance)
    
    # Parking lines
    for i in range(3):
        var line_mesh = BoxMesh.new()
        line_mesh.size = Vector3(0.1, 0.01, 15.0)
        
        var line_instance = MeshInstance3D.new()
        line_instance.mesh = line_mesh
        line_instance.position = Vector3(-4.0 + i * 4.0, 0.05, 0)
        line_instance.material_override = _create_line_material()
        parking_root.add_child(line_instance)
    
    parent.add_child(parking_root)

func _add_marina_posts(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var post_count = int(config.length / 8.0) + 1
    
    for i in range(post_count):
        var post_mesh = CylinderMesh.new()
        post_mesh.height = 2.5
        post_mesh.top_radius = 0.15
        post_mesh.bottom_radius = 0.2
        
        var post_instance = MeshInstance3D.new()
        post_instance.mesh = post_mesh
        post_instance.position = Vector3(
            -config.length * 0.5 + i * (config.length / (post_count - 1)),
            1.25,
            0
        )
        post_instance.material_override = _create_marina_post_material()
        parent.add_child(post_instance)

func _add_marina_utilities(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Utility boxes
    var utility_count = 2
    for i in range(utility_count):
        var utility_mesh = BoxMesh.new()
        utility_mesh.size = Vector3(1.0, 0.8, 0.8)
        
        var utility_instance = MeshInstance3D.new()
        utility_instance.mesh = utility_mesh
        utility_instance.position = Vector3(
            -config.length * 0.3 + i * config.length * 0.6,
            0.4,
            config.width * 0.3
        )
        utility_instance.material_override = _create_utility_material()
        parent.add_child(utility_instance)

func _add_swimming_ladder(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var ladder_root = Node3D.new()
    ladder_root.name = "SwimmingLadder"
    ladder_root.position = Vector3(0, -1.0, config.width * 0.5)
    
    # Ladder sides
    for i in range(2):
        var side_mesh = BoxMesh.new()
        side_mesh.size = Vector3(0.1, 2.5, 0.1)
        
        var side_instance = MeshInstance3D.new()
        side_instance.mesh = side_mesh
        side_instance.position = Vector3(0.3 - i * 0.6, 1.25, 0)
        side_instance.material_override = _create_ladder_material()
        ladder_root.add_child(side_instance)
    
    # Ladder rungs
    for i in range(5):
        var rung_mesh = BoxMesh.new()
        rung_mesh.size = Vector3(0.6, 0.05, 0.05)
        
        var rung_instance = MeshInstance3D.new()
        rung_instance.mesh = rung_mesh
        rung_instance.position = Vector3(0, 0.2 + i * 0.4, 0)
        rung_instance.material_override = _create_ladder_material()
        ladder_root.add_child(rung_instance)
    
    parent.add_child(ladder_root)

func _add_dock_railings(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var railing_root = Node3D.new()
    railing_root.name = "DockRailings"
    
    # Side railings
    for side in [-1, 1]:
        var side_pos = Vector3(0, 0.5, side * config.width * 0.4)
        
        # Railing posts
        var post_count = int(config.length / 3.0) + 1
        for i in range(post_count):
            var post_mesh = CylinderMesh.new()
            post_mesh.height = 1.0
            post_mesh.top_radius = 0.05
            post_mesh.bottom_radius = 0.05
            
            var post_instance = MeshInstance3D.new()
            post_instance.mesh = post_mesh
            post_instance.position = side_pos + Vector3(
                -config.length * 0.5 + i * (config.length / (post_count - 1)),
                0.5,
                0
            )
            post_instance.material_override = _create_railing_material()
            railing_root.add_child(post_instance)
        
        # Railing top rail
        var rail_mesh = BoxMesh.new()
        rail_mesh.size = Vector3(config.length, 0.05, 0.05)
        
        var rail_instance = MeshInstance3D.new()
        rail_instance.mesh = rail_mesh
        rail_instance.position = side_pos + Vector3(0, 0.5, 0)
        rail_instance.material_override = _create_railing_material()
        railing_root.add_child(rail_instance)
    
    parent.add_child(railing_root)

func _add_dock_lighting(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var light_count = int(config.length / 10.0) + 1
    
    for i in range(light_count):
        var light_pos = Vector3(
            -config.length * 0.5 + i * (config.length / (light_count - 1)),
            2.0,
            0
        )
        
        # Light post
        var post_mesh = CylinderMesh.new()
        post_mesh.height = 2.0
        post_mesh.top_radius = 0.08
        post_mesh.bottom_radius = 0.1
        
        var post_instance = MeshInstance3D.new()
        post_instance.mesh = post_mesh
        post_instance.position = light_pos
        post_instance.material_override = _create_light_post_material()
        parent.add_child(post_instance)
        
        # Light
        var light = OmniLight3D.new()
        light.position = light_pos + Vector3(0, 0.2, 0)
        light.light_color = Color(1.0, 1.0, 0.8)
        light.light_energy = 2.0
        light.omni_range = 8.0
        parent.add_child(light)

# --- Harbor feature helpers ---

func _create_breakwater_segment(length: float, angle: float, rng: RandomNumberGenerator) -> Node3D:
    var segment_root = Node3D.new()
    segment_root.name = "BreakwaterSegment"
    segment_root.rotation_degrees = Vector3(0, rad_to_deg(angle), 0)
    
    # Main segment
    var segment_mesh = BoxMesh.new()
    segment_mesh.size = Vector3(length, 2.5, 4.0)
    
    var segment_instance = MeshInstance3D.new()
    segment_instance.mesh = segment_mesh
    segment_instance.position = Vector3(0, 1.25, 0)
    segment_instance.material_override = _create_breakwater_material()
    segment_root.add_child(segment_instance)
    
    return segment_root

func _add_breakwater_light(parent: Node3D, rng: RandomNumberGenerator) -> void:
    var light_base = MeshInstance3D.new()
    var base_mesh = CylinderMesh.new()
    base_mesh.height = 1.0
    base_mesh.top_radius = 0.2
    base_mesh.bottom_radius = 0.25
    light_base.mesh = base_mesh
    light_base.position = Vector3(0, 1.5, 0)
    light_base.material_override = _create_light_post_material()
    
    var light_bulb = OmniLight3D.new()
    light_bulb.position = Vector3(0, 2.2, 0)
    light_bulb.light_color = Color(1.0, 1.0, 0.0)
    light_bulb.light_energy = 2.0
    light_bulb.omni_range = 15.0
    
    parent.add_child(light_base)
    parent.add_child(light_bulb)

func _create_harbor_office(position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var office_root = Node3D.new()
    office_root.name = "HarborOffice"
    office_root.position = position
    
    # Office building
    var office_mesh = BoxMesh.new()
    office_mesh.size = Vector3(8.0, 4.0, 6.0)
    
    var office_instance = MeshInstance3D.new()
    office_instance.mesh = office_mesh
    office_instance.position = Vector3(0, 2.0, 0)
    office_instance.material_override = _create_harbor_building_material()
    office_root.add_child(office_instance)
    
    # Roof
    var roof_mesh = PrismMesh.new()
    roof_mesh.size = Vector3(9.0, 2.0, 7.0)
    
    var roof_instance = MeshInstance3D.new()
    roof_instance.mesh = roof_mesh
    roof_instance.position = Vector3(0, 4.5, 0)
    roof_instance.material_override = _create_roof_material()
    office_root.add_child(roof_instance)
    
    return office_root

func _create_harbor_warehouse(position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var warehouse_root = Node3D.new()
    warehouse_root.name = "HarborWarehouse"
    warehouse_root.position = position
    
    # Warehouse building
    var warehouse_mesh = BoxMesh.new()
    warehouse_mesh.size = Vector3(12.0, 6.0, 8.0)
    
    var warehouse_instance = MeshInstance3D.new()
    warehouse_instance.mesh = warehouse_mesh
    warehouse_instance.position = Vector3(0, 3.0, 0)
    warehouse_instance.material_override = _create_warehouse_material()
    warehouse_root.add_child(warehouse_instance)
    
    # Large doors
    for i in range(2):
        var door_mesh = BoxMesh.new()
        door_mesh.size = Vector3(0.2, 4.0, 3.0)
        
        var door_instance = MeshInstance3D.new()
        door_instance.mesh = door_mesh
        door_instance.position = Vector3(0, 2.0, -2.0 + i * 4.0)
        door_instance.material_override = _create_door_material()
        warehouse_root.add_child(door_instance)
    
    return warehouse_root

func _create_channel_marker(position: Vector3, is_port: bool, rng: RandomNumberGenerator) -> Node3D:
    var marker_root = Node3D.new()
    marker_root.name = "ChannelMarker"
    marker_root.position = position
    
    # Marker post
    var post_mesh = CylinderMesh.new()
    post_mesh.height = 3.0
    post_mesh.top_radius = 0.15
    post_mesh.bottom_radius = 0.2
    
    var post_instance = MeshInstance3D.new()
    post_instance.mesh = post_mesh
    post_instance.position = Vector3(0, 1.5, 0)
    post_instance.material_override = _create_marker_post_material()
    marker_root.add_child(post_instance)
    
    # Marker light
    var light = OmniLight3D.new()
    light.position = Vector3(0, 3.2, 0)
    light.light_color = Color(1.0, 0.0, 0.0) if is_port else Color(0.0, 1.0, 0.0)
    light.light_energy = 3.0
    light.omni_range = 20.0
    marker_root.add_child(light)
    
    return marker_root

# --- Material creation helpers ---

func _create_dock_material(material_type: String) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    
    match material_type:
        "weathered_wood":
            mat.albedo_color = Color(0.4, 0.3, 0.2)
            mat.roughness = 0.8
        "concrete":
            mat.albedo_color = Color(0.6, 0.6, 0.65)
            mat.roughness = 0.7
        "treated_wood":
            mat.albedo_color = Color(0.3, 0.25, 0.15)
            mat.roughness = 0.6
        "natural_wood":
            mat.albedo_color = Color(0.5, 0.4, 0.3)
            mat.roughness = 0.7
        _:
            mat.albedo_color = Color(0.5, 0.5, 0.5)
            mat.roughness = 0.5
    
    return mat

func _create_post_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.25, 0.15)
    mat.roughness = 0.7
    return mat

func _create_shed_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.5, 0.4)
    mat.roughness = 0.8
    return mat

func _create_roof_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.2, 0.1)
    mat.roughness = 0.7
    return mat

func _create_ramp_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.5, 0.5, 0.5)
    mat.roughness = 0.6
    return mat

func _create_parking_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.2)
    mat.roughness = 0.8
    return mat

func _create_line_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 1.0, 0.0)
    mat.roughness = 0.3
    return mat

func _create_marina_post_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.25)
    mat.roughness = 0.4
    mat.metallic = 0.3
    return mat

func _create_utility_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.1, 0.1)
    mat.roughness = 0.3
    mat.metallic = 0.5
    return mat

func _create_ladder_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.7, 0.7)
    mat.roughness = 0.2
    mat.metallic = 0.6
    return mat

func _create_railing_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.8, 0.8)
    mat.roughness = 0.2
    mat.metallic = 0.6
    return mat

func _create_light_post_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.2)
    mat.roughness = 0.3
    mat.metallic = 0.4
    return mat

func _create_breakwater_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.4, 0.45)
    mat.roughness = 0.7
    return mat

func _create_harbor_building_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.7, 0.75)
    mat.roughness = 0.6
    return mat

func _create_warehouse_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)
    mat.roughness = 0.5
    return mat

func _create_door_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.1, 0.1)
    mat.roughness = 0.4
    mat.metallic = 0.3
    return mat

func _create_marker_post_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.2, 0.25)
    mat.roughness = 0.4
    mat.metallic = 0.3
    return mat

# --- Positioning and calculation helpers ---

func _get_dock_types_for_scene(scene_type: String) -> Array[String]:
    var scene_config = _lake_defs.lake_types.get(scene_type, {})
    var dock_types_raw = scene_config.get("dock_types", ["fishing_pier"])
    var dock_types: Array[String] = []
    for type in dock_types_raw:
        dock_types.append(type)
    return dock_types

func _calculate_dock_count(lake_radius: float, scene_type: String, rng: RandomNumberGenerator) -> int:
    var base_count = 1
    
    # Adjust based on lake size and type
    if lake_radius > 300:
        base_count = 2
    if lake_radius > 500:
        base_count = 3
    
    match scene_type:
        "harbor":
            base_count += 1  # Extra docks in harbors
        "recreational":
            base_count += rng.randi() % 2  # Random extra dock
        "fishing":
            base_count = max(1, base_count - 1)  # Fewer docks in fishing lakes
    
    return base_count

func _find_shore_points(ctx: WorldContext, lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Array[Vector3]:
    var shore_points: Array[Vector3] = []
    
    # Sample points around the lake perimeter
    var sample_count = 16
    for i in range(sample_count):
        var angle = (TAU / sample_count) * i + rng.randf() * 0.2
        var distance = lake_radius + rng.randf_range(5.0, 15.0)
        
        var test_point = lake_center + Vector3(
            cos(angle) * distance,
            0,
            sin(angle) * distance
        )
        
        # Check if this is a suitable shore point
        if ctx.terrain_generator != null:
            var height = ctx.terrain_generator.get_height_at(test_point.x, test_point.z)
            if height > Game.sea_level + 2.0:  # Above water level
                test_point.y = height
                shore_points.append(test_point)
    
    return shore_points

func _calculate_dock_orientation(shore_point: Vector3, lake_data: Dictionary, rng: RandomNumberGenerator) -> float:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    
    # Calculate angle from lake center to shore point
    var to_shore = shore_point - lake_center
    var base_angle = atan2(to_shore.z, to_shore.x)
    
    # Add perpendicular offset (dock extends into water)
    var perpendicular = base_angle + PI * 0.5
    
    # Add some randomness
    perpendicular += rng.randf_range(-0.2, 0.2)
    
    return rad_to_deg(perpendicular)