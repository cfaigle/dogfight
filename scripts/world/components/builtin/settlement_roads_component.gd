extends WorldComponentBase
class_name SettlementRoadsComponent

## Generates internal road networks within settlements (cities and towns).
## Cities get grid-pattern roads, towns get radial spoke roads.

func get_priority() -> int:
	return 65  # Run after settlements (60) but before inter-settlement roads (66)

func get_dependencies() -> Array[String]:
	return ["settlements"]

func get_optional_params() -> Dictionary:
	return {
		"enable_settlement_roads": true,
		"city_road_spacing": 120.0,  # Grid spacing in meters
		"town_spoke_count": 6,  # Number of radial roads from center
		"settlement_road_width": 12.0,
	}

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	print("🛣 SettlementRoadsComponent: Starting road generation")
	if not bool(params.get("enable_settlement_roads", true)):
		print("⚠️ Settlement roads disabled in params")
		return

	if ctx == null or ctx.terrain_generator == null:
		push_error("SettlementRoadsComponent: missing ctx or terrain_generator")
		return

	if ctx.settlements.is_empty():
		print("⚠️ No settlements found for road generation")
		return

	print("🛣 Found %d settlements for road generation" % ctx.settlements.size())

	var roads_root := Node3D.new()
	roads_root.name = "SettlementRoads"
	ctx.get_layer("Infrastructure").add_child(roads_root)

	var road_module := RoadModule.new()
	road_module.set_terrain_generator(ctx.terrain_generator)

	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.08, 0.08, 0.09)  # Much darker for contrast
	road_mat.roughness = 0.98
	road_mat.metallic = 0.0

	var road_width: float = float(params.get("settlement_road_width", 12.0))
	var city_spacing: float = float(params.get("city_road_spacing", 120.0))
	var town_spokes: int = int(params.get("town_spoke_count", 6))

	# Generate roads for each settlement
	var roads_generated: int = 0
	for settlement in ctx.settlements:
		if not (settlement is Dictionary):
			continue

		var s_type: String = str(settlement.get("type", ""))
		var center: Vector3 = settlement.get("center", Vector3.ZERO)
		var radius: float = settlement.get("radius", 200.0)

		# Skip hamlets (too small for internal roads)
		if s_type == "hamlet" or s_type == "industry":
			continue

		if s_type == "city":
			print("🏙 Generating grid roads for city at ", center)
			_create_city_road_grid(roads_root, center, radius, city_spacing, road_module, road_mat, road_width, rng)

			# TEMPORARY: Add a tall red beacon at city center so you can find it
			var beacon := MeshInstance3D.new()
			beacon.name = "CityBeacon"
			var beacon_mesh := CylinderMesh.new()
			beacon_mesh.height = 500.0
			beacon_mesh.top_radius = 5.0
			beacon_mesh.bottom_radius = 5.0
			beacon.mesh = beacon_mesh
			beacon.position = center + Vector3(0, 250, 0)
			var beacon_mat := StandardMaterial3D.new()
			beacon_mat.albedo_color = Color(1.0, 0.0, 0.0)
			beacon_mat.emission_enabled = true
			beacon_mat.emission = Color(1.0, 0.2, 0.2)
			beacon_mat.emission_energy = 2.0
			beacon.material_override = beacon_mat
			roads_root.add_child(beacon)

			roads_generated += 1
		elif s_type == "town":
			print("🏘 Generating radial roads for town at ", center)
			_create_town_radial_roads(roads_root, center, radius, town_spokes, road_module, road_mat, road_width, rng)
			roads_generated += 1

	print("✅ Generated roads for %d settlements" % roads_generated)

func _create_city_road_grid(
	parent: Node3D,
	center: Vector3,
	radius: float,
	spacing: float,
	road_module: RoadModule,
	road_mat: Material,
	road_width: float,
	rng: RandomNumberGenerator
) -> void:
	# Create grid road network
	var count: int = int(radius * 2.0 / spacing)
	var ns_count: int = count + 1
	var ew_count: int = count + 1

	print("  Creating %d N-S roads and %d E-W roads (spacing=%.1fm, radius=%.1fm)" % [ns_count, ew_count, spacing, radius])
	var roads_created: int = 0

	# North-south roads
	for i in range(-count/2, count/2 + 1):
		var x: float = center.x + float(i) * spacing
		var start := Vector3(x, 0, center.z - radius)
		var end := Vector3(x, 0, center.z + radius)
		start.y = ctx.terrain_generator.get_height_at(start.x, start.z) + 0.3  # Raise higher above terrain
		end.y = ctx.terrain_generator.get_height_at(end.x, end.z) + 0.3

		var path: PackedVector3Array = road_module.generate_road(start, end, {
			"allow_bridges": true,
			"smooth": true,
			"grid_resolution": 20.0
		})

		if path.size() > 1:
			var mesh_inst: MeshInstance3D = road_module.create_road_mesh(path, road_width, road_mat)
			if mesh_inst != null:
				parent.add_child(mesh_inst)
				roads_created += 1

	# East-west roads
	for j in range(-count/2, count/2 + 1):
		var z: float = center.z + float(j) * spacing
		var start := Vector3(center.x - radius, 0, z)
		var end := Vector3(center.x + radius, 0, z)
		start.y = ctx.terrain_generator.get_height_at(start.x, start.z) + 0.3  # Raise higher above terrain
		end.y = ctx.terrain_generator.get_height_at(end.x, end.z) + 0.3

		var path: PackedVector3Array = road_module.generate_road(start, end, {
			"allow_bridges": true,
			"smooth": true,
			"grid_resolution": 20.0
		})

		if path.size() > 1:
			var mesh_inst: MeshInstance3D = road_module.create_road_mesh(path, road_width, road_mat)
			if mesh_inst != null:
				parent.add_child(mesh_inst)
				roads_created += 1

	print("  ✅ Created %d road meshes for city grid" % roads_created)

func _create_town_radial_roads(
	parent: Node3D,
	center: Vector3,
	radius: float,
	spoke_count: int,
	road_module: RoadModule,
	road_mat: Material,
	road_width: float,
	rng: RandomNumberGenerator
) -> void:
	# Create radial roads from center
	for i in range(spoke_count):
		var angle: float = float(i) * TAU / float(spoke_count)
		var end_x: float = center.x + cos(angle) * radius
		var end_z: float = center.z + sin(angle) * radius

		var start := center
		var end := Vector3(end_x, 0, end_z)
		start.y = ctx.terrain_generator.get_height_at(start.x, start.z) + 0.3  # Raise higher above terrain
		end.y = ctx.terrain_generator.get_height_at(end.x, end.z) + 0.3

		var path: PackedVector3Array = road_module.generate_road(start, end, {
			"allow_bridges": true,
			"smooth": true,
			"grid_resolution": 20.0
		})

		if path.size() > 1:
			var mesh_inst: MeshInstance3D = road_module.create_road_mesh(path, road_width * 0.85, road_mat)
			if mesh_inst != null:
				parent.add_child(mesh_inst)
