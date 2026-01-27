class_name BuildingDefinition
extends Resource

## Resource defining a collection of building variants for a specific type
## Extensible: other AIs can create new .tres files to add building types

@export var building_type: String = "residential"  # "residential", "commercial", "industrial", etc.
@export var style: String = "ww2_european"  # Style this definition is designed for
@export var variants: Array[Resource] = []  # Array of BuildingVariant resources
@export var default_materials: Dictionary = {}  # Optional material overrides
@export var component_overrides: Dictionary = {}  # Optional component-specific settings

## Get a random variant based on probability weights
func get_random_variant() -> BuildingVariant:
    if variants.is_empty():
        push_error("No variants defined in building definition: " + building_type)
        return null

    # Calculate total weight
    var total_weight = 0.0
    for variant_res in variants:
        var variant = variant_res as BuildingVariant
        if variant:
            total_weight += variant.probability_weight

    # Random selection based on weight
    var roll = randf() * total_weight
    var cumulative = 0.0

    for variant_res in variants:
        var variant = variant_res as BuildingVariant
        if variant:
            cumulative += variant.probability_weight
            if roll <= cumulative:
                return variant

    # Fallback to first variant
    return variants[0] as BuildingVariant

## Get a specific variant by name
func get_variant_by_name(variant_name: String) -> BuildingVariant:
    for variant_res in variants:
        var variant = variant_res as BuildingVariant
        if variant and variant.name == variant_name:
            return variant
    return null

## Get all variant names
func get_variant_names() -> Array[String]:
    var names: Array[String] = []
    for variant_res in variants:
        var variant = variant_res as BuildingVariant
        if variant:
            names.append(variant.name)
    return names
