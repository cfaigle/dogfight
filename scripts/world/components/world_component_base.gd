class_name WorldComponentBase
extends RefCounted

## Base class for all world generation components
## Components generate specific world features (terrain, water, vegetation, infrastructure)
## Designed for modularity and extensibility

## Shared world context (set by WorldBuilder before generate()).
var ctx: WorldContext = null

func set_context(c: WorldContext) -> void:
    ctx = c

## Generate world feature
## @param world_root: Node3D to add generated content to
## @param params: Dictionary of generation parameters
## @param rng: RandomNumberGenerator for deterministic randomness
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    push_error("WorldComponentBase.generate() must be overridden")

## Get list of required parameter names
func get_required_params() -> Array[String]:
    return []

## Get dictionary of optional parameters with defaults
func get_optional_params() -> Dictionary:
    return {}

## Validate parameters before generation
func validate_params(params: Dictionary) -> bool:
    # Check required params
    for param_name in get_required_params():
        if not params.has(param_name):
            push_error("Missing required parameter: %s" % param_name)
            return false

    # Add optional params with defaults
    var optional = get_optional_params()
    for param_name in optional:
        if not params.has(param_name):
            params[param_name] = optional[param_name]

    return true

## Called before generation starts (for initialization)
func initialize(world_params: Dictionary) -> void:
    pass

## Called after generation completes (for cleanup)
func cleanup() -> void:
    pass

## Get dependencies - other components this depends on
## Returns array of component names that must generate before this one
func get_dependencies() -> Array[String]:
    return []

## Get component priority (lower = generates earlier)
## Terrain = 0, Water = 10, Vegetation = 20, Infrastructure = 30, etc.
func get_priority() -> int:
    return 100
