class_name BuildingComponentBase
extends RefCounted

## Base class for all building components (walls, windows, roofs, etc.)
## Provides standard interface for component-based building generation.
##
## To create a new component:
## 1. Extend this class
## 2. Override generate() with your geometry logic
## 3. Override get_required_params() to specify required parameters
## 4. Override get_optional_params() to provide defaults
## 5. Register in component_registry.gd

## Generate geometry for this component
## @param st: SurfaceTool to add geometry to
## @param params: Dictionary of parameters (validated before call)
## @param materials: Dictionary of materials keyed by zone name
func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    push_error("BuildingComponentBase.generate() must be overridden")

## Get list of required parameter names
## @return Array of parameter name strings
func get_required_params() -> Array[String]:
    return []

## Get dictionary of optional parameters with default values
## @return Dictionary {param_name: default_value}
func get_optional_params() -> Dictionary:
    return {}

## Validate parameters before generation
## @param params: Parameters to validate
## @return true if valid, false otherwise
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

## Helper: Add a quad to surface tool with proper winding and normals
## @param st: SurfaceTool
## @param v0, v1, v2, v3: Vertices in counter-clockwise order when viewed from outside
## @param uv0, uv1, uv2, uv3: UV coordinates for each vertex
func add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
              uv0: Vector2 = Vector2.ZERO, uv1: Vector2 = Vector2.ZERO,
              uv2: Vector2 = Vector2.ZERO, uv3: Vector2 = Vector2.ZERO) -> void:
    # Calculate normal
    var edge1 = v1 - v0
    var edge2 = v3 - v0
    var normal = edge1.cross(edge2).normalized()

    # First triangle: v0, v1, v2
    st.set_normal(normal)
    st.set_uv(uv0)
    st.add_vertex(v0)

    st.set_normal(normal)
    st.set_uv(uv1)
    st.add_vertex(v1)

    st.set_normal(normal)
    st.set_uv(uv2)
    st.add_vertex(v2)

    # Second triangle: v0, v2, v3
    st.set_normal(normal)
    st.set_uv(uv0)
    st.add_vertex(v0)

    st.set_normal(normal)
    st.set_uv(uv2)
    st.add_vertex(v2)

    st.set_normal(normal)
    st.set_uv(uv3)
    st.add_vertex(v3)

## Helper: Calculate UV coordinates for a wall segment
## @param position: World position on wall
## @param wall_start: Start position of wall segment
## @param wall_end: End position of wall segment
## @param height: Total wall height
## @param texture_scale: Scale factor for texture tiling
func calculate_wall_uv(position: Vector3, wall_start: Vector3, wall_end: Vector3,
                       height: float, texture_scale: float = 1.0) -> Vector2:
    var wall_length = wall_start.distance_to(wall_end)
    var distance_along = wall_start.distance_to(Vector3(position.x, wall_start.y, position.z))

    var u = (distance_along / wall_length) * texture_scale
    var v = (position.y / height) * texture_scale

    return Vector2(u, v)
