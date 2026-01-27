class_name BoatGenerator
extends RefCounted

## Generates stylized procedural boats and buoys for lake scenes

var _lake_defs: LakeDefs

func _init():
    _lake_defs = load("res://resources/defs/lake_defs.tres") as LakeDefs

func generate_boats_and_buoys(ctx: WorldContext, scene_root: Node3D, lake_data: Dictionary, scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    var lake_radius = lake_data.get("radius", 200.0)
    
    # Get available boat types for this scene type
    var available_boat_types = _get_boat_types_for_scene(scene_type)
    
    # Calculate boat count based on density and lake size
    var boat_count = _calculate_boat_count(lake_radius, scene_type, params, rng)
    boat_count = min(boat_count, params.get("max_boats_per_lake", 8))
    
    # Generate boats
    for i in range(boat_count):
        if available_boat_types.is_empty():
            break
        
        var boat_type = available_boat_types[rng.randi() % available_boat_types.size()]
        var boat_pos = _generate_boat_position(lake_center, lake_radius, rng)
        var boat = _create_stylized_boat(boat_type, boat_pos, rng)
        
        # Store movement data for future use
        boat.set_meta("original_position", boat_pos)
        boat.set_meta("boat_type", boat_type)
        boat.set_meta("movement_pattern", _get_movement_pattern(boat_type))
        
        scene_root.add_child(boat)
    
    # Generate buoys
    var buoy_count = _calculate_buoy_count(lake_radius, params, rng)
    buoy_count = min(buoy_count, params.get("max_buoys_per_lake", 20))
    
    for i in range(buoy_count):
        var buoy_type = _select_buoy_type(rng)
        var buoy_pos = _generate_buoy_position(lake_center, lake_radius, rng)
        var buoy = _create_stylized_buoy(buoy_type, buoy_pos, rng)
        scene_root.add_child(buoy)

func _create_stylized_boat(boat_type: String, position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var boat_root = Node3D.new()
    boat_root.position = position
    boat_root.name = "Boat_" + boat_type
    
    var boat_config = _lake_defs.boat_types[boat_type]
    
    match boat_type:
        "fishing":
            boat_root = _create_stylized_fishing_boat(boat_root, boat_config, rng)
        "sailboat":
            boat_root = _create_stylized_sailboat(boat_root, boat_config, rng)
        "speedboat":
            boat_root = _create_stylized_speedboat(boat_root, boat_config, rng)
        "pontoon":
            boat_root = _create_stylized_pontoon(boat_root, boat_config, rng)
    
    # Add movement-ready components (static for now)
    _add_movement_readiness(boat_root, boat_type)
    
    return boat_root

func _create_stylized_fishing_boat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Stylized hull with exaggerated fishing boat features
    var hull_mesh = _create_fishing_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("fishing")
    parent.add_child(hull_instance)
    
    # Stylized cabin
    var cabin_mesh = _create_stylized_fishing_cabin(config, rng)
    var cabin_instance = MeshInstance3D.new()
    cabin_instance.mesh = cabin_mesh
    cabin_instance.position = Vector3(0, 2.0, -2.0)
    cabin_instance.material_override = _create_stylized_cabin_material()
    parent.add_child(cabin_instance)
    
    # Fishing equipment (stylized)
    _add_stylized_fishing_gear(parent, rng)
    
    return parent

func _create_stylized_sailboat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Sleek stylized hull
    var hull_mesh = _create_sailboat_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("sailboat")
    parent.add_child(hull_instance)
    
    # Stylized mast and sail
    var mast_system = _create_stylized_mast_system(config, rng)
    mast_system.position = Vector3(0, 0, 0)
    parent.add_child(mast_system)
    
    return parent

func _create_stylized_speedboat(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Aerodynamic hull
    var hull_mesh = _create_speedboat_hull_mesh(config, rng)
    var hull_instance = MeshInstance3D.new()
    hull_instance.mesh = hull_mesh
    hull_instance.material_override = _create_stylized_boat_material("speedboat")
    parent.add_child(hull_instance)
    
    # Windshield and cockpit
    _add_speedboat_cockpit(parent, config, rng)
    
    # Engine area
    _add_speedboat_engine(parent, config, rng)
    
    return parent

func _create_stylized_pontoon(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Main deck platform
    var deck_mesh = _create_pontoon_deck_mesh(config, rng)
    var deck_instance = MeshInstance3D.new()
    deck_instance.mesh = deck_mesh
    deck_instance.material_override = _create_stylized_boat_material("pontoon")
    parent.add_child(deck_instance)
    
    # Pontoon tubes
    _add_pontoon_tubes(parent, config, rng)
    
    # Railings
    _add_pontoon_railings(parent, config, rng)
    
    return parent

func _create_stylized_buoy(buoy_type: String, position: Vector3, rng: RandomNumberGenerator) -> Node3D:
    var buoy_root = Node3D.new()
    buoy_root.position = position
    buoy_root.name = "Buoy_" + buoy_type
    
    var buoy_config = _lake_defs.buoy_types[buoy_type]
    
    # Main buoy body
    var body_mesh = CylinderMesh.new()
    body_mesh.height = buoy_config.height
    body_mesh.top_radius = buoy_config.radius
    body_mesh.bottom_radius = buoy_config.radius
    body_mesh.radial_segments = 12
    
    var body_instance = MeshInstance3D.new()
    body_instance.mesh = body_mesh
    body_instance.position = Vector3(0, buoy_config.height * 0.5, 0)
    body_instance.material_override = _create_buoy_material(buoy_config.color)
    buoy_root.add_child(body_instance)
    
    # Add light if specified
    if buoy_config.get("has_light", false):
        _add_buoy_light(buoy_root, buoy_config)
    
    return buoy_root

# --- Boat mesh creation helpers ---

func _create_fishing_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create stylized fishing boat hull (wider, more stable)
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    # Hull vertices (simplified)
    var half_length = size.z * 0.5
    var half_width = size.x * 0.5
    var height = size.y * 0.5
    
    # Bottom hull
    vertices.append(Vector3(-half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    vertices.append(Vector3(-half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.8, height, -half_width * 0.9))
    vertices.append(Vector3(half_length * 1.2, height, -half_width * 0.9))
    vertices.append(Vector3(half_length * 1.2, height, half_width * 0.9))
    vertices.append(Vector3(-half_length * 0.8, height, half_width * 0.9))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(0); indices.append(2); indices.append(3)
    indices.append(4); indices.append(7); indices.append(6)
    indices.append(4); indices.append(6); indices.append(5)
    
    # Side faces
    for i in range(4):
        var next = (i + 1) % 4
        indices.append(i)
        indices.append(next)
        indices.append(i + 4)
        indices.append(next)
        indices.append(next + 4)
        indices.append(i + 4)
    
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, vertices, [], {}, indices)
    return mesh

func _create_sailboat_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create sleek sailboat hull (narrower, deeper)
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    var half_length = size.z * 0.5
    var half_width = size.x * 0.4  # Narrower
    var height = size.y * 0.6  # Deeper
    
    # Hull vertices (pointed bow)
    vertices.append(Vector3(-half_length, -height, 0))  # Bow point
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.8, height, 0))  # Top bow
    vertices.append(Vector3(half_length * 1.1, height, -half_width * 0.8))
    vertices.append(Vector3(half_length * 1.1, height, half_width * 0.8))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(3); indices.append(5); indices.append(4)
    
    # Side faces
    indices.append(0); indices.append(3); indices.append(4)
    indices.append(0); indices.append(4); indices.append(1)
    indices.append(1); indices.append(4); indices.append(5)
    indices.append(1); indices.append(5); indices.append(2)
    indices.append(2); indices.append(5); indices.append(3)
    indices.append(2); indices.append(3); indices.append(0)
    
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, vertices, [], {}, indices)
    return mesh

func _create_speedboat_hull_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create aerodynamic speedboat hull
    var vertices = PackedVector3Array()
    var indices = PackedInt32Array()
    
    var half_length = size.z * 0.5
    var half_width = size.x * 0.5
    var height = size.y * 0.4
    
    # Hull vertices (sleek, pointed)
    vertices.append(Vector3(-half_length, -height * 0.5, 0))  # Bow
    vertices.append(Vector3(half_length, -height, -half_width))
    vertices.append(Vector3(half_length, -height, half_width))
    
    # Top hull
    vertices.append(Vector3(-half_length * 0.9, height * 0.8, 0))  # Cockpit area
    vertices.append(Vector3(half_length * 1.1, height, -half_width * 0.7))
    vertices.append(Vector3(half_length * 1.1, height, half_width * 0.7))
    
    # Create faces
    indices.append(0); indices.append(1); indices.append(2)
    indices.append(3); indices.append(5); indices.append(4)
    
    # Side faces
    indices.append(0); indices.append(3); indices.append(4)
    indices.append(0); indices.append(4); indices.append(1)
    indices.append(1); indices.append(4); indices.append(5)
    indices.append(1); indices.append(5); indices.append(2)
    indices.append(2); indices.append(5); indices.append(3)
    indices.append(2); indices.append(3); indices.append(0)
    
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, vertices, [], {}, indices)
    return mesh

func _create_pontoon_deck_mesh(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var mesh = ArrayMesh.new()
    var size = config.mesh_size
    
    # Create flat deck platform
    var deck_mesh = BoxMesh.new()
    deck_mesh.size = Vector3(size.x * 0.8, 0.3, size.z * 0.9)
    return deck_mesh

# --- Boat feature helpers ---

func _create_stylized_fishing_cabin(config: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    var cabin_mesh = BoxMesh.new()
    cabin_mesh.size = Vector3(4.0, 2.5, 3.0)
    return cabin_mesh

func _create_stylized_mast_system(config: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    var mast_root = Node3D.new()
    mast_root.name = "MastSystem"
    
    # Mast
    var mast_mesh = CylinderMesh.new()
    mast_mesh.height = config.mesh_size.y * 2.5
    mast_mesh.top_radius = 0.1
    mast_mesh.bottom_radius = 0.15
    
    var mast_instance = MeshInstance3D.new()
    mast_instance.mesh = mast_mesh
    mast_instance.position = Vector3(0, config.mesh_size.y * 1.25, 0)
    mast_instance.material_override = _create_mast_material()
    mast_root.add_child(mast_instance)
    
    # Sail (stylized triangular sail)
    var sail_mesh = PrismMesh.new()
    sail_mesh.size = Vector3(config.mesh_size.z * 0.6, config.mesh_size.y * 1.8, 0.1)
    sail_mesh.subdivide_width = 2
    sail_mesh.subdivide_depth = 2
    
    var sail_instance = MeshInstance3D.new()
    sail_instance.mesh = sail_mesh
    sail_instance.position = Vector3(config.mesh_size.z * 0.2, config.mesh_size.y * 0.9, 0)
    sail_instance.material_override = _create_sail_material()
    mast_root.add_child(sail_instance)
    
    return mast_root

func _add_stylized_fishing_gear(parent: Node3D, rng: RandomNumberGenerator) -> void:
    # Fishing nets (stylized)
    var net_mesh = BoxMesh.new()
    net_mesh.size = Vector3(2.0, 0.1, 4.0)
    
    var net_instance = MeshInstance3D.new()
    net_instance.mesh = net_mesh
    net_instance.position = Vector3(0, 1.8, 2.0)
    net_instance.material_override = _create_net_material()
    parent.add_child(net_instance)
    
    # Fishing poles
    for i in range(2):
        var pole_mesh = CylinderMesh.new()
        pole_mesh.height = 3.0
        pole_mesh.top_radius = 0.05
        pole_mesh.bottom_radius = 0.08
        
        var pole_instance = MeshInstance3D.new()
        pole_instance.mesh = pole_mesh
        pole_instance.position = Vector3(1.0 - i * 2.0, 2.5, -1.0)
        pole_instance.rotation_degrees = Vector3(15, 0, 10 - i * 20)
        pole_instance.material_override = _create_pole_material()
        parent.add_child(pole_instance)


func _add_speedboat_cockpit(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Windshield
    var windshield_mesh = PrismMesh.new()
    windshield_mesh.size = Vector3(3.0, 1.5, 0.1)
    
    var windshield_instance = MeshInstance3D.new()
    windshield_instance.mesh = windshield_mesh
    windshield_instance.position = Vector3(0, 1.2, 2.0)
    windshield_instance.rotation_degrees = Vector3(20, 0, 0)
    windshield_instance.material_override = _create_windshield_material()
    parent.add_child(windshield_instance)
    
    # Dashboard
    var dash_mesh = BoxMesh.new()
    dash_mesh.size = Vector3(2.5, 0.1, 1.0)
    
    var dash_instance = MeshInstance3D.new()
    dash_instance.mesh = dash_mesh
    dash_instance.position = Vector3(0, 0.8, 1.5)
    dash_instance.material_override = _create_dashboard_material()
    parent.add_child(dash_instance)


func _add_speedboat_engine(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    # Engine housing
    var engine_mesh = BoxMesh.new()
    engine_mesh.size = Vector3(1.5, 0.8, 1.2)
    
    var engine_instance = MeshInstance3D.new()
    engine_instance.mesh = engine_mesh
    engine_instance.position = Vector3(0, 0.4, -3.0)
    engine_instance.material_override = _create_engine_material()
    parent.add_child(engine_instance)


func _add_pontoon_tubes(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var size = config.mesh_size
    
    # Left pontoon
    var left_tube = CylinderMesh.new()
    left_tube.height = size.z * 0.8
    left_tube.top_radius = 0.4
    left_tube.bottom_radius = 0.4
    
    var left_instance = MeshInstance3D.new()
    left_instance.mesh = left_tube
    left_instance.position = Vector3(-size.x * 0.4, -0.5, 0)
    left_instance.rotation_degrees = Vector3(90, 0, 0)
    left_instance.material_override = _create_pontoon_material()
    parent.add_child(left_instance)
    
    # Right pontoon
    var right_instance = MeshInstance3D.new()
    right_instance.mesh = left_tube
    right_instance.position = Vector3(size.x * 0.4, -0.5, 0)
    right_instance.rotation_degrees = Vector3(90, 0, 0)
    right_instance.material_override = _create_pontoon_material()
    parent.add_child(right_instance)


func _add_pontoon_railings(parent: Node3D, config: Dictionary, rng: RandomNumberGenerator) -> void:
    var size = config.mesh_size
    
    # Simple railing posts
    for i in range(4):
        var post_mesh = CylinderMesh.new()
        post_mesh.height = 1.0
        post_mesh.top_radius = 0.05
        post_mesh.bottom_radius = 0.05
        
        var post_instance = MeshInstance3D.new()
        post_instance.mesh = post_mesh
        post_instance.position = Vector3(
            -size.x * 0.3 + i * size.x * 0.2,
            0.5,
            -size.z * 0.3
        )
        post_instance.material_override = _create_railing_material()
        parent.add_child(post_instance)


# --- Material creation helpers ---

func _create_stylized_boat_material(boat_type: String) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    
    match boat_type:
        "fishing":
            mat.albedo_color = Color(0.3, 0.2, 0.1)
            mat.roughness = 0.8
        "sailboat":
            mat.albedo_color = Color(0.9, 0.9, 0.9)
            mat.roughness = 0.3
            mat.metallic = 0.1
        "speedboat":
            mat.albedo_color = Color(0.8, 0.2, 0.1)
            mat.roughness = 0.2
            mat.metallic = 0.3
        "pontoon":
            mat.albedo_color = Color(0.7, 0.7, 0.7)
            mat.roughness = 0.4
        _:
            mat.albedo_color = Color(0.5, 0.5, 0.5)
            mat.roughness = 0.5
    
    return mat

func _create_stylized_cabin_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.7, 0.6)
    mat.roughness = 0.7
    return mat

func _create_mast_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.5, 0.4)
    mat.roughness = 0.6
    return mat

func _create_sail_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.95, 0.95, 0.9)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color.a = 0.9
    mat.roughness = 0.8
    return mat

func _create_net_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.3, 0.1)
    mat.roughness = 0.9
    return mat

func _create_pole_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.2)
    mat.roughness = 0.7
    return mat

func _create_windshield_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.85, 0.9)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color.a = 0.3
    mat.roughness = 0.1
    mat.metallic = 0.1
    return mat

func _create_dashboard_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.1, 0.1, 0.1)
    mat.roughness = 0.3
    mat.metallic = 0.2
    return mat

func _create_engine_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)
    mat.roughness = 0.4
    mat.metallic = 0.5
    return mat

func _create_pontoon_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.7, 0.7)
    mat.roughness = 0.3
    mat.metallic = 0.4
    return mat

func _create_railing_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.8, 0.8)
    mat.roughness = 0.2
    mat.metallic = 0.6
    return mat

func _create_buoy_material(color: Color) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.6
    return mat

# --- Positioning and calculation helpers ---

func _get_boat_types_for_scene(scene_type: String) -> Array[String]:
    var scene_config = _lake_defs.lake_types.get(scene_type, {})
    return Array[String](scene_config.get("boat_types", ["fishing"]))

func _calculate_boat_count(lake_radius: float, scene_type: String, params: Dictionary, rng: RandomNumberGenerator) -> int:
    var base_density = params.get("boat_density_per_lake", 0.4)
    var radius_factor = lake_radius / 200.0  # Normalize to 200m radius
    var count = int(base_density * radius_factor * 4.0)  # Scale by radius
    
    # Adjust based on scene type
    match scene_type:
        "harbor":
            count = int(count * 1.5)  # More boats in harbors
        "fishing":
            count = int(count * 0.8)  # Fewer boats in fishing lakes
        "recreational":
            count = int(count * 1.2)  # More boats in recreational areas
    
    return max(1, count)

func _calculate_buoy_count(lake_radius: float, params: Dictionary, rng: RandomNumberGenerator) -> int:
    var density = params.get("buoy_density_per_radius", 2.0)
    return int(density * lake_radius / 100.0)

func _generate_boat_position(lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Vector3:
    # Generate position within lake, avoiding edges
    var angle = rng.randf() * TAU
    var distance = rng.randf_range(lake_radius * 0.2, lake_radius * 0.8)
    
    var pos = lake_center + Vector3(
        cos(angle) * distance,
        0,
        sin(angle) * distance
    )
    
    return pos

func _generate_buoy_position(lake_center: Vector3, lake_radius: float, rng: RandomNumberGenerator) -> Vector3:
    # Buoys tend to be closer to shore or in navigation channels
    var angle = rng.randf() * TAU
    var distance = rng.randf_range(lake_radius * 0.6, lake_radius * 0.95)
    
    var pos = lake_center + Vector3(
        cos(angle) * distance,
        0,
        sin(angle) * distance
    )
    
    return pos

func _select_buoy_type(rng: RandomNumberGenerator) -> String:
    var types = ["navigation", "marker", "racing", "mooring"]
    var weights = [0.4, 0.3, 0.2, 0.1]  # Navigation buoys most common
    
    var total_weight = 0.0
    for w in weights:
        total_weight += w
    
    var roll = rng.randf() * total_weight
    var current_weight = 0.0
    
    for i in range(types.size()):
        current_weight += weights[i]
        if roll <= current_weight:
            return types[i]
    
    return "marker"

func _get_movement_pattern(boat_type: String) -> String:
    var boat_config = _lake_defs.boat_types.get(boat_type, {})
    return boat_config.get("movement_pattern", "static")

func _add_movement_readiness(boat_root: Node3D, boat_type: String) -> void:
    # Add components for future boat movement (static for now)
    var movement_controller = Node3D.new()
    movement_controller.name = "MovementController"
    movement_controller.set_meta("boat_type", boat_type)
    movement_controller.set_meta("is_static", true)  # Start as static
    boat_root.add_child(movement_controller)

func _add_buoy_light(parent: Node3D, config: Dictionary) -> void:
    var light = OmniLight3D.new()
    light.position = Vector3(0, config.height + 0.5, 0)
    light.light_color = config.get("light_color", Color.WHITE)
    light.light_energy = 1.5
    light.omni_range = 10.0
    parent.add_child(light)
