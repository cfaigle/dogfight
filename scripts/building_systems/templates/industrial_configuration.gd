@tool
class_name IndustrialConfiguration
extends Resource

@export var has_smokestacks: bool = true
@export var smokestack_count: int = 2
@export var smokestack_height_multiplier: float = 1.5
@export var smokestack_width: float = 1.2
@export var has_industrial_windows: bool = true
@export var window_style: String = "industrial_punched"
@export var has_loading_docks: bool = false
@export var has_metal_siding: bool = true
@export var building_complexity: String = "simple"  # "simple", "complex", "multi_wing"