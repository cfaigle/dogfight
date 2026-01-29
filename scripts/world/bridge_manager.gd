class_name BridgeManager
extends RefCounted

## Bridge manager that creates appropriate bridges based on distance and terrain

var terrain_generator = null
var world_context = null

func set_terrain_generator(terrain_gen) -> void:
	terrain_generator = terrain_gen

func set_world_context(world_ctx) -> void:
	world_context = world_ctx

## Create appropriate bridge based on distance and water conditions
func create_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material = null) -> MeshInstance3D:
	var distance: float = start_pos.distance_to(end_pos)
	
	if distance <= 100.0:
		return _create_short_bridge(start_pos, end_pos, width, material)
	elif distance <= 300.0:
		return _create_medium_bridge(start_pos, end_pos, width, material)
	elif distance <= 800.0:
		return _create_long_bridge(start_pos, end_pos, width, material)
	else:
		return _create_spanning_bridge(start_pos, end_pos, width, material)

## Create short bridge (beam bridge up to 100m)
func _create_short_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate water level and deck height
	var water_level: float = _get_water_level_at(start_pos, end_pos)
	var deck_height: float = water_level + 8.0  # 8m clearance above water
	
	# Create simple beam bridge deck
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
	
	var start_left: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) - right
	var start_right: Vector3 = Vector3(start_pos.x, deck_height, start_pos.z) + right
	var end_left: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) - right
	var end_right: Vector3 = Vector3(end_pos.x, deck_height, end_pos.z) + right
	
	# Create deck surface
	st.set_normal(Vector3.UP)
	st.add_vertex(start_left)
	st.add_vertex(end_right)
	st.add_vertex(start_right)
	
	st.set_normal(Vector3.UP)
	st.add_vertex(start_left)
	st.add_vertex(end_left)
	st.add_vertex(end_right)
	
	# Add simple railings
	var rail_height: float = 1.2
	var start_left_rail_top: Vector3 = start_left + Vector3.UP * rail_height
	var start_right_rail_top: Vector3 = start_right + Vector3.UP * rail_height
	var end_left_rail_top: Vector3 = end_left + Vector3.UP * rail_height
	var end_right_rail_top: Vector3 = end_right + Vector3.UP * rail_height
	
	# Left railing
	var left_normal: Vector3 = -right.normalized()
	st.set_normal(left_normal)
	st.add_vertex(start_left)
	st.add_vertex(start_left_rail_top)
	st.add_vertex(end_left_rail_top)
	
	st.set_normal(left_normal)
	st.add_vertex(start_left)
	st.add_vertex(end_left_rail_top)
	st.add_vertex(end_left)
	
	# Right railing
	var right_normal: Vector3 = right.normalized()
	st.set_normal(right_normal)
	st.add_vertex(start_right)
	st.add_vertex(end_right_rail_top)
	st.add_vertex(start_right_rail_top)
	
	st.set_normal(right_normal)
	st.add_vertex(start_right)
	st.add_vertex(end_right)
	st.add_vertex(end_right_rail_top)
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	if material:
		mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Add support pillars at ends
	_add_simple_pillars(mesh_instance, [start_pos, end_pos], water_level, deck_height, width * 0.2, material)
	
	return mesh_instance

## Create medium bridge (arch bridge 100-300m)
func _create_medium_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate water level and deck height
	var water_level: float = _get_water_level_at(start_pos, end_pos)
	var deck_height: float = water_level + 10.0  # 10m clearance
	
	# Create arch bridge with central support
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
	
	# Create deck with arch support
	var segments: int = 20
	var center_pos: Vector3 = start_pos.lerp(end_pos, 0.5)
	var center_deck_height: float = deck_height + 8.0  # Higher in the center
	
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		
		var pos0: Vector3 = start_pos.lerp(end_pos, t0)
		var pos1: Vector3 = start_pos.lerp(end_pos, t1)
		
		# Calculate arch height (parabolic curve)
		var arch_factor0: float = 4.0 * t0 * (1.0 - t0)  # Parabolic curve
		var arch_factor1: float = 4.0 * t1 * (1.0 - t1)
		
		var deck_y0: float = deck_height + arch_factor0 * 8.0
		var deck_y1: float = deck_height + arch_factor1 * 8.0
		
		var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
		var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
		var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
		var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
		
		# Add deck surface
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_right1)
		st.add_vertex(deck_right0)
		
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_left1)
		st.add_vertex(deck_right1)
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	if material:
		mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Add arch support pillars
	var pillar_positions: Array[Vector3] = [start_pos, center_pos, end_pos]
	_add_simple_pillars(mesh_instance, pillar_positions, water_level, deck_height, width * 0.25, material)
	
	return mesh_instance

## Create long bridge (suspension bridge 300-800m)
func _create_long_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate water level and deck height
	var water_level: float = _get_water_level_at(start_pos, end_pos)
	var deck_height: float = water_level + 15.0  # 15m clearance
	
	# Create suspension bridge deck with sag
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
	
	var segments: int = 40
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		
		var pos0: Vector3 = start_pos.lerp(end_pos, t0)
		var pos1: Vector3 = start_pos.lerp(end_pos, t1)
		
		# Calculate sag in the middle (parabolic)
		var sag_factor: float = 0.05  # Amount of sag
		var sag0: float = -sag_factor * 4.0 * t0 * (1.0 - t0)  # Parabolic sag
		var sag1: float = -sag_factor * 4.0 * t1 * (1.0 - t1)
		
		var deck_y0: float = deck_height + sag0
		var deck_y1: float = deck_height + sag1
		
		var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
		var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
		var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
		var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
		
		# Add deck surface
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_right1)
		st.add_vertex(deck_right0)
		
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_left1)
		st.add_vertex(deck_right1)
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	if material:
		mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Add suspension towers
	var tower_positions: Array[Vector3] = [start_pos, end_pos]
	_add_suspension_towers(mesh_instance, tower_positions, deck_height, width, material)
	
	return mesh_instance

## Create spanning bridge (cable-stayed bridge 800m+)
func _create_spanning_bridge(start_pos: Vector3, end_pos: Vector3, width: float, material = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate water level and deck height
	var water_level: float = _get_water_level_at(start_pos, end_pos)
	var deck_height: float = water_level + 20.0  # 20m clearance
	
	# Create cable-stayed bridge deck
	var direction: Vector3 = (end_pos - start_pos).normalized()
	var right: Vector3 = direction.cross(Vector3.UP).normalized() * width * 0.5
	
	var segments: int = 60
	for i in range(segments):
		var t0: float = float(i) / float(segments)
		var t1: float = float(i + 1) / float(segments)
		
		var pos0: Vector3 = start_pos.lerp(end_pos, t0)
		var pos1: Vector3 = start_pos.lerp(end_pos, t1)
		
		# Keep deck level for cable-stayed bridge
		var deck_y0: float = deck_height
		var deck_y1: float = deck_height
		
		var deck_left0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) - right
		var deck_right0: Vector3 = Vector3(pos0.x, deck_y0, pos0.z) + right
		var deck_left1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) - right
		var deck_right1: Vector3 = Vector3(pos1.x, deck_y1, pos1.z) + right
		
		# Add deck surface
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_right1)
		st.add_vertex(deck_right0)
		
		st.set_normal(Vector3.UP)
		st.add_vertex(deck_left0)
		st.add_vertex(deck_left1)
		st.add_vertex(deck_right1)
	
	# Create mesh instance
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	if material:
		mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	# Add multiple cable-stayed towers
	var distance: float = start_pos.distance_to(end_pos)
	var num_towers: int = max(2, int(distance / 300.0))  # One tower every 300m
	
	var tower_positions: Array[Vector3] = [start_pos]  # Start tower
	for i in range(1, num_towers):
		var t: float = float(i) / float(num_towers)
		var pos: Vector3 = start_pos.lerp(end_pos, t)
		tower_positions.append(pos)
	tower_positions.append(end_pos)  # End tower
	
	_add_cable_stayed_towers(mesh_instance, tower_positions, deck_height, width, material)
	
	return mesh_instance

## Add simple support pillars
func _add_simple_pillars(parent: MeshInstance3D, positions: Array, water_level: float, deck_height: float, pillar_width: float, material) -> void:
	for pos in positions:
		var pillar_height: float = deck_height - water_level
		if pillar_height > 2.0:  # Only add pillar if there's significant height difference
			_add_single_pillar(parent, pos.x, pos.z, water_level, deck_height, pillar_width, material)

## Add suspension bridge towers
func _add_suspension_towers(parent: MeshInstance3D, positions: Array, deck_height: float, road_width: float, material) -> void:
	var tower_height: float = 25.0  # Tower height above deck
	var tower_width: float = road_width * 0.3
	
	for pos in positions:
		_add_single_tower(parent, pos.x, pos.z, deck_height, deck_height + tower_height, tower_width, material)

## Add cable-stayed bridge towers
func _add_cable_stayed_towers(parent: MeshInstance3D, positions: Array, deck_height: float, road_width: float, material) -> void:
	var tower_height: float = 40.0  # Taller towers for cable-stayed bridges
	var tower_width: float = road_width * 0.25
	
	for pos in positions:
		_add_single_tower(parent, pos.x, pos.z, deck_height, deck_height + tower_height, tower_width, material)

## Add a single pillar
func _add_single_pillar(parent: MeshInstance3D, x: float, z: float, bottom_y: float, top_y: float, width: float, material) -> void:
	if terrain_generator == null:
		return
	
	var height: float = top_y - bottom_y
	if height <= 0.0:
		return
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var hw: float = width * 0.5
	var hd: float = width * 0.5
	
	# Create a simple rectangular pillar
	var base_corners: Array[Vector3] = [
		Vector3(x - hw, bottom_y, z - hd),  # 0: back-left
		Vector3(x + hw, bottom_y, z - hd),  # 1: back-right
		Vector3(x + hw, bottom_y, z + hd),  # 2: front-right
		Vector3(x - hw, bottom_y, z + hd),  # 3: front-left
	]
	
	var top_corners: Array[Vector3] = [
		Vector3(x - hw, top_y, z - hd),  # 4: back-left
		Vector3(x + hw, top_y, z - hd),  # 5: back-right
		Vector3(x + hw, top_y, z + hd),  # 6: front-right
		Vector3(x - hw, top_y, z + hd),  # 7: front-left
	]
	
	# Create 4 side faces
	var face_normals: Array[Vector3] = [
		Vector3(0, 0, -1),  # Back face
		Vector3(1, 0, 0),   # Right face
		Vector3(0, 0, 1),   # Front face
		Vector3(-1, 0, 0),  # Left face
	]
	
	for side in range(4):
		var next_side: int = (side + 1) % 4
		var b0: Vector3 = base_corners[side]
		var b1: Vector3 = base_corners[next_side]
		var t0: Vector3 = top_corners[side]
		var t1: Vector3 = top_corners[next_side]
		var normal: Vector3 = face_normals[side]
		
		# Two triangles per face
		st.set_normal(normal)
		st.add_vertex(b0)
		st.add_vertex(t1)
		st.add_vertex(t0)
		
		st.set_normal(normal)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(t1)
	
	# Top cap
	st.set_normal(Vector3.UP)
	st.add_vertex(top_corners[0])
	st.add_vertex(top_corners[2])
	st.add_vertex(top_corners[1])
	
	st.set_normal(Vector3.UP)
	st.add_vertex(top_corners[0])
	st.add_vertex(top_corners[3])
	st.add_vertex(top_corners[2])
	
	var pillar_mesh := MeshInstance3D.new()
	pillar_mesh.mesh = st.commit()
	if material:
		pillar_mesh.material_override = material
	pillar_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	parent.add_child(pillar_mesh)

## Add a single tower
func _add_single_tower(parent: MeshInstance3D, x: float, z: float, bottom_y: float, top_y: float, width: float, material) -> void:
	# Towers are taller and more substantial than pillars
	_add_single_pillar(parent, x, z, bottom_y, top_y, width * 0.5, material)

## Get water level between two points
func _get_water_level_at(pos1: Vector3, pos2: Vector3) -> float:
	if terrain_generator == null:
		return 20.0  # Default sea level
	
	var h1: float = terrain_generator.get_height_at(pos1.x, pos1.z)
	var h2: float = terrain_generator.get_height_at(pos2.x, pos2.z)
	
	# Check if either point is below sea level (water)
	var sea_level: float = 20.0
	if world_context and world_context.has_method("get_sea_level"):
		sea_level = float(world_context.get_sea_level())
	elif world_context and world_context.has_method("get"):
		var sea_level_val = world_context.get("sea_level")
		if sea_level_val != null:
			sea_level = float(sea_level_val)
	
	if h1 < sea_level or h2 < sea_level:
		return sea_level
	
	# Return the lower of the two terrain heights as the water level
	return min(h1, h2)