class_name BuildingVariant
extends Resource

## Resource defining a specific building variant with all its parameters
## Used to create consistent, reusable building configurations

@export var name: String = "Unnamed Variant"
@export var footprint_type: String = "rect"  # "rect", "L", "T", "U"
@export var dimensions: Vector3 = Vector3(10.0, 8.0, 12.0)  # width, depth, height
@export var floors: int = 2
@export var roof_type: String = "gable"  # "gable", "hip", "flat", "shed", etc.
@export var window_style: String = "square"  # "square", "arched", "bay", "divided"
@export var wall_profile: String = "historic"  # "modern", "historic", "industrial"
@export var detail_level: int = 1  # 0=minimal, 1=normal, 2=ornate
@export var probability_weight: float = 1.0  # Higher = more likely to be chosen

## Optional style overrides
@export var color_override: Color = Color.WHITE  # If not white, overrides default color
@export var add_shutters: bool = false
@export var add_window_boxes: bool = false
@export var add_dormers: bool = false
@export var add_cupola: bool = false

## Convert variant to parameter dictionary for building generation
func to_params() -> Dictionary:
    return {
        "name": name,
        "footprint_type": footprint_type,
        "width": dimensions.x,
        "depth": dimensions.y,
        "height": dimensions.z,
        "floors": floors,
        "roof_type": roof_type,
        "window_style": window_style,
        "wall_profile": wall_profile,
        "detail_level": detail_level,
        "color_override": color_override,
        "add_shutters": add_shutters,
        "add_window_boxes": add_window_boxes,
        "add_dormers": add_dormers,
        "add_cupola": add_cupola
    }
