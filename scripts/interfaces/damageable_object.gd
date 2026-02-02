## Documentation: DamageableObject Interface
##
## This documents the expected interface for objects that can take damage and be destroyed.
## Objects implementing this interface can participate in the configurable destruction system.
##
## To implement this interface, extend BaseDamageableObject which provides the base implementation.
##
## Required Methods:
## ------------------
##
## apply_damage(amount: float) -> void
##   Apply damage to this object
##   @param amount: The amount of damage to apply
##
## get_health() -> float
##   Get current health of the object
##   @return: Current health value
##
## get_max_health() -> float
##   Get maximum health of the object
##   @return: Maximum health value
##
## is_destroyed() -> bool
##   Check if the object is destroyed
##   @return: True if object is destroyed, false otherwise
##
## get_destruction_stage() -> int
##   Get the current destruction stage of the object
##   @return: Current destruction stage (0-3: intact, damaged, ruined, destroyed)
##
## set_health(new_health: float) -> void
##   Set the object's health
##   @param new_health: The new health value
##
## get_object_set() -> String
##   Get the object set this object belongs to
##   @return: Name of the object set (e.g., "Industrial", "Residential", etc.)
##
## set_object_set(set_name: String) -> void
##   Set the object set for this object
##   @param set_name: Name of the object set to assign
##
## Note: GDScript uses duck typing, so formal interfaces aren't required.
## Simply implement these methods in your class or extend BaseDamageableObject.