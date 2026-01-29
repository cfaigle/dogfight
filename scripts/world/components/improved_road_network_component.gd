extends WorldComponentBase
class_name ImprovedRoadNetworkComponent

## Generates improved road networks using the new master planning system.

var road_system_manager = null

func get_priority() -> int:
	return 55  # Same as original traffic_based_road_planner

func get_dependencies() -> Array[String]:
	return ["waypoints", "heightmap", "settlements"]

func get_optional_params() -> Dictionary:
	return {
		"enable_roads": true,
		"road_width": 18.0,
		"road_smooth": true,
		"allow_bridges": true,
		"road_density": 1.0,
		"highway_density": 0.35,
		"enable_terrain_carving": true,
		"enable_elevation_adjustment": true,
		"max_road_gradient": 0.15,
		"road_quality": "standard"  # "low", "standard", "high"
	}

func _init():
	road_system_manager = preload("res://scripts/world/simple_road_system.gd").new()

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
	if not bool(params.get("enable_roads", true)):
		return
	if ctx == null:
		push_error("ImprovedRoadNetworkComponent: missing ctx")
		return
	if ctx.terrain_generator == null:
		push_error("ImprovedRoadNetworkComponent: missing terrain_generator")
		return

	# Get waypoints for road planning
	var waypoints: Array = ctx.get_data("waypoints")
	var settlements: Array = ctx.settlements
	
	# If we have settlements, use them as primary targets
	# Otherwise fall back to waypoints
	if settlements.size() >= 2:
		# Use settlements as primary road targets
		_generate_from_settlements(settlements, params, rng)
	elif waypoints.size() >= 2:
		# Use waypoints for road planning
		_generate_from_waypoints(waypoints, params, rng)
	else:
		print("⚠️ ImprovedRoadNetworkComponent: insufficient data for road generation")
		ctx.set_data("organic_roads", [])
		return

## Generate roads based on settlements
func _generate_from_settlements(settlements: Array, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Set up the road system manager
	road_system_manager.set_terrain_generator(ctx.terrain_generator)
	road_system_manager.set_world_context(ctx)

	print("🛣️ Starting improved road network generation from %d settlements..." % settlements.size())
	
	# Generate the complete road network
	var generation_result: Dictionary = road_system_manager.generate_complete_road_network(
		settlements, 
		params
	)
	
	if generation_result.success:
		# Store the road network in the context using the expected format
		var formatted_roads: Array = _format_roads_for_downstream(generation_result.road_segments)
		ctx.set_data("organic_roads", formatted_roads)
		
		# Create visual representation of roads
		_create_road_visuals(formatted_roads, params)
		
		print("✅ Improved road network generation complete: %d segments" % formatted_roads.size())
		print("📊 Network stats: %d segments" % [
			generation_result.generation_stats.total_segments
		])
	else:
		push_error("❌ Failed to generate road network: %s" % str(generation_result.errors))
		ctx.set_data("organic_roads", [])

## Generate roads based on waypoints (fallback)
func _generate_from_waypoints(waypoints: Array, params: Dictionary, rng: RandomNumberGenerator) -> void:
	# Convert waypoints to pseudo-settlements for road planning
	var pseudo_settlements: Array = []
	for wp in waypoints:
		if wp is Dictionary and wp.has("position"):
			pseudo_settlements.append({
				"center": wp.position,
				"name": "waypoint_%d" % pseudo_settlements.size(),
				"population": int(wp.get("importance_score", 100))  # Use importance as population proxy
			})
	
	if pseudo_settlements.size() < 2:
		ctx.set_data("organic_roads", [])
		return
	
	# Set up the road system manager
	road_system_manager.set_terrain_generator(ctx.terrain_generator)
	road_system_manager.set_world_context(ctx)

	print("🛣️ Starting improved road network generation from %d waypoints..." % pseudo_settlements.size())
	
	# Generate the complete road network
	var generation_result: Dictionary = road_system_manager.generate_complete_road_network(
		pseudo_settlements, 
		params
	)
	
	if generation_result.success:
		# Store the road network in the context using the expected format
		var formatted_roads: Array = _format_roads_for_downstream(generation_result.road_segments)
		ctx.set_data("organic_roads", formatted_roads)
		
		# Create visual representation of roads
		_create_road_visuals(formatted_roads, params)
		
		print("✅ Waypoint-based road network generation complete: %d segments" % formatted_roads.size())
		print("📊 Network stats: %d segments" % [
			generation_result.generation_stats.total_segments
		])
	else:
		push_error("❌ Failed to generate waypoint-based road network: %s" % str(generation_result.errors))
		ctx.set_data("organic_roads", [])

## Format roads to match expected downstream format
func _format_roads_for_downstream(road_segments: Array) -> Array:
	var formatted_roads: Array = []
	
	for segment in road_segments:
		var formatted_segment: Dictionary = {
			"path": segment.get("path", PackedVector3Array()),
			"width": segment.get("width", 8.0),
			"type": segment.get("type", "local"),
			"from": segment.get("from", Vector3.ZERO),
			"to": segment.get("to", Vector3.ZERO),
			"demand": segment.get("demand", 100.0)  # Default demand value
		}
		
		formatted_roads.append(formatted_segment)
	
	return formatted_roads

## Create visual representations of the roads
func _create_road_visuals(road_segments: Array, params: Dictionary) -> void:
	# Get infrastructure layer
	var infra: Node3D = ctx.get_layer("Infrastructure")
	var roads_root: Node3D = infra.get_node_or_null("ImprovedRoadNetwork")
	if roads_root == null:
		roads_root = Node3D.new()
		roads_root.name = "ImprovedRoadNetwork"
		infra.add_child(roads_root)
	
	# Create materials based on road type
	var highway_mat: Material = _create_road_material("highway")
	var arterial_mat: Material = _create_road_material("arterial") 
	var local_mat: Material = _create_road_material("local")
	
	# Generate geometry for each road segment using the new geometry generator
	var geometry_generator = preload("res://scripts/world/road_geometry_generator.gd").new()
	geometry_generator.set_terrain_generator(ctx.terrain_generator)
	
	for segment in road_segments:
		var path: PackedVector3Array = segment.get("path", PackedVector3Array())
		var width: float = segment.get("width", 8.0)
		var road_type: String = segment.get("type", "local")
		
		if path.size() >= 2:
			# Select appropriate material
			var material: Material = local_mat
			match road_type:
				"highway": material = highway_mat
				"arterial": material = arterial_mat
				"local": material = local_mat
			
			# Generate road geometry using the new system
			var road_mesh: MeshInstance3D = geometry_generator.generate_road_mesh(path, width, material)
			if road_mesh != null:
				road_mesh.name = "RoadSegment_%s" % road_type
				roads_root.add_child(road_mesh)

## Create road material based on type
func _create_road_material(road_type: String) -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	
	match road_type:
		"highway":
			mat.albedo_color = Color(0.08, 0.08, 0.09)  # Dark asphalt for highways
			mat.roughness = 0.95
			mat.metallic = 0.0
			mat.uv1_scale = Vector3(0.3, 0.3, 0.3)  # Smaller texture repeat for highways
		"arterial":
			mat.albedo_color = Color(0.10, 0.10, 0.11)  # Medium asphalt for arterials
			mat.roughness = 0.92
			mat.metallic = 0.0
			mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
		"local":
			mat.albedo_color = Color(0.12, 0.12, 0.13)  # Lighter asphalt for local roads
			mat.roughness = 0.90
			mat.metallic = 0.0
			mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
		_:
			mat.albedo_color = Color(0.10, 0.10, 0.11)
			mat.roughness = 0.90
			mat.metallic = 0.0
			mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	
	return mat

## Cleanup resources
func cleanup() -> void:
	if road_system_manager:
		road_system_manager = null