extends WorldComponentBase
class_name UnifiedRoadNetworkComponent

## Generates unified road networks using the new unified road system with proper bridge detection and tessellated rendering

var unified_road_system = null

func get_priority() -> int:
    return 55  # Same as improved_road_planner

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
        "road_quality": "standard",  # "low", "standard", "high"
        "max_road_connection_distance": 8000.0,
        "extra_road_connectivity": 0.5,
        "sea_level": 20.0,
        "bridge_clearance": 8.0,
        "bridge_type_threshold_short": 100.0,
        "bridge_type_threshold_medium": 300.0,
        "bridge_type_threshold_long": 800.0
    }

func _init():
    unified_road_system = load("res://scripts/world/unified_road_system.gd").new()

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if not bool(params.get("enable_roads", true)):
        # Store empty road data for downstream components
        ctx.set_data("organic_roads", [])
        return
    
    if ctx == null:
        push_error("UnifiedRoadNetworkComponent: missing ctx")
        return
    
    if ctx.terrain_generator == null:
        push_error("UnifiedRoadNetworkComponent: missing terrain_generator")
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
        print("⚠️ UnifiedRoadNetworkComponent: insufficient data for road generation")
        ctx.set_data("organic_roads", [])
        return

## Generate roads based on settlements
func _generate_from_settlements(settlements: Array, params: Dictionary, rng: RandomNumberGenerator) -> void:
    # Set up the unified road system
    unified_road_system.set_terrain_generator(ctx.terrain_generator)
    unified_road_system.set_world_context(ctx)

    print("🛣️ Starting unified road network generation from %d settlements..." % settlements.size())

    # Generate the complete road network
    var generation_result: Dictionary = unified_road_system.generate_complete_road_network(
        settlements,
        params
    )

    if generation_result.success:
        # Store the road network in the context using the expected format
        var formatted_roads: Array = _format_roads_for_downstream(generation_result.road_segments)
        ctx.set_data("organic_roads", formatted_roads)

        # Create visual representation of roads
        _create_road_visuals(formatted_roads, params)

        print("✅ Unified road network generation complete: %d segments" % formatted_roads.size())
        print("📊 Network stats: %d total segments, %d bridges created" % [
            generation_result.generation_stats.total_segments,
            generation_result.generation_stats.bridges_created
        ])
    else:
        push_error("❌ Failed to generate unified road network: %s" % str(generation_result.errors))
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

    # Set up the unified road system
    unified_road_system.set_terrain_generator(ctx.terrain_generator)
    unified_road_system.set_world_context(ctx)

    print("🛣️ Starting unified road network generation from %d waypoints..." % pseudo_settlements.size())

    # Generate the complete road network
    var generation_result: Dictionary = unified_road_system.generate_complete_road_network(
        pseudo_settlements,
        params
    )

    if generation_result.success:
        # Store the road network in the context using the expected format
        var formatted_roads: Array = _format_roads_for_downstream(generation_result.road_segments)
        ctx.set_data("organic_roads", formatted_roads)

        # Create visual representation of roads
        _create_road_visuals(formatted_roads, params)

        print("✅ Waypoint-based unified road network generation complete: %d segments" % formatted_roads.size())
        print("📊 Network stats: %d total segments, %d bridges created" % [
            generation_result.generation_stats.total_segments,
            generation_result.generation_stats.bridges_created
        ])
    else:
        push_error("❌ Failed to generate unified waypoint-based road network: %s" % str(generation_result.errors))
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
            "is_bridge": segment.get("is_bridge", false),
            "demand": segment.get("demand", 100.0)  # Default demand value
        }

        formatted_roads.append(formatted_segment)

    return formatted_roads

## Create visual representations of the roads with proper bridge handling
func _create_road_visuals(road_segments: Array, params: Dictionary) -> void:
    # Get infrastructure layer
    var infra: Node3D = ctx.get_layer("Infrastructure")
    var roads_root: Node3D = infra.get_node_or_null("UnifiedRoadNetwork")
    if roads_root == null:
        roads_root = Node3D.new()
        roads_root.name = "UnifiedRoadNetwork"
        infra.add_child(roads_root)

    # Create materials based on road type with enhanced parameters for visibility
    var highway_mat: Material = _create_road_material("highway")
    var arterial_mat: Material = _create_road_material("arterial")
    var local_mat: Material = _create_road_material("local")
    var bridge_mat: Material = _create_road_material("bridge")

    # Set enhanced parameters for road visibility
    params["road_terrain_clearance"] = 2.0  # Ensure roads are clearly above terrain
    params["bridge_clearance"] = 8.0       # Proper clearance for bridges over water

    # Generate geometry for each road segment using the unified system
    for segment in road_segments:
        var path: PackedVector3Array = segment.get("path", PackedVector3Array())
        var width: float = segment.get("width", 8.0)
        var road_type: String = segment.get("type", "local")
        var is_bridge: bool = segment.get("is_bridge", false)

        if path.size() >= 2:
            # Select appropriate material
            var material: Material = local_mat
            match road_type:
                "highway": material = highway_mat
                "arterial": material = arterial_mat
                "bridge": material = bridge_mat
                "local": material = local_mat

            if is_bridge:
                # Create bridge for this path since it crosses water
                var start_pos: Vector3 = path[0]
                var end_pos: Vector3 = path[-1]

                var bridge_mesh: MeshInstance3D = unified_road_system.create_bridge_mesh(start_pos, end_pos, width, material)
                if bridge_mesh != null:
                    bridge_mesh.name = "Bridge_%s" % road_type
                    roads_root.add_child(bridge_mesh)
            else:
                # Generate regular road geometry with conservative offset to account for carving
                var road_mesh: MeshInstance3D = unified_road_system.create_tessellated_road_mesh(path, width, road_type, material)
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
        "bridge":
            mat.albedo_color = Color(0.12, 0.12, 0.13)  # Slightly different for bridges
            mat.roughness = 0.88
            mat.metallic = 0.15  # Slightly metallic for structural look
            mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
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
    if unified_road_system:
        unified_road_system = null