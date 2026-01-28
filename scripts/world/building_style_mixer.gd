class_name BuildingStyleMixer
extends RefCounted

## Mixes parametric buildings (20-30%) with 27 building styles (70-80%)
## Creates variety while using both systems

var parametric_system: RefCounted = null
var building_style_defs: BuildingStyleDefs = null
var style_rotation_index: int = 0


func _init(parametric_sys: RefCounted, style_defs: BuildingStyleDefs):
    parametric_system = parametric_sys
    building_style_defs = style_defs


## Get next building mesh/material with mixed strategy
## Returns: {mesh: Mesh, material: Material, is_parametric: bool, style_id: String}
func get_next_building(zone_type: String, is_landmark: bool, rng: RandomNumberGenerator) -> Dictionary:
    # Regular buildings: 20% parametric, 80% from 27 styles
    var use_parametric: bool = false

    if parametric_system != null:
        if is_landmark:
            use_parametric = rng.randf() < 0.5  # 50% for landmarks
        else:
            use_parametric = rng.randf() < 0.2  # 20% for regular buildings

    if use_parametric and parametric_system != null:
        return _get_parametric_building(zone_type, is_landmark, rng)
    else:
        return _get_styled_building(zone_type, rng)
        
    # Safety fallback (should never reach here)
    return _get_fallback_building(zone_type, rng)


## Get parametric building
func _get_parametric_building(zone_type: String, is_landmark: bool, rng: RandomNumberGenerator) -> Dictionary:
    var style_name: String = ""

    # Map zone to parametric style
    if zone_type == "downtown" or zone_type == "commercial":
        style_name = "american_art_deco"
    elif zone_type == "residential" or zone_type == "town_center":
        style_name = "ww2_european"
    elif zone_type == "industrial":
        style_name = "industrial_modern"
    else:
        style_name = "ww2_european"  # Default

    # Generate parametric mesh
    var width: float = rng.randf_range(8.0, 16.0)
    var depth: float = rng.randf_range(8.0, 16.0)
    var height: float = rng.randf_range(12.0, 28.0)

    if is_landmark:
        width *= 1.5
        depth *= 1.5
        height *= 1.8

    var mesh: Mesh = parametric_system.create_parametric_building(
        zone_type,
        style_name,
        width, depth, height,
        1,  # floors
        1   # quality level
    )

    # Create simple material (parametric buildings handle their own materials)
    var material := StandardMaterial3D.new()
    material.albedo_color = _get_zone_color(zone_type)
    material.roughness = 0.9

    return {
        "mesh": mesh,
        "material": material,
        "is_parametric": true,
        "style_id": style_name,
        "width": width,
        "depth": depth,
        "height": height
    }


## Get building from 27 styles (round-robin for variety)
func _get_styled_building(zone_type: String, rng: RandomNumberGenerator) -> Dictionary:
    if building_style_defs == null:
        print("⚠️ building_style_defs is null, using fallback")
        # Fallback: simple box
        return _get_fallback_building(zone_type, rng)

    # Get available styles for this zone
    var available_styles: Array = _get_styles_for_zone(zone_type)

    if available_styles.is_empty():
        print("⚠️ No available styles for zone ", zone_type, ", using fallback")
        return _get_fallback_building(zone_type, rng)

    # Round-robin selection (ensures all styles get used)
    var style: BuildingStyle = available_styles[style_rotation_index % available_styles.size()]
    style_rotation_index += 1

    # Generate mesh from style
    var width: float = rng.randf_range(8.0, 16.0)
    var depth: float = rng.randf_range(8.0, 14.0)
    var height: float = rng.randf_range(10.0, 22.0)

    # Apply style-specific modifiers
    if style.properties.has("building_scale"):
        var scale: float = float(style.properties.building_scale)
        width *= scale
        depth *= scale
        height *= scale

    # Create procedural mesh based on style
    var mesh: Mesh = _create_style_mesh(style, width, depth, height)
    var material: Material = _create_style_material(style)

    return {
        "mesh": mesh,
        "material": material,
        "is_parametric": false,
        "style_id": style.id,
        "style_name": style.display_name,
        "width": width,
        "depth": depth,
        "height": height
    }


## Get styles appropriate for zone type
func _get_styles_for_zone(zone_type: String) -> Array:
    var all_styles: Array[BuildingStyle] = building_style_defs.get_all()
    var filtered: Array = []
    var preferred: Array = []
    var secondary: Array = []

    for style in all_styles:
        if style == null:
            continue

        var region: String = str(style.culture).to_lower()  # Fixed: was style.region
        var era: String = str(style.era).to_lower()

        # Categorize styles by preference for this zone
        var is_preferred: bool = false
        var is_secondary: bool = false

        match zone_type:
            "downtown", "commercial":
                # Commercial: prefer modern, industrial, north_american
                if era.contains("modern") or era.contains("industrial") or region.contains("north_american") or region.contains("american"):
                    is_preferred = true
                elif region.contains("european") or era.contains("neoclassical"):
                    is_secondary = true
                else:
                    is_secondary = true  # Allow all other styles as secondary
            "residential", "town_center":
                # Residential: prefer traditional, scandinavian, mediterranean
                if region.contains("traditional") or region.contains("scandinavian") or region.contains("mediterranean") or era.contains("medieval"):
                    is_preferred = true
                else:
                    is_secondary = true  # Allow all other styles as secondary
            "industrial":
                # Industrial: prefer industrial, modern, brutalist
                if era.contains("industrial") or era.contains("modern") or region.contains("industrial"):
                    is_preferred = true
                elif region.contains("european") or region.contains("north_american"):
                    is_secondary = true
                else:
                    is_secondary = true  # Allow all other styles as secondary
            "rural", "farms":
                # Rural: prefer medieval, traditional, rustic
                if era.contains("medieval") or region.contains("traditional") or region.contains("rural") or region.contains("scandinavian"):
                    is_preferred = true
                else:
                    is_secondary = true  # Allow all other styles as secondary
            _:
                # Mixed/default: all styles are preferred
                is_preferred = true

        # Add to appropriate category
        if is_preferred:
            preferred.append(style)
        elif is_secondary:
            secondary.append(style)

    # Combine: 70% preferred, 30% secondary (but include ALL styles)
    var result: Array = []
    
    # Add all preferred styles first
    result.append_array(preferred)
    
    # Add all secondary styles (ensuring all 27 styles are available)
    result.append_array(secondary)

    # Safety check: if somehow empty, return all styles
    if result.is_empty():
        for style in all_styles:
            if style != null:
                result.append(style)

    return result


## Create mesh from style definition
func _create_style_mesh(style: BuildingStyle, width: float, depth: float, height: float) -> Mesh:
    # For now, create simple box mesh (can be enhanced with procedural details)
    var box := BoxMesh.new()
    box.size = Vector3(width, height, depth)
    return box


## Create material from style definition
func _create_style_material(style: BuildingStyle) -> Material:
    var mat := StandardMaterial3D.new()

    # Use style colors
    if style.properties.has("wall_color"):
        mat.albedo_color = style.properties.wall_color
    else:
        mat.albedo_color = Color(0.2, 0.2, 0.22)

    mat.roughness = 0.95
    mat.metallic = 0.0

    return mat


## Fallback building (simple box)
func _get_fallback_building(zone_type: String, rng: RandomNumberGenerator) -> Dictionary:
    var width: float = rng.randf_range(8.0, 16.0)
    var depth: float = rng.randf_range(8.0, 14.0)
    var height: float = rng.randf_range(10.0, 22.0)

    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, height, depth)

    var material := StandardMaterial3D.new()
    material.albedo_color = _get_zone_color(zone_type)
    material.roughness = 0.95

    return {
        "mesh": mesh,
        "material": material,
        "is_parametric": false,
        "style_id": "fallback",
        "width": width,
        "depth": depth,
        "height": height
    }


## Get color for zone type
func _get_zone_color(zone_type: String) -> Color:
    match zone_type:
        "downtown", "commercial":
            return Color(0.18, 0.18, 0.20)
        "residential", "town_center":
            return Color(0.20, 0.20, 0.22)
        "industrial":
            return Color(0.16, 0.17, 0.16)
        "rural", "farms":
            return Color(0.22, 0.20, 0.18)
        _:
            return Color(0.20, 0.20, 0.22)
