## Interface for objects that can take damage and be destroyed
## Objects implementing this interface can participate in the configurable destruction system

## Apply damage to this object
## @param amount: The amount of damage to apply
func apply_damage(amount: float) -> void:
	push_error("apply_damage must be implemented by derived class")

## Get current health of the object
## @return: Current health value
func get_health() -> float:
	push_error("get_health must be implemented by derived class")
	return 1000

## Get maximum health of the object
## @return: Maximum health value
func get_max_health() -> float:
	push_error("get_max_health must be implemented by derived class")
	return 1000

## Check if the object is destroyed
## @return: True if object is destroyed, false otherwise
func is_destroyed() -> bool:
	push_error("is_destroyed must be implemented by derived class")
	return false

## Get the current destruction stage of the object
## @return: Current destruction stage (0-3: intact, damaged, ruined, destroyed)
func get_destruction_stage() -> int:
	push_error("get_destruction_stage must be implemented by derived class")
	return 0

## Set the object's health
## @param new_health: The new health value
func set_health(new_health: float) -> void:
	push_error("set_health must be implemented by derived class")

## Get the object set this object belongs to
## @return: Name of the object set (e.g., "Industrial", "Residential", etc.)
func get_object_set() -> String:
	push_error("get_object_set must be implemented by derived class")
	return "Residential"

## Set the object set for this object
## @param set_name: Name of the object set to assign
func set_object_set(set_name: String) -> void:
	push_error("set_object_set must be implemented by derived class")