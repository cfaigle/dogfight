extends WorldComponentBase
class_name OrganicBuildingPlacementComponent

## Places buildings on pre-generated plots
## Reuses existing collision system and building styles
## Priority: 65 (same as old settlement_buildings)

func get_priority() -> int:
	return 65

func get_dependencies() -> Array[String]:
	return ["building_plots", "heightmap"]

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if ctx == null or ctx.terrain_generator == null:
		push_error("OrganicBuildingPlacementComponent: missing ctx/terrain_generator")
		return

	if not ctx.has_data("building_plots"):
		push_warning("OrganicBuildingPlacementComponent: no building_plots available")
		return

	var plots: Array = ctx.get_data("building_plots")

	# Initialize collision grid (15m cells, same as existing system)
	var collision_cell_size := 15.0
	var collision_grid := {}

	var buildings_layer := ctx.get_layer("Buildings")

	var placed_count := 0

	for plot in plots:
		# Check collision
		if _check_collision(plot.position, collision_grid, collision_cell_size):
			continue

		# Create building
		var building := _place_building_on_plot(plot, rng)
		if building != null:
			buildings_layer.add_child(building)
			_mark_building_in_grid(plot.position, collision_grid, collision_cell_size, plot.lot_width)
			placed_count += 1

	print("OrganicBuildingPlacement: Placed ", placed_count, " buildings from ", plots.size(), " plots")

func _place_building_on_plot(plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
	# Get terrain height at plot position
	var height := ctx.terrain_generator.get_height_at(plot.position.x, plot.position.z)
	var final_pos := Vector3(plot.position.x, height, plot.position.z)

	# Create building mesh
	var building := MeshInstance3D.new()
	building.position = final_pos
	building.rotation.y = plot.yaw

	# Generate mesh based on plot type
	var mesh := _generate_building_mesh(plot, rng)
	building.mesh = mesh

	return building

func _generate_building_mesh(plot: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	# Simple box building for now (can be enhanced with parametric system later)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	# Building dimensions
	var base_width: float = plot.lot_width
	var base_depth: float = plot.lot_depth

	# Height based on category
	var height := 0.0
	match plot.height_category:
		"tall":
			height = rng.randf_range(18.0, 36.0)  # 6-12 floors
		"medium":
			height = rng.randf_range(9.0, 15.0)   # 3-5 floors
		"low":
			height = rng.randf_range(3.0, 6.0)    # 1-2 floors

	# Building type affects color
	var color := Color.WHITE
	match plot.building_type:
		"commercial":
			color = Color(0.7, 0.7, 0.8)  # Gray/blue commercial
		"residential":
			color = Color(0.9, 0.85, 0.7)  # Warm residential
		"mixed":
			color = Color(0.8, 0.8, 0.75)  # Mixed
		"rural":
			color = Color(0.85, 0.75, 0.6)  # Earthy rural

	var w: float = base_width * 0.5
	var d: float = base_depth * 0.5
	var h: float = height

	# Bottom vertices (y=0)
	var v0 := Vector3(-w, 0, -d)
	var v1 := Vector3(w, 0, -d)
	var v2 := Vector3(w, 0, d)
	var v3 := Vector3(-w, 0, d)

	# Top vertices (y=h)
	var v4 := Vector3(-w, h, -d)
	var v5 := Vector3(w, h, -d)
	var v6 := Vector3(w, h, d)
	var v7 := Vector3(-w, h, d)

	# Front face (-Z)
	_add_quad(vertices, normals, indices, v0, v1, v5, v4, Vector3(0, 0, -1))
	# Back face (+Z)
	_add_quad(vertices, normals, indices, v3, v2, v6, v7, Vector3(0, 0, 1))
	# Left face (-X)
	_add_quad(vertices, normals, indices, v3, v0, v4, v7, Vector3(-1, 0, 0))
	# Right face (+X)
	_add_quad(vertices, normals, indices, v1, v2, v6, v5, Vector3(1, 0, 0))
	# Top face (+Y)
	_add_quad(vertices, normals, indices, v4, v5, v6, v7, Vector3(0, 1, 0))

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Create material with building color
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.surface_set_material(0, material)

	return mesh

func _add_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	var base_idx := vertices.size()

	vertices.append(v0)
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v3)

	for i in range(4):
		normals.append(normal)

	# Two triangles
	indices.append(base_idx + 0)
	indices.append(base_idx + 1)
	indices.append(base_idx + 2)

	indices.append(base_idx + 0)
	indices.append(base_idx + 2)
	indices.append(base_idx + 3)

func _check_collision(pos: Vector3, grid: Dictionary, cell_size: float) -> bool:
	var cell := Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))
	return grid.has(cell)

func _mark_building_in_grid(pos: Vector3, grid: Dictionary, cell_size: float, building_width: float) -> void:
	var radius := int(building_width / cell_size) + 1
	var center_cell := Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))

	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell := center_cell + Vector2i(dx, dz)
			grid[cell] = true
