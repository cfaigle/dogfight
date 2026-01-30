@tool
class_name WallConfiguration
extends Resource

@export var wall_thickness: float = 0.25
@export var wall_height: float = 4.0
@export var wall_material: String = "stone"
@export var wall_texture_scale: Vector2 = Vector2(1.0, 1.0)
@export var has_rustic_variation: bool = true
@export var rustic_offset_range: float = 0.1