class_name WorldComponentRegistry
extends RefCounted

## Registry for world generation components
## Manages component lifecycle and dependency resolution

var _components: Dictionary = {}
var _initialized: bool = false

## Register a component class
func register_component(component_name: String, component_class) -> void:
    if not component_class is GDScript:
        push_error("Component must be a GDScript class")
        return

    _components[component_name] = component_class
    print("Registered world component: %s" % component_name)

## Get a component instance by name
func get_component(component_name: String) -> WorldComponentBase:
    if not _components.has(component_name):
        push_error("Component not found: %s" % component_name)
        return null

    var component_class = _components[component_name]
    var instance = component_class.new()

    if not instance is WorldComponentBase:
        push_error("Component must extend WorldComponentBase: %s" % component_name)
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

## Get components in dependency order (topological sort)
func get_components_in_order() -> Array:
    var ordered = []
    var components_to_sort = []

    # Create component instances
    for name in _components.keys():
        var component = get_component(name)
        if component:
            components_to_sort.append({"name": name, "component": component})

    # Sort by priority first
    components_to_sort.sort_custom(func(a, b): return a["component"].get_priority() < b["component"].get_priority())

    # Simple dependency resolution (for now, just use priority)
    # TODO: Implement full topological sort with dependency checking
    for item in components_to_sort:
        ordered.append(item)

    return ordered
