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
	# Landmarks and special buildings: 50% parametric
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
		width, depth, height,
		style_name,
		{"seed": rng.randi()}
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
		# Fallback: simple box
		return _get_fallback_building(zone_type, rng)

	# Get available styles for this zone
	var available_styles: Array = _get_styles_for_zone(zone_type)

	if available_styles.is_empty():
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

	for style in all_styles:
		if style == null:
			continue

		var region: String = str(style.region).to_lower()
		var era: String = str(style.era).to_lower()

		# Map zones to architectural styles
		if zone_type == "downtown" or zone_type == "commercial":
			# Commercial: prefer modern, art deco, neoclassical
			if region.contains("american") or era.contains("modern") or era.contains("neoclassical"):
				filtered.append(style)
		elif zone_type == "residential" or zone_type == "town_center":
			# Residential: wide variety, prefer traditional
			if region.contains("traditional") or region.contains("scandinavian") or region.contains("mediterranean"):
				filtered.append(style)
		elif zone_type == "industrial":
			# Industrial: modern, brutalist
			if era.contains("modern") or era.contains("brutalist"):
				filtered.append(style)
		elif zone_type == "rural" or zone_type == "farms":
			# Rural: medieval, traditional, rustic
			if era.contains("medieval") or region.contains("traditional"):
				filtered.append(style)
		else:
			# Mixed/default: allow all styles
			filtered.append(style)

	# If no matches, use all styles
	if filtered.is_empty():
		for style in all_styles:
			if style != null:
				filtered.append(style)

	return filtered


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
