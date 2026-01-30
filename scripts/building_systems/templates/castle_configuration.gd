@tool
class_name CastleConfiguration
extends Resource

@export var has_battlements: bool = true
@export var battlement_height: float = 2.0
@export var battlement_width: float = 0.5
@export var battlement_spacing: float = 2.0
@export var has_corner_towers: bool = true
@export var tower_height_multiplier: float = 1.3
@export var tower_diameter: float = 3.0
@export var has_main_gate: bool = true
@export var gate_width: float = 3.0
@export var gate_height: float = 4.0
@export var has_murder_holes: bool = false
@export var has_courtyard: bool = false
@export var castle_style: String = "keep"  # "keep", "fortress", "citadel"