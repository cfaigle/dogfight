class_name BoatDamageableObject
extends BaseDamageableObject

var boat_type: String = "generic"      # "fishing", "sailboat", "speedboat", etc.
var boat_mesh: MeshInstance3D = null    # Reference to main hull mesh
var water_surface_y: float = 0.0       # Y-position of water surface

# Moskva-specific effect tracking
var _moskva_fire_particles: Array[GPUParticles3D] = []
var _moskva_smoke_particles: Array[GPUParticles3D] = []
var _moskva_lights: Array[OmniLight3D] = []
var _is_moskva: bool = false

func _ready() -> void:
    # Find the main hull mesh in the boat hierarchy
    boat_mesh = _find_boat_mesh()

    # Determine object set based on boat type
    var object_set = _determine_object_set(boat_type)

    # Get appropriate health value for this boat type
    var health = _get_health_for_set(object_set)

    # Detect if this is the Moskva (check metadata first, then boat name)
    if get_parent():
        if get_parent().has_meta("is_moskva"):
            _is_moskva = get_parent().get_meta("is_moskva", false)
        elif get_parent().name.to_lower().contains("moskva"):
            _is_moskva = true

        if _is_moskva:
            print("🚢 MOSKVA DETECTED: Special fire/smoke effects will be applied")

    # Check if we can get the original material
    var test_material = _get_original_boat_material()
    var material_found = test_material != null
    var material_color = "none"
    if test_material:
        material_color = "%.2f,%.2f,%.2f" % [test_material.albedo_color.r, test_material.albedo_color.g, test_material.albedo_color.b]

    print("⛵ NEW CODE: Initializing boat '%s' - type: %s, set: %s, health: %.1f, mesh: %s, material: %s, color: %s" % [
        get_parent().name if get_parent() else "?", boat_type, object_set, health,
        boat_mesh != null, material_found, material_color
    ])

    # Register with damage manager
    initialize_damageable(health, object_set)

    # Store water level for sinking effects
    water_surface_y = global_position.y

    # CRITICAL: Connect to DamageManager signals to apply our custom effects
    # DamageManager bypasses apply_damage() and calls set_health() directly, so we need to hook into its signals
    if DamageManager:
        print("🔌 Connecting boat to DamageManager signals: %s" % get_parent().name)
        DamageManager.destruction_stage_changed.connect(_on_damage_manager_stage_changed)
        DamageManager.object_destroyed.connect(_on_damage_manager_destroyed)

## Handle DamageManager's stage change signal (this is how effects are ACTUALLY triggered)
func _on_damage_manager_stage_changed(object, old_stage: int, new_stage: int) -> void:
    # Only respond if this is OUR object
    if object != self:
        return

    print("🎯 DamageManager boat stage change: %s from %d to %d" % [get_parent().name if get_parent() else "?", old_stage, new_stage])

    # Apply appropriate effects based on new stage
    match new_stage:
        1:  # Damaged
            _apply_damaged_effects()
        2:  # Ruined
            _apply_ruined_effects()
        3:  # Destroyed
            _apply_destroyed_effects()

## Handle DamageManager's destruction signal
func _on_damage_manager_destroyed(object) -> void:
    # Only respond if this is OUR object
    if object != self:
        return

    print("💀 DamageManager boat destroyed: %s" % (get_parent().name if get_parent() else "?"))
    # _apply_destroyed_effects() should have already been called by stage change to stage 3
    # But call it again just in case
    _apply_destroyed_effects()

## NOTE: _on_damaged() and _on_destroyed() are NOT called when DamageManager is active
## DamageManager calls set_health() directly and uses its own effect system
## We hook into DamageManager via signals instead (see _on_damage_manager_stage_changed)

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

## Get the boat's ORIGINAL material (always from surface, not override)
## This ensures we always start from the original color when applying damage effects
func _get_original_boat_material() -> StandardMaterial3D:
    if not boat_mesh:
        return null

    # ONLY check surface material (the original), NOT material_override (which may be modified)
    if boat_mesh.mesh and boat_mesh.mesh.get_surface_count() > 0:
        var surface_mat = boat_mesh.mesh.surface_get_material(0)
        if surface_mat and surface_mat is StandardMaterial3D:
            return surface_mat as StandardMaterial3D

    return null

# Override: Apply damage-specific visual effects
func _on_damaged(amount: float) -> void:
    # Call parent to handle destruction stage logic
    super._on_damaged(amount)

    # Add boat-specific hit effect
    _spawn_water_splash()

# Override: Handle complete destruction
func _on_destroyed() -> void:
    # Call parent to handle base destruction logic
    super._on_destroyed()

    # Boat-specific destruction is handled by _apply_destroyed_effects()

## MOSKVA-SPECIFIC PARTICLE HELPERS
func _spawn_moskva_fire_emitter(position: Vector3, scale_range: Vector2) -> GPUParticles3D:
    var fire = GPUParticles3D.new()
    fire.amount = 63  # 25% more particles (50 * 1.25)
    fire.lifetime = 2.5  # Longer lifetime
    fire.one_shot = false
    fire.explosiveness = 0.3

    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process_mat.emission_box_extents = Vector3(12.5, 10.0, 12.5)  # 25% larger emission area
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 30.0
    process_mat.initial_velocity_min = 8.0  # Faster particles
    process_mat.initial_velocity_max = 15.0
    process_mat.gravity = Vector3(0, 1.5, 0)  # Stronger upward (fire rises faster)
    process_mat.scale_min = scale_range.x
    process_mat.scale_max = scale_range.y

    # Orange-red fire gradient
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(1.0, 0.7, 0.2, 1.0))   # Bright orange
    gradient.add_point(0.3, Color(1.0, 0.4, 0.1, 0.9))   # Orange-red
    gradient.add_point(0.7, Color(0.8, 0.2, 0.0, 0.4))   # Dark red
    gradient.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))   # Fade out

    var gradient_tex = GradientTexture1D.new()
    gradient_tex.gradient = gradient
    process_mat.color_ramp = gradient_tex

    fire.process_material = process_mat

    # Mesh and material
    var mesh = QuadMesh.new()
    mesh.size = Vector2(6.25, 6.25)  # 25% larger base mesh for fire
    fire.draw_pass_1 = mesh

    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.albedo_color = Color(1.0, 0.5, 0.1, 1.0)
    mesh.surface_set_material(0, mat)

    get_parent().add_child(fire)
    fire.global_position = position
    fire.emitting = true

    return fire

func _spawn_moskva_smoke_emitter(position: Vector3, scale_range: Vector2) -> GPUParticles3D:
    var smoke = GPUParticles3D.new()
    smoke.amount = 160  # DOUBLE particles (80 * 2)
    smoke.lifetime = 6.0  # Longer lasting smoke
    smoke.one_shot = false
    smoke.explosiveness = 0.05
    smoke.randomness = 0.4

    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 30.0  # DOUBLE emission area (15.0 * 2)
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 35.0
    process_mat.initial_velocity_min = 5.0  # Faster smoke
    process_mat.initial_velocity_max = 10.0
    process_mat.gravity = Vector3(0, -0.3, 0)  # Heavy smoke but rises
    process_mat.scale_min = scale_range.x
    process_mat.scale_max = scale_range.y

    # Dark grey-to-black smoke gradient
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color(0.3, 0.3, 0.3, 0.8))   # Medium grey
    gradient.add_point(0.3, Color(0.2, 0.2, 0.2, 0.9))   # Dark grey
    gradient.add_point(0.7, Color(0.15, 0.15, 0.15, 0.5))  # Very dark
    gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))   # Fade out

    var gradient_tex = GradientTexture1D.new()
    gradient_tex.gradient = gradient
    process_mat.color_ramp = gradient_tex

    smoke.process_material = process_mat

    # Mesh and material
    var mesh = QuadMesh.new()
    mesh.size = Vector2(16.0, 16.0)  # DOUBLE base mesh for smoke (8.0 * 2)
    smoke.draw_pass_1 = mesh

    var mat = StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
    mesh.surface_set_material(0, mat)

    get_parent().add_child(smoke)
    smoke.global_position = position
    smoke.emitting = true

    return smoke

func _cleanup_moskva_effects():
    for fire in _moskva_fire_particles:
        if is_instance_valid(fire):
            fire.emitting = false
            fire.queue_free()
    for smoke in _moskva_smoke_particles:
        if is_instance_valid(smoke):
            smoke.emitting = false
            smoke.queue_free()
    for light in _moskva_lights:
        if is_instance_valid(light):
            light.queue_free()
    _moskva_fire_particles.clear()
    _moskva_smoke_particles.clear()
    _moskva_lights.clear()

# Stage 1: Moderate damage (50-25% health)
func _apply_damaged_effects() -> void:
    print("🔧 _apply_damaged_effects CALLED for boat: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), boat_mesh != null
    ])

    if not is_inside_tree() or not boat_mesh:
        print("⚠️ EARLY RETURN: Not in tree or no mesh")
        return

    # Get ORIGINAL material from surface (not override)
    var original_material: StandardMaterial3D = _get_original_boat_material()

    if not original_material:
        print("⚠️ Cannot find material for boat damage effects on: %s" % get_parent().name)
        return

    # DUPLICATE the original material to avoid modifying shared resources
    var damaged_material = original_material.duplicate() as StandardMaterial3D

    # Get original color
    var original_color = damaged_material.albedo_color

    # DRAMATIC darkening: 50% of ORIGINAL (not compounding)
    damaged_material.albedo_color = Color(
        original_color.r * 0.5,
        original_color.g * 0.5,
        original_color.b * 0.5,
        original_color.a
    )

    # Apply the modified material
    boat_mesh.material_override = damaged_material

    print("💥 BOAT DAMAGE EFFECT: Darkened '%s' to 50%% brightness (from %.2f,%.2f,%.2f)" % [get_parent().name, original_color.r, original_color.g, original_color.b])

# Stage 2: Heavy damage (25-0% health)
func _apply_ruined_effects() -> void:
    print("🔧 _apply_ruined_effects CALLED for boat: %s (in_tree: %s, has_mesh: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree(), boat_mesh != null
    ])

    if not is_inside_tree() or not boat_mesh:
        print("⚠️ EARLY RETURN: Not in tree or no mesh")
        return

    # Get ORIGINAL material from surface (not override)
    var original_material: StandardMaterial3D = _get_original_boat_material()
    if not original_material:
        return

    var ruined_material = original_material.duplicate() as StandardMaterial3D

    # VERY DRAMATIC darkening: 70% of ORIGINAL (not compounding)
    var original_color = ruined_material.albedo_color
    ruined_material.albedo_color = Color(
        original_color.r * 0.3,
        original_color.g * 0.3,
        original_color.b * 0.35,  # Slightly more blue for water damage
        original_color.a
    )

    # INTENSE fire/damage glow
    ruined_material.emission_enabled = true
    ruined_material.emission = Color(1.0, 0.5, 0.0)  # Bright orange
    ruined_material.emission_energy_multiplier = 2.0  # Double intensity

    boat_mesh.material_override = ruined_material

    # Start spawning smoke particles
    _spawn_damage_smoke()

    # MOSKVA-SPECIFIC: Add dramatic fire and smoke effects
    if _is_moskva and get_parent():
        print("🔥🚢 MOSKVA RUINED: Checking fire and smoke settings...")

        # Get mesh size from metadata or calculate from bounds
        var mesh_size: Vector3 = get_parent().get_meta("mesh_size", Vector3(840, 180, 120))
        var boat_pos = get_parent().global_position

        # Check if fire effects are enabled
        if Game.settings.get("enable_moskva_fire", true):
            print("🔥 Fire enabled - spawning fire emitters")
            # Fire positions (on deck, strategic damage points) - MORE FIRES!
            var fire_positions = [
                boat_pos + Vector3(mesh_size.x * 0.3, mesh_size.y * 0.3, 0),      # Bow
                boat_pos + Vector3(-mesh_size.x * 0.3, mesh_size.y * 0.3, 0),     # Stern
                boat_pos + Vector3(0, mesh_size.y * 0.4, mesh_size.z * 0.2),      # Superstructure
                boat_pos + Vector3(0, mesh_size.y * 0.3, -mesh_size.z * 0.2),     # Mid-deck
                boat_pos + Vector3(mesh_size.x * 0.15, mesh_size.y * 0.35, mesh_size.z * 0.1),   # Port bow
                boat_pos + Vector3(-mesh_size.x * 0.15, mesh_size.y * 0.35, mesh_size.z * 0.1),  # Starboard bow
                boat_pos + Vector3(mesh_size.x * 0.2, mesh_size.y * 0.32, -mesh_size.z * 0.15)   # Port mid
            ]

            # Spawn fire emitters with 25% larger scale
            for fire_pos in fire_positions:
                var fire = _spawn_moskva_fire_emitter(fire_pos, Vector2(12.5, 25.0))  # 25% larger (was 10-20)
                _moskva_fire_particles.append(fire)

                # Add fire light
                var light = OmniLight3D.new()
                light.light_color = Color(1.0, 0.5, 0.1)
                light.light_energy = 30.0  # Brighter light for massive fire
                light.omni_range = 100.0  # Much larger range
                get_parent().add_child(light)
                light.global_position = fire_pos
                _moskva_lights.append(light)

            print("🔥 Spawned ", _moskva_fire_particles.size(), " fire emitters")
        else:
            print("🔥 Fire disabled by settings")

        # Check if smoke effects are enabled
        if Game.settings.get("enable_moskva_smoke", true):
            print("💨 Smoke enabled - spawning smoke emitters")
            # Smoke positions (above deck, offset from center)
            var smoke_positions = [
                boat_pos + Vector3(mesh_size.x * 0.2, mesh_size.y * 0.5, 0),
                boat_pos + Vector3(-mesh_size.x * 0.2, mesh_size.y * 0.5, 0)
            ]

            # Spawn thick smoke emitters with DOUBLED scale
            for smoke_pos in smoke_positions:
                var smoke = _spawn_moskva_smoke_emitter(smoke_pos, Vector2(40.0, 80.0))  # DOUBLE size (was 20-40)
                _moskva_smoke_particles.append(smoke)

            print("💨 Spawned ", _moskva_smoke_particles.size(), " smoke emitters")
        else:
            print("💨 Smoke disabled by settings")

    print("🔥 BOAT RUINED EFFECT: Heavily damaged with fire! (from %.2f,%.2f,%.2f)" % [original_color.r, original_color.g, original_color.b])

# Stage 3: Destroyed (0% health)
func _apply_destroyed_effects() -> void:
    print("🔧 _apply_destroyed_effects CALLED for boat: %s (in_tree: %s)" % [
        get_parent().name if get_parent() else "?", is_inside_tree()
    ])

    if not is_inside_tree():
        print("⚠️ EARLY RETURN: Not in tree")
        return

    # Generate floating debris
    _generate_boat_debris()

    # Material: VERY dark (almost black) with intense fire
    var original_material = _get_original_boat_material()
    if original_material and boat_mesh:
        var destroyed_mat = original_material.duplicate()
        destroyed_mat.albedo_color = Color(0.1, 0.1, 0.15)  # Nearly black with blue tint
        destroyed_mat.emission_enabled = true
        destroyed_mat.emission = Color(1.0, 0.6, 0.2)  # Bright fire
        destroyed_mat.emission_energy_multiplier = 3.0  # Very intense
        boat_mesh.material_override = destroyed_mat

    # Start sinking animation
    _start_sinking_animation()

    # Big explosion effect
    _spawn_destruction_explosion()

    print("💥 BOAT DESTROYED: Sinking with massive explosion!")

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
    get_tree().create_timer(3.0).timeout.connect(
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

    # MOSKVA-SPECIFIC: Enhance fire and smoke during sinking
    if _is_moskva:
        print("🔥💥 MOSKVA SINKING: Checking if effects should be intensified...")

        var mesh_size: Vector3 = boat_node.get_meta("mesh_size", Vector3(840, 180, 120))
        var boat_pos = boat_node.global_position

        # Check if fire effects are enabled
        if Game.settings.get("enable_moskva_fire", true):
            print("🔥 Intensifying fire for sinking")
            # More fire emitters for sinking - INFERNO!
            var extra_fire_positions = [
                boat_pos + Vector3(mesh_size.x * 0.15, mesh_size.y * 0.35, mesh_size.z * 0.15),
                boat_pos + Vector3(-mesh_size.x * 0.15, mesh_size.y * 0.35, -mesh_size.z * 0.15),
                boat_pos + Vector3(mesh_size.x * 0.25, mesh_size.y * 0.38, 0),  # Additional port fire
                boat_pos + Vector3(-mesh_size.x * 0.25, mesh_size.y * 0.38, 0)  # Additional starboard fire
            ]

            for fire_pos in extra_fire_positions:
                var fire = _spawn_moskva_fire_emitter(fire_pos, Vector2(18.75, 37.5))  # 25% larger (was 15-30)
                _moskva_fire_particles.append(fire)

                # Intense light for sinking
                var light = OmniLight3D.new()
                light.light_color = Color(1.0, 0.4, 0.1)
                light.light_energy = 50.0  # VERY dramatic
                light.omni_range = 150.0  # Huge range
                boat_node.add_child(light)
                light.global_position = fire_pos
                _moskva_lights.append(light)

        # Check if smoke effects are enabled
        if Game.settings.get("enable_moskva_smoke", true):
            print("💨 Adding massive smoke plume for sinking")
            # Add massive black smoke plume from center - DOUBLED!
            var center_smoke_pos = boat_pos + Vector3(0, mesh_size.y * 0.6, 0)
            var massive_smoke = GPUParticles3D.new()
            massive_smoke.amount = 240  # DOUBLE particles (120 * 2)
            massive_smoke.lifetime = 8.0  # Very long lasting
            massive_smoke.one_shot = false
            massive_smoke.explosiveness = 0.05

            var process_mat = ParticleProcessMaterial.new()
            process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
            process_mat.emission_sphere_radius = 40.0  # DOUBLE emission area (20.0 * 2)
            process_mat.direction = Vector3(0, 1, 0)
            process_mat.spread = 30.0
            process_mat.initial_velocity_min = 8.0  # Much faster
            process_mat.initial_velocity_max = 15.0
            process_mat.gravity = Vector3(0, -0.2, 0)  # Lighter gravity, rises higher
            process_mat.scale_min = 60.0  # DOUBLE size (was 30.0)
            process_mat.scale_max = 120.0  # DOUBLE size (was 60.0)

            # Very dark smoke
            var gradient = Gradient.new()
            gradient.add_point(0.0, Color(0.1, 0.1, 0.1, 1.0))
            gradient.add_point(0.5, Color(0.08, 0.08, 0.08, 0.7))
            gradient.add_point(1.0, Color(0.05, 0.05, 0.05, 0.0))

            var gradient_tex = GradientTexture1D.new()
            gradient_tex.gradient = gradient
            process_mat.color_ramp = gradient_tex

            massive_smoke.process_material = process_mat

            var mesh = QuadMesh.new()
            mesh.size = Vector2(20.0, 20.0)  # DOUBLE base mesh (was 10.0)
            massive_smoke.draw_pass_1 = mesh

            var mat = StandardMaterial3D.new()
            mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
            mat.albedo_color = Color(0.1, 0.1, 0.1, 1.0)
            mesh.surface_set_material(0, mat)

            boat_node.add_child(massive_smoke)
            massive_smoke.global_position = center_smoke_pos
            massive_smoke.emitting = true
            _moskva_smoke_particles.append(massive_smoke)

        print("🔥 Enhanced sinking: ", _moskva_fire_particles.size(), " fires, ", _moskva_smoke_particles.size(), " smoke emitters")

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

    # Delete boat after sinking and cleanup Moskva effects
    tween.tween_callback(
        func():
            if _is_moskva:
                print("🧹 Cleaning up Moskva effects...")
                _cleanup_moskva_effects()
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
    smoke.position = Vector3(0, 3.0, 0)  # Above boat deck
    smoke.amount = 40  # More particles (was 15)
    smoke.lifetime = 2.5  # Longer lasting
    smoke.explosiveness = 0.2
    smoke.randomness = 0.4

    # Make smoke LARGE and VISIBLE
    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 2.0
    process_mat.direction = Vector3(0, 1, 0)  # Rise upward
    process_mat.gravity = Vector3(0, -0.5, 0)  # Light gravity (smoke rises)
    process_mat.initial_velocity_min = 2.0
    process_mat.initial_velocity_max = 4.0
    process_mat.scale_min = 1.5  # Large particles
    process_mat.scale_max = 3.0
    smoke.process_material = process_mat

    get_parent().add_child(smoke)
    smoke.emitting = true

    print("💨 Heavy smoke spawned on boat: %s" % get_parent().name)

# Spawn large explosion when destroyed
func _spawn_destruction_explosion() -> void:
    # Create a massive one-shot explosion
    var explosion = GPUParticles3D.new()
    explosion.name = "BoatDestructionExplosion"
    explosion.position = global_position + Vector3(0, 2.0, 0)  # Slightly above water
    explosion.amount = 80  # Large explosion
    explosion.lifetime = 0.6
    explosion.one_shot = true
    explosion.explosiveness = 1.0

    # Explosive burst in all directions
    var process_mat = ParticleProcessMaterial.new()
    process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process_mat.emission_sphere_radius = 1.5
    process_mat.direction = Vector3(0, 1, 0)
    process_mat.spread = 180.0  # All directions
    process_mat.initial_velocity_min = 8.0
    process_mat.initial_velocity_max = 16.0
    process_mat.gravity = Vector3(0, -9.8, 0)
    process_mat.scale_min = 0.8
    process_mat.scale_max = 2.5
    process_mat.color = Color(1.0, 0.7, 0.3)  # Bright orange
    process_mat.damping_min = 2.0
    process_mat.damping_max = 5.0
    explosion.process_material = process_mat

    get_tree().root.add_child(explosion)
    explosion.emitting = true

    # Remove after explosion finishes
    get_tree().create_timer(2.0).timeout.connect(
        func():
            if is_instance_valid(explosion):
                explosion.queue_free()
    , CONNECT_ONE_SHOT)

    print("💥 Massive boat explosion spawned!")
