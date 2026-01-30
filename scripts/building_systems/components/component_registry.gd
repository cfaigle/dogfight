class_name ComponentRegistry
extends RefCounted

## Registry for building components
## Automatically discovers and instantiates component classes

var _components: Dictionary = {}

func _init():
    _register_default_components()

## Register a component class
## @param component_name: Name to register under
## @param component_class: Class reference (must extend BuildingComponentBase)
func register_component(component_name: String, component_class) -> void:
    if not component_class is GDScript:
        push_error("Component must be a GDScript class")
        return

    _components[component_name] = component_class
#    print("Registered component: %s" % component_name)

## Get a component instance by name
## @param component_name: Name of component
## @return Component instance or null if not found
func get_component(component_name: String) -> BuildingComponentBase:
    if not _components.has(component_name):
        push_error("Component not found: %s" % component_name)
        return null

    var component_class = _components[component_name]
    var instance = component_class.new()

    if not instance is BuildingComponentBase:
        push_error("Component must extend BuildingComponentBase: %s" % component_name)
        return null

    return instance

## Check if a component is registered
func has_component(component_name: String) -> bool:
    return _components.has(component_name)

## Get list of all registered component names
func get_component_names() -> Array[String]:
    var names: Array[String] = []
    for name in _components.keys():
        names.append(name)
    return names

## Register default components
func _register_default_components() -> void:
    # Components will be registered here as they're created
    # For now, this is a placeholder for the component classes we'll create
    pass
