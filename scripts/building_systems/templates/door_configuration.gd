@tool
class_name DoorConfiguration
extends Resource

@export var door_style: String = "wooden"  # "wooden", "double", "arched", "modern"
@export var door_count: int = 1
@export var door_size: Vector2 = Vector2(0.9, 2.0)
@export var door_material: String = "oak"
@export var door_position: Vector2 = Vector2(0.0, 0.0)  # relative to front wall center
@export var has_door_frame: bool = true
@export var door_frame_width: float = 0.15