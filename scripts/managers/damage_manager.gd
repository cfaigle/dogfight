## Damage Manager Singleton
## Manages all damage application and destruction logic for configurable object sets

extends Node

## The current configuration for object sets
var object_sets_config: ObjectSetsConfig

## Dictionary to track all damageable objects in the game
var damageable_objects: Dictionary = {}

## Signal emitted when an object takes damage
signal object_damaged(object, damage_amount, remaining_health)

## Signal emitted when an object is destroyed
signal object_destroyed(object)

## Signal emitted when an object's destruction stage changes
signal destruction_stage_changed(object, old_stage, new_stage)

func _ready() -> void:
	## Load the default object sets configuration
	object_sets_config = load("res://resources/configs/object_sets_config.tres")
	if not object_sets_config:
		# Create a default configuration if none exists
		object_sets_config = ObjectSetsConfig.new()
		_create_default_sets()
	
	# Register this as an Engine singleton (for code paths that use Engine.* APIs)
	# NOTE: Engine.get_singleton("DamageManager") logs an error if it doesn't exist,
	# so use has_singleton() to avoid noisy startup logs.
	if not Engine.has_singleton("DamageManager"):
		Engine.register_singleton("DamageManager", self)

func _create_default_sets() -> void:
	## Create default object sets for testing
	var default_sets = {
		"Industrial": {
			"health_range": {"min": 150.0, "max": 300.0},
			"destruction_stages": [
				{"threshold": 1.0, "effect": "intact"},
				{"threshold": 0.66, "effect": "lightly_damaged"},
				{"threshold": 0.33, "effect": "heavily_damaged"},
				{"threshold": 0.0, "effect": "destroyed"}
			],
			"geometry_changes": {
				"remove_parts": true,
				"add_holes": true,
				"collapse_sections": true,
				"break_into_pieces": true
			},
			"visual_effects": {
				"particle_effects": ["smoke", "sparks", "debris"],
				"material_changes": ["darken", "crack_texture"],
				"animation_triggers": ["shake"]
			},
			"audio_effects": {
				"damage_sounds": ["metal_impact"],
				"destruction_sounds": ["explosion"]
			},
			"physics_properties": {
				"debris_enabled": true,
				"debris_count_range": {"min": 3, "max": 8},
				"debris_size_range": {"min": 0.5, "max": 3.0}
			}
		},
		"Residential": {
			"health_range": {"min": 80.0, "max": 150.0},
			"destruction_stages": [
				{"threshold": 1.0, "effect": "intact"},
				{"threshold": 0.66, "effect": "lightly_damaged"},
				{"threshold": 0.33, "effect": "heavily_damaged"},
				{"threshold": 0.0, "effect": "ruined"}
			],
			"geometry_changes": {
				"remove_parts": true,
				"add_holes": false,
				"collapse_sections": false,
				"break_into_pieces": false
			},
			"visual_effects": {
				"particle_effects": ["dust", "wood_debris"],
				"material_changes": ["crack_texture"],
				"animation_triggers": ["slight_shake"]
			},
			"audio_effects": {
				"damage_sounds": ["wood_crack"],
				"destruction_sounds": ["structure_collapse"]
			},
			"physics_properties": {
				"debris_enabled": true,
				"debris_count_range": {"min": 1, "max": 4},
				"debris_size_range": {"min": 0.3, "max": 1.5}
			}
		},
		"Natural": {
			"health_range": {"min": 40.0, "max": 100.0},
			"destruction_stages": [
				{"threshold": 1.0, "effect": "intact"},
				{"threshold": 0.5, "effect": "damaged"},
				{"threshold": 0.0, "effect": "destroyed"}
			],
			"geometry_changes": {
				"remove_parts": false,
				"add_holes": false,
				"collapse_sections": false,
				"break_into_pieces": true
			},
			"visual_effects": {
				"particle_effects": ["leaves", "bark_debris"],
				"material_changes": ["change_color"],
				"animation_triggers": ["fall_animation"]
			},
			"audio_effects": {
				"damage_sounds": ["tree_crack"],
				"destruction_sounds": ["tree_fall"]
			},
			"physics_properties": {
				"debris_enabled": true,
				"debris_count_range": {"min": 2, "max": 6},
				"debris_size_range": {"min": 0.2, "max": 1.0}
			}
		}
	}
	
	for set_name in default_sets:
		object_sets_config.add_set(set_name, default_sets[set_name])

## Register a damageable object with the manager
func register_damageable_object(object, object_set: String = "Default") -> void:
	if not object.has_method("get_health") or not object.has_method("apply_damage"):
		push_error("Object does not implement DamageableObject interface")
		return
	
	damageable_objects[object.get_instance_id()] = {
		"object": object,
		"object_set": object_set,
		"initial_health": object.get_health(),
		"current_stage": 0
	}

## Unregister a damageable object from the manager
func unregister_damageable_object(object) -> void:
	damageable_objects.erase(object.get_instance_id())

## Apply damage to an object using the configured rules for its set
func apply_damage_to_object(object, damage_amount: float, weapon_type: String = "default") -> void:
	var object_id = object.get_instance_id()
	if not damageable_objects.has(object_id):
		print("Warning: Object not registered with DamageManager")
		return
	
	var obj_data = damageable_objects[object_id]
	var current_health = object.get_health()
	var max_health = object.get_max_health()
	
	# Apply damage multiplier based on weapon type and object set
	var effective_damage = _calculate_effective_damage(damage_amount, obj_data.object_set, weapon_type)
	
	# Apply the damage
	var new_health = max(current_health - effective_damage, 0.0)
	object.set_health(new_health)
	
	# Emit signal for damage taken
	object_damaged.emit(object, effective_damage, new_health)
	
	# Check if object is destroyed
	if new_health <= 0:
		_handle_object_destruction(object, obj_data)
	else:
		# Check if destruction stage changed
		_update_destruction_stage(object, obj_data)

## Calculate effective damage based on weapon type and object set
func _calculate_effective_damage(base_damage: float, object_set: String, weapon_type: String) -> float:
	# For now, return base damage - in a full implementation, this would
	# apply multipliers based on weapon type and object set
	return base_damage

## Handle object destruction
func _handle_object_destruction(object, obj_data) -> void:
	# Apply destruction effects based on object set
	_apply_destruction_effects(object, obj_data.object_set)
	
	# Emit destruction signal
	object_destroyed.emit(object)
	
	# Remove from tracking
	damageable_objects.erase(object.get_instance_id())

## Apply destruction effects based on object set
func _apply_destruction_effects(object, object_set: String) -> void:
	var config = object_sets_config.get_set_config(object_set)
	
	# Apply visual effects
	_apply_visual_effects(object, config.get("visual_effects", {}))
	
	# Apply audio effects
	_apply_audio_effects(object, config.get("audio_effects", {}))
	
	# Apply physics changes
	_apply_physics_changes(object, config.get("physics_properties", {}))
	
	# Apply geometry changes
	_apply_geometry_changes(object, config.get("geometry_changes", {}))

## Apply visual effects to an object
func _apply_visual_effects(object, effects_config: Dictionary) -> void:
	# This would apply particle effects, material changes, etc.
	# Implementation depends on the specific object type
	pass

## Apply audio effects to an object
func _apply_audio_effects(object, effects_config: Dictionary) -> void:
	# This would play sounds based on the damage/destruction
	# Implementation depends on the specific object type
	pass

## Apply physics changes to an object
func _apply_physics_changes(object, physics_config: Dictionary) -> void:
	# This would create debris, apply forces, etc.
	# Implementation depends on the specific object type
	pass

## Apply geometry changes to an object
func _apply_geometry_changes(object, geometry_config: Dictionary) -> void:
	# This would modify the object's mesh, remove parts, etc.
	# Implementation depends on the specific object type
	pass

## Update destruction stage based on current health
func _update_destruction_stage(object, obj_data) -> void:
	var current_health = object.get_health()
	var max_health = object.get_max_health()
	var current_ratio = current_health / max_health if max_health > 0 else 0
	
	var stages = object_sets_config.get_destruction_stages(obj_data.object_set)
	var new_stage = 0
	
	for i in range(stages.size()):
		var stage = stages[i]
		if current_ratio <= stage.threshold:
			new_stage = i
	
	if new_stage != obj_data.current_stage:
		var old_stage = obj_data.current_stage
		obj_data.current_stage = new_stage
		
		# Apply stage-specific effects
		_apply_stage_effects(object, obj_data.object_set, new_stage)
		
		# Emit stage change signal
		destruction_stage_changed.emit(object, old_stage, new_stage)

## Apply effects for a specific destruction stage
func _apply_stage_effects(object, object_set: String, stage_index: int) -> void:
	var stages = object_sets_config.get_destruction_stages(object_set)
	if stage_index < stages.size():
		var stage = stages[stage_index]
		# Apply effects based on the stage
		# This could include visual changes, audio cues, etc.
		pass

## Get the current destruction stage for an object
func get_destruction_stage(object) -> int:
	var object_id = object.get_instance_id()
	if damageable_objects.has(object_id):
		return damageable_objects[object_id].current_stage
	return 0

## Get the object set for an object
func get_object_set(object) -> String:
	var object_id = object.get_instance_id()
	if damageable_objects.has(object_id):
		return damageable_objects[object_id].object_set
	return "Default"

## Change the object set for an object
func set_object_set(object, new_set: String) -> void:
	var object_id = object.get_instance_id()
	if damageable_objects.has(object_id):
		damageable_objects[object_id].object_set = new_set
		object.set_object_set(new_set)

## Get configuration for an object set
func get_set_config(set_name: String) -> Dictionary:
	return object_sets_config.get_set_config(set_name)

## Update the object sets configuration
func update_config(new_config: ObjectSetsConfig) -> void:
	object_sets_config = new_config