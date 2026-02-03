class_name BoatDamageableObject
extends BaseDamageableObject

var boat_type: String = "generic"      # "fishing", "sailboat", "speedboat", etc.
var boat_mesh: MeshInstance3D = null    # Reference to main hull mesh
var water_surface_y: float = 0.0       # Y-position of water surface

func _ready() -> void:
    # Find the main hull mesh in the boat hierarchy
    boat_mesh = _find_boat_mesh()

    # Determine object set based on boat type
    var object_set = _determine_object_set(boat_type)

    # Get appropriate health value for this boat type
    var health = _get_health_for_set(object_set)

    # Register with damage manager
    initialize_damageable(health, object_set)

    # Store water level for sinking effects
    water_surface_y = global_position.y

func _find_boat_mesh() -> MeshInstance3D:
    # Search for the main hull mesh in children
    for child in get_parent().get_children():
        if child is MeshInstance3D and "Hull" in child.name:
            return child
        # Recursively search if not found at top level
        for subchild in child.get_children():
            if subchild is MeshInstance3D:
                return subchild
    return null

func _determine_object_set(b_type: String) -> String:
    # Map boat types to object sets (health ranges)
    var type_to_set_map = {
        "fishing": "Maritime_Light",        # 50-80 HP
        "sailboat": "Maritime_Light",       # 50-80 HP
        "speedboat": "Maritime_Light",      # 50-80 HP
        "pontoon": "Maritime_Light",        # 50-80 HP
        "yacht": "Maritime_Medium",         # 80-120 HP
        "cruiser": "Maritime_Medium",       # 80-120 HP
        "trawler": "Maritime_Heavy",        # 120-180 HP
        "tugboat": "Maritime_Heavy",        # 120-180 HP
        "ferry": "Maritime_Heavy",          # 120-180 HP
        "freighter": "Maritime_Heavy",      # 120-180 HP
    }
    return type_to_set_map.get(b_type, "Maritime_Light")

func _get_health_for_set(object_set: String) -> float:
    # Get health range from DamageManager config
    if not DamageManager:
        return 80.0

    var set_config = DamageManager.get_set_config(object_set)
    if set_config and set_config.has("health_range"):
        var health_range = set_config.health_range
        return randf_range(health_range.min, health_range.max)

    return 80.0  # Default boat health

# Override: Apply damage-specific visual effects
func _on_damaged(amount: float) -> void:
    # Spawn water splash effect at hit location
    _spawn_water_splash()

    # Check destruction stage and apply appropriate effects
    var health_percent = health / max_health

    if health_percent > 0.5:
        # Light damage - no visible effects yet
        pass
    elif health_percent > 0.25:
        # Moderate damage - darken materials
        _apply_damaged_effects()
    else:
        # Heavy damage - add smoke/fire
        _apply_ruined_effects()

# Override: Handle complete destruction
func _on_destroyed() -> void:
    _apply_destroyed_effects()

# Stage 1: Moderate damage (50-25% health)
func _apply_damaged_effects() -> void:
    if not boat_mesh or not boat_mesh.material_override:
        return

    var material = boat_mesh.material_override as StandardMaterial3D
    if not material:
        return

    # Darken the boat material (20% darker)
    var current_color = material.albedo_color
    material.albedo_color = Color(
        current_color.r * 0.8,
        current_color.g * 0.8,
        current_color.b * 0.8,
        current_color.a
    )

# Stage 2: Heavy damage (25-0% health)
func _apply_ruined_effects() -> void:
    if not boat_mesh or not boat_mesh.material_override:
        return

    var material = boat_mesh.material_override as StandardMaterial3D
    if not material:
        return

    # Very dark, with scorch marks (40% darker, blue-ish tint for water damage)
    var current_color = material.albedo_color
    material.albedo_color = Color(
        current_color.r * 0.6,
        current_color.g * 0.6,
        current_color.b * 0.7,  # Slightly more blue for water damage
        current_color.a
    )

    # Add fire/smoke emission
    material.emission_enabled = true
    material.emission = Color(0.8, 0.4, 0.1)  # Orange fire glow
    material.emission_energy = 0.5

    # Start spawning smoke particles
    _spawn_damage_smoke()

# Stage 3: Destroyed (0% health)
func _apply_destroyed_effects() -> void:
    # Generate floating debris
    _generate_boat_debris()

    # Massive smoke/fire
    if boat_mesh and boat_mesh.material_override:
        var material = boat_mesh.material_override as StandardMaterial3D
        if material:
            # Very dark, burned appearance
            material.albedo_color = Color(0.2, 0.2, 0.25)
            material.emission = Color(0.9, 0.5, 0.2)
            material.emission_energy = 1.0

    # Start sinking animation
    _start_sinking_animation()

    # Big explosion effect
    _spawn_destruction_explosion()

# Generate boat-specific debris (floating wood pieces)
func _generate_boat_debris() -> void:
    if not DamageManager:
        return

    var debris_count = randi_range(3, 8)  # More debris for boats

    for i in range(debris_count):
        _create_floating_debris_piece()

# Create a single floating debris piece
func _create_floating_debris_piece() -> void:
    var debris = RigidBody3D.new()
    debris.name = "BoatDebris_%d" % randi()

    # Spawn near the boat, slightly above water
    var spawn_offset = Vector3(
        randf_range(-3, 3),
        randf_range(-0.5, 1.5),
        randf_range(-3, 3)
    )
    debris.position = global_position + spawn_offset

    # Create debris mesh (wood plank or box)
    var mesh_instance = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    var debris_size = randf_range(0.5, 1.5)
    box_mesh.size = Vector3(debris_size, debris_size * 0.3, debris_size * 2.0)  # Plank shape
    mesh_instance.mesh = box_mesh

    # Copy material from boat (or use brown wood color)
    if boat_mesh and boat_mesh.material_override:
        mesh_instance.material_override = boat_mesh.material_override.duplicate()
    else:
        var wood_mat = StandardMaterial3D.new()
        wood_mat.albedo_color = Color(0.4, 0.25, 0.15)  # Brown wood
        mesh_instance.material_override = wood_mat

    debris.add_child(mesh_instance)

    # Add collision shape
    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    box_shape.size = box_mesh.size
    collision_shape.shape = box_shape
    debris.add_child(collision_shape)

    # Add to scene
    get_tree().root.add_child(debris)

    # Apply outward explosion impulse
    var impulse_direction = (debris.global_position - global_position).normalized()
    var impulse_force = randf_range(30, 100)
    debris.apply_central_impulse(impulse_direction * impulse_force)

    # Add upward component (debris flies up from explosion)
    debris.apply_central_impulse(Vector3(0, randf_range(20, 50), 0))

    # Apply random torque for spinning
    debris.apply_torque_impulse(Vector3(
        randf_range(-10, 10),
        randf_range(-10, 10),
        randf_range(-10, 10)
    ))

    # Auto-cleanup after 10 seconds (debris floats longer than building debris)
    get_tree().create_timer(10.0).timeout.connect(
        func():
            if is_instance_valid(debris):
                # Fade out
                var tween = debris.create_tween()
                tween.tween_property(mesh_instance, "transparency", 1.0, 2.0)
                tween.tween_callback(debris.queue_free)
    , CONNECT_ONE_SHOT)

# Sinking animation: gradually lower boat into water
func _start_sinking_animation() -> void:
    if not get_parent():
        return

    var boat_node = get_parent()
    var tween = create_tween()

    # Sink 10 units down over 5 seconds
    tween.tween_property(boat_node, "position:y", boat_node.position.y - 10.0, 5.0)

    # Also tilt the boat slightly (random rotation)
    var random_tilt = Vector3(
        randf_range(-15, 15),
        randf_range(-30, 30),
        randf_range(-15, 15)
    )
    tween.parallel().tween_property(
        boat_node,
        "rotation_degrees",
        boat_node.rotation_degrees + random_tilt,
        5.0
    )

    # Fade out material
    if boat_mesh and boat_mesh.material_override:
        var material = boat_mesh.material_override as StandardMaterial3D
        if material:
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            tween.parallel().tween_property(material, "albedo_color:a", 0.0, 5.0)

    # Delete boat after sinking
    tween.tween_callback(
        func():
            if is_instance_valid(boat_node):
                boat_node.queue_free()
    )

# Spawn water splash particles when hit
func _spawn_water_splash() -> void:
    var splash = GPUParticles3D.new()
    splash.name = "WaterSplash"
    splash.position = global_position
    splash.amount = 20
    splash.lifetime = 0.5
    splash.one_shot = true
    splash.explosiveness = 0.8

    # TODO: Configure particle material with blue/white water droplets
    # For now, use basic setup

    get_tree().root.add_child(splash)
    splash.emitting = true

    # Auto-cleanup
    get_tree().create_timer(1.0).timeout.connect(splash.queue_free, CONNECT_ONE_SHOT)

# Spawn smoke from damaged boat
func _spawn_damage_smoke() -> void:
    # Check if smoke already exists
    if get_parent().has_node("DamageSmoke"):
        return

    var smoke = GPUParticles3D.new()
    smoke.name = "DamageSmoke"
    smoke.position = Vector3(0, 2.0, 0)  # Above boat deck
    smoke.amount = 15
    smoke.lifetime = 2.0
    smoke.explosiveness = 0.0
    smoke.randomness = 0.3

    # TODO: Configure smoke material (dark gray, rising)

    get_parent().add_child(smoke)
    smoke.emitting = true

# Spawn large explosion when destroyed
func _spawn_destruction_explosion() -> void:
    # Use existing explosion system if available
    var explosion_scene_path = "res://scripts/fx/explosion.tscn"
    if ResourceLoader.exists(explosion_scene_path):
        var explosion_scene = load(explosion_scene_path)
        var explosion = explosion_scene.instantiate()
        explosion.position = global_position
        # Scale based on boat size
        explosion.scale = Vector3.ONE * 2.0
        get_tree().root.add_child(explosion)
