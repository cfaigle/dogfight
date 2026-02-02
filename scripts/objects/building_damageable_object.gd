## Building-specific damageable object
## Extends the base damageable object with building-specific functionality

class_name BuildingDamageableObject
extends BaseDamageableObject

## Building type (used to determine appropriate object set)
var building_type: String = "generic"

## Reference to the building's mesh
var building_mesh: MeshInstance3D = null

## Initialize the building damageable object
func _ready() -> void:
    # Find the building mesh in children
    building_mesh = _find_building_mesh()
    
    # Use the building_type set during creation, or fall back to name
    if building_type.is_empty():
        building_type = name.to_lower()
    
    # Assign appropriate object set based on building type
    var object_set = _determine_object_set(building_type)
    
    # Initialize with appropriate health based on set
    var health = _get_health_for_set(object_set)
    
    print("DEBUG: Initializing building damageable - type: ", building_type, " set: ", object_set, " health: ", health)
    initialize_damageable(health, object_set)

## Determine the object set based on building type
func _determine_object_set(building_type: String) -> String:
    # Map building types to appropriate object sets
    var type_to_set_map = {
        "factory": "Industrial",
        "warehouse": "Industrial", 
        "mill": "Industrial",
        "power_station": "Industrial",
        "foundry": "Industrial",
        "workshop": "Industrial",
        "industrial": "Industrial",
        "house": "Residential",
        "cottage": "Residential",
        "inn": "Residential",
        "tavern": "Residential",
        "pub": "Residential",
        "farmhouse": "Residential",
        "barn": "Residential",
        "stone_cottage": "Residential",
        "thatched_cottage": "Residential",
        "white_stucco_house": "Residential",
        "house_victorian": "Residential",
        "house_tudor": "Residential",
        "house_colonial": "Residential",
        "shop": "Residential",  # Small shops often residential style
        "windmill": "Residential",  # Often residential style
        "tree": "Natural",
        "pine": "Natural",
        "oak": "Natural",
        "birch": "Natural",
        "bush": "Natural",
        "rock": "Natural",
        "stone": "Natural"
    }
    
    if type_to_set_map.has(building_type):
        return type_to_set_map[building_type]
    
    # Default to residential if no specific mapping
    return "Residential"

## Get appropriate health for the object set
func _get_health_for_set(object_set: String) -> float:
    var set_config = {}
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        set_config = damage_manager.get_set_config(object_set)
    
    if set_config.has("health_range"):
        var health_range = set_config.health_range
        var min_health = health_range.get("min", 50.0)
        var max_health = health_range.get("max", 100.0)
        return randf_range(min_health, max_health)
    
    # Default health
    return 100.0

## Find the building mesh in the children
func _find_building_mesh() -> MeshInstance3D:
    for child in get_children():
        if child is MeshInstance3D:
            return child
        # Recursively search in children
        var result = _search_mesh_recursive(child)
        if result:
            return result
    return null

## Recursively search for mesh in children
func _search_mesh_recursive(node) -> MeshInstance3D:
    if node is MeshInstance3D:
        return node
    
    for child in node.get_children():
        if child is MeshInstance3D:
            return child
        var result = _search_mesh_recursive(child)
        if result:
            return result
    
    return null

## Apply damaged effects
func _apply_damaged_effects() -> void:
    if building_mesh:
        # Change material to show damage
        var material = building_mesh.material_override
        if not material:
            material = StandardMaterial3D.new()
            building_mesh.material_override = material
        
        # Darken the material slightly
        var current_color = material.albedo_color
        material.albedo_color = Color(current_color.r * 0.8, current_color.g * 0.8, current_color.b * 0.8, current_color.a)

## Apply ruined effects
func _apply_ruined_effects() -> void:
    if building_mesh:
        # More significant material changes
        var material = building_mesh.material_override
        if not material:
            material = StandardMaterial3D.new()
            building_mesh.material_override = material
        
        # Further darken and add damage indicators
        var current_color = material.albedo_color
        material.albedo_color = Color(current_color.r * 0.6, current_color.g * 0.6, current_color.b * 0.7, current_color.a)
        
        # Add emissive effect to simulate fires or damage
        material.emission_enabled = true
        material.emission = Color(0.8, 0.4, 0.1)  # Reddish orange for damage/fire
        material.emission_energy = 0.5

## Apply destroyed effects
func _apply_destroyed_effects() -> void:
    if building_mesh:
        # Significant material changes for destruction
        var material = building_mesh.material_override
        if not material:
            material = StandardMaterial3D.new()
            building_mesh.material_override = material
        
        # Make almost completely dark
        material.albedo_color = Color(0.2, 0.2, 0.2, material.albedo_color.a)
        
        # Increase emission for fire/smoke effect
        material.emission_enabled = true
        material.emission = Color(0.9, 0.5, 0.2)  # More intense fire color
        material.emission_energy = 1.0

## Called when the building is destroyed
func _on_destroyed() -> void:
    # Apply destruction effects
    _apply_destroyed_effects()
    
    # Notify DamageManager
    if Engine.has_singleton("DamageManager"):
        var damage_manager = Engine.get_singleton("DamageManager")
        damage_manager.object_destroyed.emit(self)
    
    # Emit local signal
    destroyed.emit()
    
    # In a full implementation, we would:
    # - Apply geometry changes (remove parts, add holes, break into pieces)
    # - Spawn debris
    # - Apply physics to parts
    # For now, we'll just fade out
    var tween = create_tween()
    tween.tween_method(func(val): 
        if building_mesh and building_mesh.material_override:
            var mat = building_mesh.material_override
            mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, val)
    , 1.0, 0.0, 2.0)
    
    # Queue for removal after effect completes
    await tween.finished
    queue_free()