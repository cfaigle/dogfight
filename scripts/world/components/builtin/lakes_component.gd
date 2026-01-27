extends WorldComponentBase
class_name LakesComponent

## Carves lakes into the heightmap and spawns simple lake meshes.
##
## Runs after `heightmap` and before `terrain_mesh`.

func get_priority() -> int:
    return 5

func get_optional_params() -> Dictionary:
    return {
        "lake_count": 8,
        "lake_min_radius": 160.0,
        "lake_max_radius": 520.0,
        "lake_depth_min": 10.0,
        "lake_depth_max": 45.0,
        "lake_min_height": Game.sea_level + 35.0,
        # Degrees (converted internally to slope gradient)
        "lake_max_slope": 10.0,
        
        # Lake scene generation parameters
        "lake_scene_percentage": 1.0,  # 100% default, adjustable 0.0-1.0
        "lake_types_resource": "res://resources/defs/lake_defs.tres",
        "lake_type_weights": {"basic": 0.3, "recreational": 0.3, "fishing": 0.25, "harbor": 0.15},
        
        # Scene density controls
        "boat_density_per_lake": 0.4,      # Average boats per lake
        "buoy_density_per_radius": 2.0,    # Buoys per 100 units of radius
        "dock_probability": 0.5,           # 50% chance of docks per lake
        "shore_feature_probability": 0.7,  # 70% chance of shore features
        
        # Performance controls
        "max_boats_per_lake": 8,
        "max_buoys_per_lake": 20,
        "max_docks_per_lake": 3,
        "lake_scene_lod_distance": 500.0,
        "lake_scene_max_detail_distance": 200.0,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    print("🏞️ LakesComponent: Starting generation")
    if ctx == null or ctx.terrain_generator == null:
        push_error("LakesComponent: missing ctx/terrain_generator")
        return
    if ctx.water_bodies_generator == null:
        # Optional feature; no lakes
        return
    if ctx.hmap.is_empty() or ctx.hmap_res <= 0:
        push_warning("LakesComponent: heightmap missing, skipping")
        return

    var gen: RefCounted = ctx.water_bodies_generator
    if not gen.has_method("carve_lakes"):
        push_error("LakesComponent: water_bodies_generator missing carve_lakes")
        return

    # Enhanced lake carving with scene type assignment
    var lakes: Array = _carve_lakes_with_scene_types(gen, ctx, params, rng)
    ctx.lakes = lakes
    print("  ✓ Carved ", lakes.size(), " lakes into heightmap")

    # Heightmap was modified in-place; make sure terrain generator sees it.
    ctx.terrain_generator.set_heightmap_data(ctx.hmap, ctx.hmap_res, ctx.hmap_step, ctx.hmap_half)

    # Generate basic lake water visualization (will be enhanced by lake scenes)
    if lakes.is_empty():
        print("  ⚠️  No lakes to visualize")
        return

    var water_layer: Node3D = ctx.get_layer("Water")
    var lakes_root := Node3D.new()
    lakes_root.name = "Lakes"
    water_layer.add_child(lakes_root)

    # Load lake definitions
    var lake_defs_path = params.get("lake_types_resource", "res://resources/defs/lake_defs.tres")
    var lake_defs = load(lake_defs_path) as LakeDefs

    print("  ✓ Creating water meshes for ", lakes.size(), " lakes")
    var mesh_count = 0

    for lake_data in lakes:
        mesh_count += 1
        if not (lake_data is Dictionary):
            continue
        
        # Create basic water mesh
        _create_lake_water_mesh(lakes_root, lake_data, lake_defs)

        # Generate detailed scene if this lake should have one
        if rng.randf() <= params.get("lake_scene_percentage", 1.0):
            var scene_root = _generate_lake_scene(ctx, lake_data, params, rng, lake_defs)
            if scene_root != null:
                lake_data["scene_root"] = scene_root

    print("  ✓ LakesComponent: Complete - created ", mesh_count, " lake water meshes")

# --- Lake scene generation helpers ---

func _carve_lakes_with_scene_types(gen: RefCounted, ctx: WorldContext, params: Dictionary, rng: RandomNumberGenerator) -> Array:
    var lakes = gen.call("carve_lakes", ctx, params, rng)
    
    # Assign scene types to lakes based on weights
    var lake_type_weights = params.get("lake_type_weights", {"basic": 0.3, "recreational": 0.3, "fishing": 0.25, "harbor": 0.15})
    var types = lake_type_weights.keys()
    var weights = lake_type_weights.values()
    
    var total_weight = 0.0
    for w in weights:
        total_weight += w
    
    for lake in lakes:
        if not (lake is Dictionary):
            continue
        
        var roll = rng.randf() * total_weight
        var current_weight = 0.0
        var selected_type = "basic"
        
        for i in range(types.size()):
            current_weight += weights[i]
            if roll <= current_weight:
                selected_type = types[i]
                break
        
        lake["scene_type"] = selected_type
    
    return lakes

func _create_lake_water_mesh(parent: Node3D, lake_data: Dictionary, lake_defs: LakeDefs) -> void:
    var center: Vector3 = lake_data.get("center", Vector3.ZERO)
    var radius: float = float(lake_data.get("radius", 200.0))
    var water_level: float = float(lake_data.get("water_level", Game.sea_level + 2.0))
    var depth: float = float(lake_data.get("depth", 15.0))  # Get carving depth
    var scene_type: String = lake_data.get("scene_type", "basic")

    # Debug: check actual terrain height at lake center after carving
    var terrain_h: float = ctx.terrain_generator.get_height_at(center.x, center.z) if ctx.terrain_generator != null else 0.0
    if parent.get_child_count() < 3:
        print("    Lake #", parent.get_child_count(), ": water_level=", water_level, " depth=", depth, " terrain_h=", terrain_h)

    var mi := MeshInstance3D.new()
    mi.name = "Lake_Water"

    # Use a thin cylinder at the water surface (ocean shader works best as thin surface)
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = 0.5  # Thin surface layer
    cyl.radial_segments = 48
    cyl.rings = 1
    mi.mesh = cyl

    # Use the same ocean shader as rivers but with purple color for visibility
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://resources/shaders/ocean.gdshader")
    # Purple color scheme for lakes (temporary for debugging)
    mat.set_shader_parameter("deep_color", Vector3(0.15, 0.02, 0.25))  # Deep purple
    mat.set_shader_parameter("glow_color", Vector3(0.45, 0.15, 0.65))  # Bright purple
    mi.material_override = mat

    # Position at water level (the carved terrain is below this)
    mi.position = Vector3(center.x, water_level - (cyl.height * 0.5), center.z)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)

func _create_water_material(scene_type: String, lake_defs: LakeDefs) -> StandardMaterial3D:
    # DEPRECATED: This function is no longer used - lakes now use ocean shader
    # Keeping for backward compatibility but should not be called
    var mat := StandardMaterial3D.new()

    match scene_type:
        "basic":
            mat.albedo_color = Color(0.06, 0.12, 0.18, 0.82)
        "recreational":
            mat.albedo_color = Color(0.08, 0.16, 0.24, 0.85)
        "fishing":
            mat.albedo_color = Color(0.04, 0.10, 0.14, 0.80)
        "harbor":
            mat.albedo_color = Color(0.10, 0.18, 0.22, 0.88)
        _:
            mat.albedo_color = Color(0.06, 0.12, 0.18, 0.82)

    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.roughness = 0.18
    mat.metallic = 0.0

    return mat

func _generate_lake_scene(ctx: WorldContext, lake_data: Dictionary, params: Dictionary, rng: RandomNumberGenerator, lake_defs: LakeDefs) -> Node3D:
    # Load lake scene factory (create it inline for now)
    var lake_scene_factory = LakeSceneFactory.new()
    return lake_scene_factory.generate_lake_scene(ctx, lake_data, params, rng, lake_defs)
