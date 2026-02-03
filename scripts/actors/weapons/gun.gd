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

# Sound effects
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
	heat = max(heat - dt * 0.25, 0.0)

func can_fire() -> bool:
	return _t <= 0.0 and heat < 0.98

func fire(aim_dir: Vector3) -> void:
	if not can_fire():
		return
	
	# Debug collision system state
	if Engine.has_singleton("CollisionManager"):
		var cm = Engine.get_singleton("CollisionManager")
		print("COLLISION DEBUG: Active collision bodies before shot: ", cm.get_active_collision_count())

	_t = cooldown
	heat = min(heat + heat_per_shot, 1.0)

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

		# Start tracers farther in front of the plane
		var tracer_offset: float = 40.0  # Distance in front of muzzle
		var origin: Vector3 = muzzle_pos + dir * tracer_offset

		var to = origin + dir * range
		var query = PhysicsRayQueryParameters3D.create(origin, to)
		query.exclude = exclude_rids
		query.collision_mask = 1  # Match layer 1 where trees are placed
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		# Debug query setup
		# print("QUERY DEBUG: origin=", origin, " to=", to, " mask=", query.collision_mask)

		var space_state = PhysicsServer3D.space_get_direct_state(space)
		# print("DEBUG: space type: ", space_state.get_class(), " has intersect_ray: ", space_state.has_method("intersect_ray"))
		
		var hit = space_state.intersect_ray(query)
		
		# Debug hit result
		if hit:
			print("HIT DEBUG: hit result=", hit, " is_empty=", hit.is_empty())
		else:
			print("HIT DEBUG: hit result is null")

		var hit_pos = to
		var did_hit := false
		if hit and hit.size() > 0:  # Check if hit dictionary has any content
			if hit.has("position"):
				hit_pos = hit.position
				did_hit = true
				var collider = hit.collider
				print("COLLISION DEBUG: Raycast hit detected at: ", hit_pos, " collider: ", collider.name if collider else "null")
				_apply_damage_to_collider(collider, damage)
			else:
				print("COLLISION DEBUG: Raycast hit but no position - using endpoint: ", to)
		else:
			print("COLLISION DEBUG: Raycast hit nothing, using endpoint: ", to)

		_spawn_tracer(origin, hit_pos, is_player)
		_spawn_muzzle_flash((m as Node3D), dir, 0.8)

		if did_hit:
			_spawn_impact_spark(hit_pos)
			_create_bullet_hit_effects(hit_pos, hit.collider if hit else null)
			_spawn_smoke_trail(hit_pos)  # Add smoke for extra drama!
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

	var descriptive_name = _get_descriptive_object_name(obj)
	print("COLLISION DEBUG: Attempting to apply damage to: ", descriptive_name, " type: ", obj.get_class() if obj is Object else "unknown")

	# First, try walking up the parent chain to find a node with apply_damage
	var n := obj as Node
	while n:
		if n.has_method("apply_damage"):
			# Check if the node is still in the tree before applying damage
			if n.is_inside_tree():
				# Prefer DamageManager if present and compatible, otherwise call apply_damage directly.
				if Engine.has_singleton("DamageManager"):
					var dm := Engine.get_singleton("DamageManager")
					if dm and dm.has_method("apply_damage_to_object"):
						print("COLLISION DEBUG: Found apply_damage on: ", n.name, " - applying damage via DamageManager")
						dm.call("apply_damage_to_object", n, dmg, "bullet")
						return
				print("COLLISION DEBUG: Applied damage directly to: ", n.name)
				n.call("apply_damage", dmg)
				return
			else:
				print("COLLISION DEBUG: Node is no longer in tree, skipping damage application: ", n.name)
				return
		n = n.get_parent()

	# If no apply_damage method found in parent chain, check children for damageable components
	var node_obj := obj as Node
	if node_obj:
		var damageable_found = _find_damageable_in_children(node_obj)
		if damageable_found:
			# Check if the damageable child is still in the tree before applying damage
			if damageable_found.is_inside_tree():
				if Engine.has_singleton("DamageManager"):
					var dm := Engine.get_singleton("DamageManager")
					if dm and dm.has_method("apply_damage_to_object"):
						print("COLLISION DEBUG: Found damageable child: ", damageable_found.name, " - applying damage via DamageManager")
						dm.call("apply_damage_to_object", damageable_found, dmg, "bullet")
						return
				print("COLLISION DEBUG: Applied damage directly to child: ", damageable_found.name)
				damageable_found.call("apply_damage", dmg)
				return
			else:
				print("COLLISION DEBUG: Damageable child is no longer in tree, skipping damage application: ", damageable_found.name)
				return

	print("COLLISION DEBUG: No apply_damage method found in parent chain or children")
	print("DEBUG: No node with apply_damage method found in parent chain or children")

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
	flash_particles.amount = 150  # Much more particles for better visibility
	flash_particles.lifetime = 0.8  # Much longer lifetime for better visibility
	flash_particles.one_shot = true
	flash_particles.speed_scale = 8.0  # Much faster particles
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

	# Auto-cleanup after lifetime
	var t := get_tree().create_timer(flash_particles.lifetime * 2.0)
	t.timeout.connect(func():
		if is_instance_valid(flash_particles):
			flash_particles.queue_free()
	)

func _spawn_impact_spark(pos: Vector3) -> void:
	# Big, impressive "spark pop" at impact. Uses the existing explosion effect at high intensity.
	var e := ExplosionScript.new()
	var root = get_tree().root
	if root:
		e.add_to_group("impact_sparks")
		root.add_child(e)
		e.global_position = pos
		e.radius = 50.0  # MASSIVE radius for arcade visibility
		e.intensity = 8.0  # Very intense for big impact
		e.life = 3.0  # Longer duration so you can see it while flying past

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

	var material_type = _determine_material_type(hit_object)

	# Spawn appropriate particle effect based on material
	var effect_scene = null
	match material_type:
		"metal":
			effect_scene = load("res://effects/particle_sparks.tscn")
		"wood":
			effect_scene = load("res://effects/particle_wood_debris.tscn")
		"stone":
			effect_scene = load("res://effects/particle_dust.tscn")
		"natural":
			effect_scene = load("res://effects/particle_leaves.tscn")

	if effect_scene:
		var effect_instance = effect_scene.instantiate()

		var root = get_tree().root
		if root:
			root.add_child(effect_instance)
			effect_instance.global_position = pos

			# Auto-cleanup after 3 seconds
			get_tree().create_timer(3.0).timeout.connect(
				func():
					if is_instance_valid(effect_instance):
						effect_instance.queue_free()
			)

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
			if collider and collider is Node3D:
				audio_player.global_position = (collider as Node3D).global_position
			audio_player.play()

			# Auto-cleanup after sound finishes
			audio_player.finished.connect(func():
				if is_instance_valid(audio_player):
					audio_player.queue_free()
			)

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
	var smoke_scene = load("res://effects/particle_smoke.tscn")
	if smoke_scene:
		var smoke = smoke_scene.instantiate()
		var root = get_tree().root
		if root:
			root.add_child(smoke)
			smoke.global_position = pos
			# Auto-cleanup
			get_tree().create_timer(6.0).timeout.connect(
				func():
					if is_instance_valid(smoke):
						smoke.queue_free()
			)

## Determine material type from hit object
func _determine_material_type(obj) -> String:
	if not obj:
		return "metal"

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
		n = n.get_parent()

	# Default to metal for unknown objects
	return "metal"
