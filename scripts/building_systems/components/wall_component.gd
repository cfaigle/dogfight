class_name WallComponent
extends BuildingComponentBase

## Generates building walls with proper geometry and UV mapping
## Supports multi-floor buildings and various footprint shapes

func get_required_params() -> Array[String]:
    return ["footprint", "height", "floors"]

func get_optional_params() -> Dictionary:
    return {
        "floor_height": 3.0,
        "wall_thickness": 0.2,
        "texture_scale": 2.0,
        "create_interior": false
    }

func generate(st: SurfaceTool, params: Dictionary, materials: Dictionary) -> void:
    var footprint: PackedVector2Array = params["footprint"]
    var height: float = params["height"]
    var floors: int = params["floors"]
    var floor_height: float = params.get("floor_height", height / float(floors))
    var texture_scale: float = params["texture_scale"]
    var create_interior: bool = params["create_interior"]

    if footprint.size() < 3:
        push_error("Footprint must have at least 3 points")
        return

    # Generate exterior walls
    _generate_walls(st, footprint, height, floors, floor_height, texture_scale, false)

    # Optionally generate interior walls (for recessed windows)
    if create_interior:
        var interior_footprint = _shrink_footprint(footprint, params.get("wall_thickness", 0.2))
        _generate_walls(st, interior_footprint, height, floors, floor_height, texture_scale, true)

## Generate walls for a footprint
func _generate_walls(st: SurfaceTool, footprint: PackedVector2Array, height: float,
                     floors: int, floor_height: float, texture_scale: float,
                     flip_normals: bool) -> void:
    var point_count = footprint.size()

    for i in range(point_count):
        var p0 = footprint[i]
        var p1 = footprint[(i + 1) % point_count]

        # Calculate wall segment length for UV mapping
        var segment_length = p0.distance_to(p1)

        # Generate wall for each floor
        for floor in range(floors):
            var y_bottom = floor * floor_height
            var y_top = (floor + 1) * floor_height

            # Create vertices for this wall segment
            var v0 = Vector3(p0.x, y_bottom, p0.y)
            var v1 = Vector3(p1.x, y_bottom, p1.y)
            var v2 = Vector3(p1.x, y_top, p1.y)
            var v3 = Vector3(p0.x, y_top, p0.y)

            # Calculate UVs
            var uv0 = Vector2(0, (y_bottom / height) * texture_scale)
            var uv1 = Vector2(segment_length * texture_scale, (y_bottom / height) * texture_scale)
            var uv2 = Vector2(segment_length * texture_scale, (y_top / height) * texture_scale)
            var uv3 = Vector2(0, (y_top / height) * texture_scale)

            # Add quad (flip for interior walls)
            if flip_normals:
                add_quad(st, v1, v0, v3, v2, uv1, uv0, uv3, uv2)
            else:
                add_quad(st, v0, v1, v2, v3, uv0, uv1, uv2, uv3)

## Shrink footprint inward by specified amount (for interior walls)
func _shrink_footprint(footprint: PackedVector2Array, amount: float) -> PackedVector2Array:
    var shrunken = PackedVector2Array()
    var point_count = footprint.size()

    for i in range(point_count):
        var prev = footprint[(i - 1 + point_count) % point_count]
        var curr = footprint[i]
        var next = footprint[(i + 1) % point_count]

        # Calculate inward normals for adjacent edges
        var edge1 = curr - prev
        var edge2 = next - curr

        var normal1 = Vector2(-edge1.y, edge1.x).normalized()
        var normal2 = Vector2(-edge2.y, edge2.x).normalized()

        # Average the normals to get corner offset direction
        var offset_dir = (normal1 + normal2).normalized()

        # Move point inward
        shrunken.append(curr + offset_dir * amount)

    return shrunken

## Helper function to generate walls with window cutouts
## This version is called by window component to avoid overlapping geometry
func generate_with_cutouts(st: SurfaceTool, params: Dictionary, materials: Dictionary,
                           cutouts: Array) -> void:
    # TODO: Implement wall generation with window cutouts
    # For now, just generate regular walls
    # Window component will handle additive window geometry
    generate(st, params, materials)
