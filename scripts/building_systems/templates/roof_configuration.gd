@tool
class_name RoofConfiguration
extends Resource

@export var roof_type: String = "gabled"  # "gabled", "hipped", "thatched", "flat"
@export var roof_pitch: float = 40.0  # degrees
@export var roof_overhang: float = 0.3
@export var roof_material: String = "stone_tiles"
@export var roof_color: Color = Color(0.4, 0.3, 0.2)
@export var has_chimney: bool = true
@export var chimney_position: Vector2 = Vector2(0.3, 0.2)  # relative to building center