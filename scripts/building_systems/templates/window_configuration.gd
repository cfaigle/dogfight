@tool
class_name WindowConfiguration
extends Resource

@export var window_style: String = "double_hung"  # "double_hung", "casement", "bay", "punched"
@export var window_count: int = 4
@export var window_size: Vector2 = Vector2(0.8, 1.2)
@export var window_material: String = "wood_frame"
@export var window_distribution: String = "symmetric"  # "symmetric", "random", "clustered"
@export var has_window_sills: bool = true
@export var window_sill_depth: float = 0.1