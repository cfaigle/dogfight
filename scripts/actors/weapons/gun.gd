extends Node3D

var _flash_mesh: QuadMesh = QuadMesh.new()

@export var defs: Resource
# Keep this as a plain Array for maximum compatibility across GDScript versions.
@export var muzzle_paths: Array = []
@export var owner_hitbox_path: NodePath = NodePath("Hitbox")
@export var tracer_scene: PackedScene

var _muzzles: Array = []  # Array of Node3D muzzle points (resolved from muzzle_paths)

const AutoDestructScript = preload("res://scripts/components/auto_destruct.gd")
const ExplosionScript = preload("res://scripts/fx/explosion.gd")
const SmokeScene = preload("res://effects/particle_smoke.tscn")

# Hit effect particles (preloaded for performance)
const FX_SPARKS = preload("res://effects/particle_sparks.tscn")
const FX_WOOD_DEBRIS = preload("res://effects/particle_wood_debris.tscn")
const FX_DUST = preload("res://effects/particle_dust.tscn")
const FX_LEAVES = preload("res://effects/particle_leaves.tscn")

# Sound effects
const SND_SHOT = preload("res://sounds/shot.wav")
const SND_TERRAIN_HIT = preload("res://sounds/thwack-02.wav")
const SND_NON_DAMAGEABLE_HIT = preload("res://sounds/thwack-10.wav")

var cooldown = 0.075
var heat_per_shot = 0.055
var damage = 10.0
var range = 1600.0
var spread_deg = 0.35
var tracer_life = 0.2 # 0.065

var _t = 0.0
var heat = 0.0 # 0..1

func _ready() -> void:
    if muzzle_paths.is_empty():
        # These paths are resolved relative to our parent (Plane), see fire().
        muzzle_paths = [NodePath("Muzzles/Left"), NodePath("Muzzles/Right")]
    if defs:
        _apply(defs.gun)
    # Muzzle flash quad (initialized here to avoid top-level statements).
    if _flash_mesh == null:
        _flash_mesh = QuadMesh.new()
    _flash_mesh.size = Vector2(0.9, 0.45)

func _process(dt: float) -> void:
    _t = max(_t - dt, 0.0)
    # Changed CTF to increase cooldown:
    heat = max(heat - dt * 0.66, 0.0)
#   heat = max(heat - dt * 0.25, 0.0)

func can_fire() -> bool:
    return heat < 0.98 # Changed CTF so can fire more rapidly - its an arcade game!
    # return _t <= 0.0 and heat < 0.98

func fire(aim_dir: Vector3) -> void:
    if not can_fire():
        return
    

    _t = cooldown
    # Changed CTF - divided the heat factor by 12 so you can more or less 
    #               continually shoot:
    heat = min(heat + (heat_per_shot/12), 1.0)
    
    # Play gunshot sound
    _play_shot_sound()

    # Decide if this is the player's gun (duck-typed + safe).
    var is_player := false
    var p := get_parent()
    if p and p is Node and (p as Node).is_in_group("player"):
        is_player = true

    # Enhanced camera shake so shooting feels more impactful.
    if is_player:
        Game.add_camera_shake(0.35)  # Increased from 0.18 to 0.35 for more noticeable effect

    # Get a convergence / aim point if the owner provides it.
    var aim_point: Vector3 = Vector3.ZERO

    # Check if target lock is enabled in settings
    var target_lock_enabled: bool = true
    if Game.settings.has("enable_target_lock"):
        target_lock_enabled = bool(Game.settings.get("enable_target_lock", true))
    else:
        target_lock_enabled = true

    if p != null and (p as Node).has_method("gun_aim_point") and target_lock_enabled:
        var ap = (p as Node).call("gun_aim_point", range)
        if typeof(ap) == TYPE_VECTOR3:
            # Check if the target is reasonably close to the player to avoid aiming at distant objects
            var distance_to_target = (ap - global_position).length()
            var max_target_distance = range * 0.8  # Only aim at targets within 80% of our range

            # Target lock enabled - use calculated aim point
            if distance_to_target <= max_target_distance:
                aim_point = ap
            else:
                # Target is too far, aim straight ahead instead
                # Calculate forward direction from the parent plane
                if p.has_method("get_forward"):
                    var forward_dir = (p as Node).call("get_forward")
                    aim_point = global_position + forward_dir * range
                else:
                    aim_point = global_position + aim_dir * range
        else:
            # Calculate forward direction from the parent plane
            if p.has_method("get_forward"):
                var forward_dir = (p as Node).call("get_forward")
                aim_point = global_position + forward_dir * range
            else:
                aim_point = global_position + aim_dir * range
    else:
        # Either no gun_aim_point method or target lock is disabled, aim straight ahead
        # Calculate forward direction from the parent plane
        if p and p.has_method("get_forward"):
            var forward_dir = (p as Node).call("get_forward")
            aim_point = global_position + forward_dir * range
            if randf() < 0.05:  # Print every ~5% of shots when in free-fire mode
                print("DEBUG: Free-fire mode. Forward dir: ", forward_dir, " Aim point: ", aim_point)
        else:
            aim_point = global_position + aim_dir * range

    # Aim point calculated - ready to fire

    # Raycast from each muzzle toward the convergence point.
    var space = get_world_3d().space
    if not space:
        print("ERROR: Could not get physics space!")
        return
    var exclude_rids: Array[RID] = []
    var hb = _resolve_owner_hitbox()
    if hb:
        exclude_rids.append(hb.get_rid())

    # Resolve muzzle nodes from configured paths (relative to the owning plane).
    _muzzles.clear()
    if p and p is Node:
        for mp in muzzle_paths:
            var mn: Node3D = (p as Node).get_node_or_null(mp) as Node3D
            if mn != null:
                _muzzles.append(mn)
    if _muzzles.is_empty():
        # Fall back to firing from this node if muzzle points are missing.
        _muzzles.append(self)

    # Processing muzzles for firing

    for m in _muzzles:
        var muzzle_pos: Vector3 = (m as Node3D).global_position
        var dir: Vector3 = (aim_point - muzzle_pos).normalized()
        dir = _apply_spread(dir, deg_to_rad(spread_deg))

        # Raycast starts from muzzle for accurate hit detection
        var raycast_offset: float = 0.5  # Tiny offset to prevent self-collision
        var origin: Vector3 = muzzle_pos + dir * raycast_offset

        # Visual tracer starts further out to avoid obscuring the plane
        var tracer_start_offset: float = 75.0  # Visual clarity
        var tracer_start: Vector3 = muzzle_pos + dir * tracer_start_offset

        var to = origin + dir * range

        var query = PhysicsRayQueryParameters3D.create(origin, to)
        query.exclude = exclude_rids
        query.collision_mask = 1  # Environment layer
        query.collide_with_areas = true
        query.collide_with_bodies = true

        var space_state = PhysicsServer3D.space_get_direct_state(space)
        var hit = space_state.intersect_ray(query)

        var hit_pos = to
        var did_hit := false
        if hit and hit.size() > 0:
            if hit.has("position"):
                hit_pos = hit.position
                did_hit = true
                var collider = hit.collider

                # DEBUG: Always print what we hit for debugging
                if collider is Node:
                    var collider_node = collider as Node
                    var has_meta = collider_node.has_meta("damage_target")
                    var meta_target = collider_node.get_meta("damage_target") if has_meta else null
                    var is_tree_collision = "Tree" in collider_node.name and "_Collision" in collider_node.name
                    print("🔫 RAYCAST HIT: '%s' at (%.0f, %.0f, %.0f) (type: %s) - Has damage_target: %s - Target: %s - IsTreeCollision: %s" % [
                        collider_node.name,
                        hit_pos.x, hit_pos.y, hit_pos.z,
                        collider_node.get_class(),
                        has_meta,
                        meta_target.name if meta_target else "none",
                        is_tree_collision
                    ])
                else:
                    print("🔫 RAYCAST HIT: Non-node object: %s" % str(collider))

                _apply_damage_to_collider(collider, damage)

        _spawn_tracer(tracer_start, hit_pos, is_player)

        # Check settings before spawning effects
        if Game.settings.get("enable_muzzle_flash", true):
            if _check_particle_budget("muzzle_flashes", Game.settings.get("max_active_muzzle_flashes", 300)):
                _spawn_muzzle_flash((m as Node3D), dir, 0.8)

        if did_hit:
            if Game.settings.get("enable_impact_sparks", true):
                if _check_particle_budget("impact_sparks", Game.settings.get("max_active_impact_effects", 100)):
                    _spawn_impact_spark(hit_pos)
            if Game.settings.get("enable_bullet_hit_effects", true):
                _create_bullet_hit_effects(hit_pos, hit.collider if hit else null)
            if Game.settings.get("enable_smoke_trails", true):
                _spawn_smoke_trail(hit_pos)  # 320 particles/hit - can cause GPU overload!
            if Game.settings.get("enable_hit_sounds", true):
                _play_hit_sound(hit.collider if hit else null)
            if is_player:
                GameEvents.hit_confirmed.emit(1.0)

func _resolve_owner_hitbox() -> CollisionObject3D:
    # Look for owner hitbox relative to our parent (Plane).
    var p = get_parent()
    if p and p is Node:
        var hb = p.get_node_or_null(owner_hitbox_path)
        if hb and hb is CollisionObject3D:
            return hb
    return null

func _apply_damage_to_collider(obj: Object, dmg: float) -> void:
    if obj == null:
        return

    # Check if this collision body has a metadata link to the actual damage target
    var n := obj as Node
    if n and n.has_meta("damage_target"):
        var target = n.get_meta("damage_target")
        print("🔗 REDIRECT: Collision '%s' -> Target '%s' (Valid: %s, In tree: %s)" % [
            n.name,
            target.name if target else "null",
            is_instance_valid(target),
            target.is_inside_tree() if target else false
        ])
        if target and is_instance_valid(target):
            # Recursively apply damage to the actual target
            _apply_damage_to_collider(target, dmg)
            return
        else:
            print("⚠️ ERROR: damage_target metadata exists but target is invalid!")
            return

    # First, try walking up the parent chain to find a node with apply_damage
    while n:
        if n.has_method("apply_damage"):
            # Check if the node is still in the tree before applying damage
            if n.is_inside_tree():
                # Debug damage application
                print("💥 FOUND apply_damage: node='%s', id=%d, class=%s" % [n.name, n.get_instance_id(), n.get_class()])
                # Prefer DamageManager if present and compatible, otherwise call apply_damage directly.
                if DamageManager and DamageManager.has_method("apply_damage_to_object"):
                    DamageManager.apply_damage_to_object(n, dmg, "bullet")
                    return
                n.call("apply_damage", dmg)
                return
            else:
                return
        n = n.get_parent()

    # If no apply_damage method found in parent chain, check children for damageable components
    var node_obj := obj as Node
    if node_obj:
        var damageable_found = _find_damageable_in_children(node_obj)
        if damageable_found:
            # Debug damage application to children
            print("💥 FOUND apply_damage (child): node='%s', id=%d, parent='%s'" % [
                damageable_found.name, damageable_found.get_instance_id(), node_obj.name
            ])
            # Check if the damageable child is still in the tree before applying damage
            if damageable_found.is_inside_tree():
                if DamageManager and DamageManager.has_method("apply_damage_to_object"):
                    DamageManager.apply_damage_to_object(damageable_found, dmg, "bullet")
                    return
                damageable_found.call("apply_damage", dmg)
                return
        elif "Tree" in node_obj.name:
            print("⚠️ NO DAMAGE METHOD: Tree '%s' has no apply_damage method in parent chain or children!" % node_obj.name)

## Get descriptive name for objects hit by weapons
func _get_descriptive_object_name(obj: Object) -> String:
    if obj == null:
        return "null"
    
    if not obj is Node:
        return str(obj) if obj else "unknown"
    
    var node = obj as Node
    
    # PRIORITY 1: Check for metadata first (most reliable)
    if node.has_meta("building_type"):
        var building_type = node.get_meta("building_type")
        if building_type and building_type != "":
            print("DEBUG: Found building type from metadata: ", building_type)
            return "Building (%s)" % str(building_type).capitalize()
    
    # PRIORITY 2: Check for unnamed StaticBody3D (the @StaticBody3D@ID case)
    var name = node.name
    if name.begins_with("@StaticBody3D@"):
        print("DEBUG: Found unnamed StaticBody3D, searching children/parents for name...")
        # Try to find descriptive name from children or parent
        var child_name = _find_descriptive_name_in_children(node)
        if child_name != "":
            print("DEBUG: Found descriptive name in children: ", child_name)
            return child_name
        
        var parent_name = _find_descriptive_name_in_parent(node)
        if parent_name != "":
            print("DEBUG: Found descriptive name in parent: ", parent_name)
            return parent_name
        
        print("DEBUG: No descriptive name found, returning UnknownBuilding")
        return "UnknownBuilding"
    
    # Parse name to extract readable information
    if name.begins_with("DestructibleTree_"):
        # Extract species from names like "DestructibleTree_Pine_123_456"
        var parts = name.split("_")
        if parts.size() >= 3:
            var species = parts[1]
            return "Tree (%s)" % species
        return "Tree"
    
    elif name.begins_with("BuildingWithCollision_"):
        # Extract readable name from "BuildingWithCollision_BlacksmithShop"
        var readable_name = name.substr(20)  # Remove "BuildingWithCollision_" prefix
        return "Building (%s)" % readable_name.replace("Building", "")
    
    elif name.begins_with("SpecialGeometry_"):
        # Extract readable name from "SpecialGeometry_windmill_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("SpecialBuilding_"):
        # Extract readable name from "SpecialBuilding_windmill_0"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("ParametricBuilding_"):
        # Extract readable name from "ParametricBuilding_stone_cottage_ww2_european_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("AdaptiveParametric_"):
        # Extract readable name from "AdaptiveParametric_stone_cottage_ww2_european_0"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("TemplateBuilding_"):
        # Extract readable name from "TemplateBuilding_cottage_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("EnhancedTemplate_"):
        # Extract readable name from "EnhancedTemplate_cottage_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("ProceduralBuilding_"):
        # Extract readable name from "ProceduralBuilding_variantName_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("ProceduralVariant_"):
        # Extract readable name from "ProceduralVariant_barn_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("ExternalMesh_"):
        # Extract readable name from "ExternalMesh_stone_cottage_123"
        var parts = name.split("_")
        if parts.size() >= 2:
            var building_type = parts[1]
            return "Building (%s)" % building_type.capitalize()
        return "Building"
    
    elif name.begins_with("SimpleBuilding_"):
        return "Building"
    
    elif name.contains("Chunk"):
        return "Terrain"
    
    elif name.contains("ground") or name.contains("terrain"):
        return "Ground"
    
    # Return the original name if no special pattern matches
    return name

## Helper function to find descriptive name in children nodes
func _find_descriptive_name_in_children(node: Node) -> String:
    print("DEBUG: Searching ", node.get_child_count(), " children of node: ", node.name)
    
    for child in node.get_children():
        print("DEBUG: Checking child: ", child.name)
        
        # PRIORITY 1: Check metadata first
        if child.has_meta("building_type"):
            var building_type = child.get_meta("building_type")
            if building_type and building_type != "":
                print("DEBUG: Found building type from child metadata: ", building_type)
                return "Building (%s)" % str(building_type).capitalize()
        
        # PRIORITY 2: Check name patterns
        if child.name.begins_with("BuildingWithCollision_"):
            var readable_name = child.name.substr(20)
            return "Building (%s)" % readable_name.replace("Building", "")
        elif child.name.begins_with("SpecialGeometry_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("SpecialBuilding_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("ParametricBuilding_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("AdaptiveParametric_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("TemplateBuilding_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("EnhancedTemplate_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("ProceduralBuilding_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("ProceduralVariant_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("ExternalMesh_"):
            var parts = child.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif child.name.begins_with("SimpleBuilding_"):
            return "Building"
        elif child.name.begins_with("DestructibleTree_"):
            var parts = child.name.split("_")
            if parts.size() >= 3:
                var species = parts[1]
                return "Tree (%s)" % species
            return "Tree"
    
    print("DEBUG: No descriptive name found in children")
    return ""

## Helper function to find descriptive name in parent nodes
func _find_descriptive_name_in_parent(node: Node) -> String:
    var parent = node.get_parent()
    if parent:
        print("DEBUG: Checking parent: ", parent.name)
        
        # PRIORITY 1: Check metadata first
        if parent.has_meta("building_type"):
            var building_type = parent.get_meta("building_type")
            if building_type and building_type != "":
                print("DEBUG: Found building type from parent metadata: ", building_type)
                return "Building (%s)" % str(building_type).capitalize()
        
        # PRIORITY 2: Check name patterns
        if parent.name.begins_with("BuildingWithCollision_"):
            var readable_name = parent.name.substr(20)
            return "Building (%s)" % readable_name.replace("Building", "")
        elif parent.name.begins_with("SpecialGeometry_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("SpecialBuilding_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("ParametricBuilding_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("AdaptiveParametric_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("TemplateBuilding_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("EnhancedTemplate_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("ProceduralBuilding_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("ProceduralVariant_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("ExternalMesh_"):
            var parts = parent.name.split("_")
            if parts.size() >= 2:
                var building_type = parts[1]
                return "Building (%s)" % building_type.capitalize()
            return "Building"
        elif parent.name.begins_with("SimpleBuilding_"):
            return "Building"
    
    print("DEBUG: No parent or no descriptive name found in parent")
    return ""

# Helper function to find a damageable component in children
func _find_damageable_in_children(node: Node) -> Node:
    # Check direct children first
    for child in node.get_children():
        if child.has_method("apply_damage") and child.is_inside_tree():
            return child
        # Recursively check grandchildren (only if child is in tree)
        if child.is_inside_tree():
            var grandchild_result = _find_damageable_in_children(child)
            if grandchild_result:
                return grandchild_result
    return null

func _spawn_tracer(a: Vector3, b: Vector3, is_player: bool) -> void:
    if tracer_scene:
        var t = tracer_scene.instantiate()
        var root = get_tree().root
        if root:
            root.add_child(t)
            t.add_to_group("tracers")
            if t.has_method("setup"):
                t.setup(a, b, tracer_life)
            if t.has_method("set_color"):
                var c: Color = Color(1.0, 0.78, 0.25, 1.0) if is_player else Color(1.0, 0.42, 0.12, 1.0)
                t.set_color(c)
            if t.has_method("set_width"):
                # Player tracers: 5.0 (default), Enemy tracers: 2.0 (smaller for less obstruction)
                var width: float = 5.0 if is_player else 0.1
                t.set_width(width)

func _spawn_muzzle_flash(muzzle_node: Variant, dir: Vector3 = Vector3.ZERO, scale_mul: float = 1.0) -> void:
    # Accept either a muzzle Node3D or a world-space Vector3 position.
    if not is_inside_tree():
        return
    var root := get_tree().root
    if root == null:
        return

    # Create a more dynamic muzzle flash using particles for better arcade feel
    var flash_particles := GPUParticles3D.new()
    flash_particles.name = "MuzzleFlash"
    flash_particles.add_to_group("muzzle_flashes")
    root.add_child(flash_particles)

    # Configure particle system
    flash_particles.emitting = true
    flash_particles.amount = 8  # Further reduced to prevent GPU freeze in intense dogfights
    flash_particles.lifetime = 0.3  # Further reduced for faster cleanup
    flash_particles.one_shot = true
    flash_particles.speed_scale = 6.0  # Reduced from 8.0 for GPU performance
    flash_particles.explosiveness = 0.8  # More spread
    flash_particles.randomness = 0.95  # More randomness

    # Particle material
    var mat := ParticleProcessMaterial.new()
    mat.direction = Vector3(0, 0, 1)  # Forward direction
    mat.initial_velocity_min = 800.0  # Much faster particles
    mat.initial_velocity_max = 1500.0  # Much faster particles
    mat.angular_velocity_min = -3000.0
    mat.angular_velocity_max = 3000.0
    mat.scale_min = 2.0  # Much larger particles
    mat.scale_max = 5.0  # Much larger particles
    mat.flatness = 0.8  # Make particles more billboard-like

    # Color ramp for fiery effect
    var color_ramp := Gradient.new()
    color_ramp.add_point(0.0, Color(1.0, 1.0, 0.9, 1.0))  # Bright yellow-white
    color_ramp.add_point(0.2, Color(1.0, 0.9, 0.5, 0.95))  # Yellow-orange
    color_ramp.add_point(0.5, Color(1.0, 0.6, 0.2, 0.9))  # Orange-red
    color_ramp.add_point(0.8, Color(1.0, 0.3, 0.1, 0.7))  # Red-orange
    color_ramp.add_point(1.0, Color(0.9, 0.15, 0.1, 0.0))  # Fade to transparent red

    var color_ramp_tex := GradientTexture1D.new()
    color_ramp_tex.gradient = color_ramp
    mat.color_ramp = color_ramp_tex

    # Make particles more emissive/bright
    mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
    mat.emission_point_count = 1

    # Ensure particles are bright and visible
#    mat.emission_enabled = true
#    mat.emission_intensity = 10.0  # Very bright muzzle flash

    flash_particles.process_material = mat

    # Position and orient the particle system
    if muzzle_node is Node3D:
        var n: Node3D = muzzle_node
        if not is_instance_valid(n) or not n.is_inside_tree():
            flash_particles.queue_free()
            return
        flash_particles.global_transform = n.global_transform
    elif muzzle_node is Vector3:
        flash_particles.global_position = muzzle_node
        # Orient along dir if provided
        if dir.length() > 0.001:
            var fwd := dir.normalized()
            var up := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
            var right := up.cross(fwd).normalized()
            up = fwd.cross(right).normalized()
            flash_particles.global_basis = Basis(right, up, fwd)
    else:
        flash_particles.queue_free()
        return

    # Scale the flash
    flash_particles.scale = Vector3.ONE * (scale_mul * 12.0)  # Much larger scale for more impact

    # Auto-cleanup after lifetime using CONNECT_ONE_SHOT to prevent memory leaks
    get_tree().create_timer(flash_particles.lifetime * 1.2).timeout.connect(
        func():
            if is_instance_valid(flash_particles):
                flash_particles.queue_free()
    , CONNECT_ONE_SHOT)

func _spawn_impact_spark(pos: Vector3) -> void:
    # Budget check now handled in fire() method - no redundant check needed here
    # Big, impressive "spark pop" at impact. Uses the existing explosion effect at high intensity.
    var e := ExplosionScript.new()
    var root = get_tree().root
    if root:
        e.add_to_group("impact_sparks")
        root.add_child(e)
        e.global_position = pos
        e.radius = 50.0  # MASSIVE radius for arcade visibility
        e.intensity = 0.5  # Further reduced to 50 particles per impact (was 100)
        e.life = 1.0  # Reduced from 3.0 for faster cleanup

func _apply_spread(dir: Vector3, spread_rad: float) -> Vector3:
    if spread_rad <= 0.0:
        return dir
    # Random small rotation around a random axis.
    var axis = dir.cross(Vector3.UP)
    if axis.length() < 0.001:
        axis = dir.cross(Vector3.RIGHT)
    axis = axis.normalized()
    var a = randf_range(-spread_rad, spread_rad)
    return dir.rotated(axis, a).normalized()

func _apply(d: Dictionary) -> void:
    damage = d.get("damage", damage)
    range = d.get("range", range)
    cooldown = d.get("cooldown", cooldown)
    heat_per_shot = d.get("heat_per_shot", heat_per_shot)
    spread_deg = d.get("spread_deg", spread_deg)
    tracer_life = d.get("tracer_life", tracer_life)

## Create bullet hit effects based on material type
func _create_bullet_hit_effects(pos: Vector3, hit_object) -> void:
    if not hit_object:
        return

    # Budget check now handled in fire() method - no redundant check needed here
    var material_type = _determine_material_type(hit_object)

    # Spawn appropriate particle effect based on material (using preloaded scenes for performance)
    var effect_scene = null
    match material_type:
        "metal":
            effect_scene = FX_SPARKS
        "wood":
            effect_scene = FX_WOOD_DEBRIS
        "stone":
            effect_scene = FX_DUST
        "natural":
            effect_scene = FX_LEAVES

    if effect_scene:
        var effect_instance = effect_scene.instantiate()

        var root = get_tree().root
        if root:
            effect_instance.add_to_group("bullet_hit_effects")
            root.add_child(effect_instance)
            effect_instance.global_position = pos

            # Auto-cleanup based on effect's actual lifetime
            var cleanup_time = 3.0  # Default fallback
            if effect_instance.has_method("get_lifetime"):
                cleanup_time = effect_instance.get_lifetime() + 0.5  # Add buffer for particle fadeout
            get_tree().create_timer(cleanup_time).timeout.connect(
                func():
                    if is_instance_valid(effect_instance):
                        effect_instance.queue_free()
            , CONNECT_ONE_SHOT)

## Play appropriate hit sound based on what was hit
func _play_hit_sound(collider: Object) -> void:
    var sound_to_play: AudioStream = null

    # Determine if this is terrain or non-damageable
    if _is_terrain(collider):
        sound_to_play = SND_TERRAIN_HIT
    elif not _is_damageable(collider):
        sound_to_play = SND_NON_DAMAGEABLE_HIT

    # Play the sound if we have one
    if sound_to_play:
        var audio_player = AudioStreamPlayer3D.new()
        audio_player.stream = sound_to_play
        audio_player.volume_db = 0.0
        audio_player.max_distance = 500.0
        audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
        audio_player.max_polyphony = 16  # Allow up to 16 simultaneous impact sounds

        var root = get_tree().root
        if root:
            root.add_child(audio_player)
            if collider and collider is Node3D and (collider as Node3D).is_inside_tree():
                audio_player.global_position = (collider as Node3D).global_position
            audio_player.play()

            # Auto-cleanup after sound finishes using CONNECT_ONE_SHOT to prevent memory leaks
            audio_player.finished.connect(func():
                if is_instance_valid(audio_player):
                    audio_player.queue_free()
            , CONNECT_ONE_SHOT)

## Check if the collider is terrain
func _is_terrain(obj: Object) -> bool:
    if not obj or not obj is Node:
        return false

    var node := obj as Node
    var name := node.name

    # Check for terrain-related names
    if name.contains("Chunk") or name.contains("ground") or name.contains("terrain") or name.to_lower().contains("terrain"):
        return true

    return false

## Check if the collider is damageable
func _is_damageable(obj: Object) -> bool:
    if not obj:
        return false

    # Check if this object or any parent has apply_damage method
    var n := obj as Node
    while n:
        if n.has_method("apply_damage"):
            return true
        n = n.get_parent()

    # Check children for damageable components
    if obj is Node:
        if _find_damageable_in_children(obj as Node):
            return true

    return false

## Spawn smoke trail at hit location for extra drama
func _spawn_smoke_trail(pos: Vector3) -> void:
    if SmokeScene:
        var smoke = SmokeScene.instantiate()
        var root = get_tree().root
        if root:
            root.add_child(smoke)
            smoke.global_position = pos
            # Auto-cleanup using CONNECT_ONE_SHOT to prevent memory leaks
            # Reduced from 6.0 to 2.5s for faster cleanup
            get_tree().create_timer(2.5).timeout.connect(
                func():
                    if is_instance_valid(smoke):
                        smoke.queue_free()
            , CONNECT_ONE_SHOT)

## Determine material type from hit object
func _determine_material_type(obj) -> String:
    if not obj:
        return "metal"

    # Check if it's terrain (collision name contains "Terrain")
    if obj is Node and ("Terrain" in obj.name or "terrain" in obj.name):
        return "stone"  # Terrain should spawn dust effects

    # Walk up parent chain to find a node with object_set
    var n := obj as Node
    while n:
        if n.has_method("get_object_set"):
            var obj_set = n.call("get_object_set")
            match obj_set:
                "Industrial":
                    return "metal"
                "Residential":
                    return "wood"
                "Natural":
                    return "natural"

        # Fallback: Check node name for tree patterns
        # This catches destructible trees that may not have get_object_set()
        var name_lower = n.name.to_lower()
        if "tree" in name_lower or "pine" in name_lower or "oak" in name_lower or \
           "birch" in name_lower or "maple" in name_lower or "spruce" in name_lower or \
           "fir" in name_lower or "cedar" in name_lower or "ash" in name_lower or \
           "palm" in name_lower or "conifer" in name_lower or "broadleaf" in name_lower:
            return "natural"  # Treat any tree as natural material

        n = n.get_parent()

    # Default to metal for unknown objects
    return "metal"

## Play gunshot sound when firing
func _play_shot_sound() -> void:
    var audio_player = AudioStreamPlayer3D.new()
    audio_player.stream = SND_SHOT
    audio_player.volume_db = -5.0  # Slightly quieter than impact sounds
    audio_player.max_distance = 300.0
    audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    audio_player.max_polyphony = 8  # Allow up to 8 simultaneous shot sounds

    var root = get_tree().root
    if root:
        root.add_child(audio_player)
        audio_player.global_position = global_position
        audio_player.play()

        # Auto-cleanup after sound finishes using CONNECT_ONE_SHOT to prevent memory leaks
        audio_player.finished.connect(func():
            if is_instance_valid(audio_player):
                audio_player.queue_free()
        , CONNECT_ONE_SHOT)

## Check if spawning a new particle effect would exceed budget
## Returns true if within budget, false if over budget
func _check_particle_budget(group_name: String, max_count: int) -> bool:
    if not Game.settings.get("enable_particle_budget", true):
        return true  # Budget system disabled

    var active = get_tree().get_nodes_in_group(group_name)
    if active.size() >= max_count:
        # Over budget - enforce cleanup based on priority
        var priority = Game.settings.get("particle_budget_priority", "newest")
        if priority == "oldest":
            # Keep newest, remove oldest
            if active.size() > 0 and is_instance_valid(active[0]):
                active[0].queue_free()
            return true
        else:
            # Keep oldest, skip newest (default)
            return false

    return true  # Within budget
