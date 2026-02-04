class_name PropGenerator
extends RefCounted

var _terrain: TerrainGenerator = null
var _assets: RefCounted = null
var _settlements: Array = []
var _world_ctx: RefCounted = null
var _sea_level: float = 0.0

# Optional biome service (e.g. BiomeGenerator) providing `classify(x,z)`
var _biomes: RefCounted = null

var _prop_lod_roots: Array[Node3D] = []

func set_terrain_generator(t: TerrainGenerator) -> void:
    _terrain = t

func set_assets(a: RefCounted) -> void:
    _assets = a

func set_settlements(s: Array) -> void:
    _settlements = s

func set_biome_generator(b: RefCounted) -> void:
    _biomes = b

func get_lod_roots() -> Array[Node3D]:
    return _prop_lod_roots

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator, world_ctx: RefCounted = null) -> Dictionary:
    _prop_lod_roots = []
    _world_ctx = world_ctx
    if _terrain == null:
        push_error("PropGenerator: missing terrain generator")
        return {"prop_lod_groups": _prop_lod_roots}

    # `world_root` is already the props layer; place content directly under it.
    var props_root: Node3D = world_root

    # Get sea level from params or fallback to default
    _sea_level = float(params.get("sea_level", 0.0))

    # Forests - New Granular Parameter System
    # Forest Patch Parameters
    var forest_patch_count: int = int(params.get("forest_patch_count", 26))
    var trees_per_patch_target: int = int(params.get("forest_patch_trees_per_patch", 200))
    var patch_radius_min: float = float(params.get("forest_patch_radius_min", 180.0))
    var patch_radius_max: float = float(params.get("forest_patch_radius_max", 520.0))
    var patch_placement_attempts: int = int(params.get("forest_patch_placement_attempts", 50))
    var patch_placement_buffer: float = float(params.get("forest_patch_placement_buffer", 250.0))

    # Random Tree Parameters
    var random_tree_count: int = int(params.get("random_tree_count", 300))
    var random_tree_clearance_buffer: float = float(params.get("random_tree_clearance_buffer", 30.0))
    var random_tree_slope_limit: float = float(params.get("random_tree_slope_limit", 34.0))
    var random_tree_placement_attempts: int = int(params.get("random_tree_placement_attempts", 10))

    # Settlement Tree Parameters
    var settlement_trees_per_building: float = float(params.get("settlement_tree_count_per_building", 0.2))
    var urban_tree_buffer: float = float(params.get("urban_tree_buffer_distance", 50.0))
    var park_tree_density: int = int(params.get("park_tree_density", 6))
    var roadside_tree_spacing: float = float(params.get("roadside_tree_spacing", 40.0))

    # Biome & Rendering Parameters
    var biome_tree_types: Dictionary = params.get("forest_biome_tree_types", {})
    var use_external_assets: bool = bool(params.get("use_external_tree_assets", true))
    var tree_lod_distance: float = float(params.get("tree_lod_distance", 200.0))
    var debug_metrics: bool = bool(params.get("tree_debug_metrics", true))
    
    # Legacy compatibility for existing functions (will be removed after refactoring)
    var legacy_tree_target: int = forest_patch_count * trees_per_patch_target
    var legacy_patch_count: int = forest_patch_count

    var external_tree_variants: Array[Mesh] = []
    if _assets != null and _assets.has_method("enabled") and bool(_assets.call("enabled")):
        if _assets.has_method("get_mesh_variants"):
            var conifers: Array[Mesh] = _assets.call("get_mesh_variants", "trees_conifer")
            var broadleaf: Array[Mesh] = _assets.call("get_mesh_variants", "trees_broadleaf")
            var palms: Array[Mesh] = _assets.call("get_mesh_variants", "trees_palm")
            external_tree_variants.append_array(conifers)
            external_tree_variants.append_array(broadleaf)
            external_tree_variants.append_array(palms)

    var forest_root := Node3D.new()
    forest_root.name = "Forests"
    props_root.add_child(forest_root)

    # NEW: ALL TREES ARE NOW DESTRUCTIBLE!
    # Disabled non-destructible MultiMesh tree generation for full destructibility
    # (Comment these back in if performance is an issue)

    # var forest_stats: Dictionary = _build_forest_patches_fit_based(forest_root, rng, forest_patch_count, trees_per_patch_target, patch_radius_min, patch_radius_max, patch_placement_attempts, patch_placement_buffer, external_tree_variants, use_external_assets)
    # var random_stats: Dictionary = _build_random_trees(forest_root, rng, random_tree_count, random_tree_clearance_buffer, random_tree_slope_limit, random_tree_placement_attempts)
    # var settlement_stats: Dictionary = _build_settlement_trees(forest_root, rng, settlement_trees_per_building, urban_tree_buffer, park_tree_density, roadside_tree_spacing)

    var forest_stats: Dictionary = {"patches_created": 0, "total_trees_placed": 0, "patch_details": []}
    var random_stats: Dictionary = {"placed_trees": 0, "target_trees": 0, "failed_placements": 0}
    var settlement_stats: Dictionary = {"placed_trees": 0, "target_trees": 0, "buildings_processed": 0, "trees_placed": 0}

    # NEW: ALL trees are now individual destructible trees with collision and damage
    var destructible_tree_stats: Dictionary = _build_destructible_trees(forest_root, rng, params)

    # Log final metrics
    _log_tree_generation_metrics(forest_stats, random_stats, settlement_stats, debug_metrics)

    # Ponds (simple water discs)
    var pond_count: int = int(params.get("pond_count", 18))
    _build_ponds(props_root, rng, pond_count)

    return {"prop_lod_groups": _prop_lod_roots}

# --- Forest helpers ---

func _build_forest_external(root: Node3D, rng: RandomNumberGenerator, tree_target: int, patch_count: int, tree_variants: Array[Mesh]) -> void:
    # Create a MultiMesh for each tree variant (efficient batching)
    var mms: Array[MultiMeshInstance3D] = []
    for i in range(tree_variants.size()):
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = tree_variants[i]
        mm.instance_count = 0
        var inst := MultiMeshInstance3D.new()
        inst.multimesh = mm
        root.add_child(inst)
        mms.append(inst)

    # Pre-allocate transforms per variant (approx equal share)
    var transforms_per_variant: Array[Array] = []
    for _i in range(tree_variants.size()):
        transforms_per_variant.append([])

    # Drop trees in patches
    var placed: int = 0
    var tries: int = 0
    var max_tries: int = tree_target * 30
    while placed < tree_target and tries < max_tries:
        tries += 1
        var center: Vector3 = _terrain.find_land_point(rng, _sea_level + 4.0, 0.60, false)
        if center == Vector3.ZERO:
            continue
        if not _biome_allows_trees(center.x, center.z):
            continue
        # Patch radius scales with world size
        var patch_r: float = rng.randf_range(180.0, 520.0)
        var in_patch: int = int(float(tree_target) / float(max(1, patch_count)))
        in_patch = int(clamp(in_patch, 80, 650))
        for _t in range(in_patch):
            if placed >= tree_target:
                break
            var ang: float = rng.randf_range(0.0, TAU)
            var r: float = patch_r * sqrt(rng.randf())
            var x: float = center.x + cos(ang) * r
            var z: float = center.z + sin(ang) * r
            var h: float = _terrain.get_height_at(x, z)
            if h < _sea_level + 0.35:
                continue
            if _terrain.get_slope_at(x, z) > 32.0:
                continue
            if _too_close_to_settlements(Vector3(x, h, z), 250.0):
                continue
            if not _biome_allows_trees(x, z):
                continue

            # Check if in lake (avoid placing trees in lakes)
            if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
                if _world_ctx.is_in_lake(x, z, 5.0):  # 5m buffer from lake edge
                    continue

            var yaw: float = rng.randf_range(-PI, PI)
            var s: float = rng.randf_range(0.75, 1.55)
            var basis := Basis(Vector3.UP, yaw)
            basis = basis.scaled(Vector3(s, s, s))
            var t3 := Transform3D(basis, Vector3(x, h, z))

            var vi: int = rng.randi_range(0, tree_variants.size() - 1)
            transforms_per_variant[vi].append(t3)
            placed += 1

    # Upload transforms
    for i in range(mms.size()):
        var inst := mms[i]
        var list: Array = transforms_per_variant[i]
        inst.multimesh.instance_count = list.size()
        for j in range(list.size()):
            inst.multimesh.set_instance_transform(j, list[j])

func _build_forest_batched(root: Node3D, rng: RandomNumberGenerator, tree_target: int, patch_count: int) -> void:
    # Procedural tree mesh (fast + no external assets required)
    var tree_mesh := _make_simple_tree_mesh()
    var mmi := MultiMeshInstance3D.new()
    mmi.multimesh = MultiMesh.new()
    mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
    mmi.multimesh.mesh = tree_mesh
    mmi.multimesh.instance_count = tree_target
    root.add_child(mmi)

    var placed: int = 0
    var tries: int = 0
    var max_tries: int = tree_target * 40

    while placed < tree_target and tries < max_tries:
        tries += 1
        var center: Vector3 = _terrain.find_land_point(rng, _sea_level + 4.0, 0.65, false)
        if center == Vector3.ZERO:
            continue
        if not _biome_allows_trees(center.x, center.z):
            continue
        var patch_r: float = rng.randf_range(160.0, 520.0)
        var in_patch: int = int(float(tree_target) / float(max(1, patch_count)))
        in_patch = int(clamp(in_patch, 90, 720))
        for _t in range(in_patch):
            if placed >= tree_target:
                break
            var ang: float = rng.randf_range(0.0, TAU)
            var r: float = patch_r * sqrt(rng.randf())
            var x: float = center.x + cos(ang) * r
            var z: float = center.z + sin(ang) * r
            var h: float = _terrain.get_height_at(x, z)
            if h < _sea_level + 0.35:
                continue
            if _terrain.get_slope_at(x, z) > 34.0:
                continue
            if _too_close_to_settlements(Vector3(x, h, z), 260.0):
                continue
            if not _biome_allows_trees(x, z):
                continue

            # Check if in lake (avoid placing trees in lakes)
            if _world_ctx != null and _world_ctx.has_method("is_in_lake"):
                if _world_ctx.is_in_lake(x, z, 5.0):  # 5m buffer from lake edge
                    continue

            var yaw: float = rng.randf_range(-PI, PI)
            var s: float = rng.randf_range(0.80, 1.65)
            var basis := Basis(Vector3.UP, yaw)
            basis = basis.scaled(Vector3(s, s, s))
            var t3 := Transform3D(basis, Vector3(x, h, z))
            mmi.multimesh.set_instance_transform(placed, t3)
            placed += 1

    mmi.multimesh.instance_count = placed

func _make_simple_tree_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # Trunk
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.22
    trunk.bottom_radius = 0.32
    trunk.height = 3.8
    trunk.radial_segments = 8
    trunk.rings = 1
    # Leaves
    var crown := CylinderMesh.new()
    crown.top_radius = 0.02
    crown.bottom_radius = 1.8
    crown.height = 4.4
    crown.radial_segments = 10
    crown.rings = 1

    st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0.0, 1.9, 0.0)))
    st.append_from(crown, 0, Transform3D(Basis(), Vector3(0.0, 5.2, 0.0)))

    st.generate_normals()
    var mesh := st.commit()
    return mesh

# --- Ponds ---

func _build_ponds(root: Node3D, rng: RandomNumberGenerator, pond_count: int) -> void:
    if pond_count <= 0:
        return

    var ponds := Node3D.new()
    ponds.name = "Ponds"
    root.add_child(ponds)

    # Use the same ocean shader as rivers and lakes for consistency
    var mat := ShaderMaterial.new()
    mat.shader = preload("res://resources/shaders/ocean.gdshader")

    for _i in range(pond_count):
        var p: Vector3 = _terrain.find_land_point(rng, _sea_level + 8.0, 0.40, false)
        if p == Vector3.ZERO:
            continue
        if not _biome_allows_ponds(p.x, p.z):
            continue
        if _too_close_to_settlements(p, 420.0):
            continue

        var r: float = rng.randf_range(45.0, 120.0)
        var mi := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = r
        cyl.bottom_radius = r
        cyl.height = 0.1  # Much thinner to avoid floating effect
        cyl.radial_segments = 32
        cyl.rings = 1
        mi.mesh = cyl
        mi.material_override = mat
        # Position correctly: ground level minus half cylinder height, plus small offset
        var water_y: float = max(_sea_level + 0.3, p.y)
        mi.position = Vector3(p.x, water_y - (cyl.height * 0.5) + 0.05, p.z)
        ponds.add_child(mi)


func _biome_allows_trees(x: float, z: float) -> bool:
    if _biomes == null:
        return true
    if not _biomes.has_method("classify"):
        return true
    var b: String = str(_biomes.call("classify", x, z))
    # Trees can live in forest, wetland, and grassland; allow a little in farmland too.
    return not (b in ["Ocean", "Beach", "Rock", "Snow", "Desert"])


func _biome_allows_ponds(x: float, z: float) -> bool:
    if _biomes == null or not _biomes.has_method("classify"):
        return true
    var b: String = str(_biomes.call("classify", x, z))
    # Prefer wetlands/grasslands; avoid coast + dry/harsh biomes.
    return b in ["Wetland", "Grassland", "Forest", "Farm", ""]

# --- Shared helpers ---

func _too_close_to_settlements(p: Vector3, buffer: float) -> bool:
    for s in _settlements:
        if not (s is Dictionary):
            continue
        var c: Vector3 = (s as Dictionary).get("center", Vector3.ZERO)
        var r: float = float((s as Dictionary).get("radius", 300.0))
        if p.distance_to(c) < (r + buffer):
            return true
    return false

## Check if position is too close to any building
func _too_close_to_buildings(p: Vector3, buffer: float) -> bool:
    if not _world_ctx or not _world_ctx.has_data("building_positions"):
        return false

    var building_positions: Array = _world_ctx.get_data("building_positions")
    for building_data in building_positions:
        if not (building_data is Dictionary):
            continue
        var building_pos: Vector3 = building_data.get("position", Vector3.ZERO)
        var building_radius: float = float(building_data.get("radius", 15.0))
        # Check 2D distance (ignore Y axis) since buildings and trees are at different heights
        var dx = p.x - building_pos.x
        var dz = p.z - building_pos.z
        var distance_2d = sqrt(dx * dx + dz * dz)
        if distance_2d < (building_radius + buffer):
            return true
    return false

# --- NEW: Granular Tree Generation System ---

func _build_forest_patches_fit_based(root: Node3D, rng: RandomNumberGenerator, 
                                   patch_count: int, trees_per_patch_target: int,
                                   patch_radius_min: float, patch_radius_max: float,
                                   placement_attempts: int, placement_buffer: float,
                                   external_tree_variants: Array[Mesh], use_external_assets: bool) -> Dictionary:
    var forest_stats = {
        "patches_created": 0,
        "total_trees_placed": 0,
        "patch_details": []
    }
    
    if external_tree_variants.is_empty() or not use_external_assets:
        # Use procedural generation
        _build_forest_batched_procedural(root, rng, patch_count, trees_per_patch_target, 
                                        patch_radius_min, patch_radius_max, placement_attempts, 
                                        placement_buffer, forest_stats)
    else:
        # Use external assets with fit-based placement
        _build_forest_external_fit_based(root, rng, patch_count, trees_per_patch_target,
                                        patch_radius_min, patch_radius_max, placement_attempts,
                                        placement_buffer, external_tree_variants, forest_stats)
    
    return forest_stats

func _build_forest_batched_procedural(root: Node3D, rng: RandomNumberGenerator,
                                    patch_count: int, trees_per_patch_target: int,
                                    patch_radius_min: float, patch_radius_max: float,
                                    placement_attempts: int, placement_buffer: float,
                                    forest_stats: Dictionary) -> void:
    var mmi := MultiMeshInstance3D.new()
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    
    # Create procedural tree mesh with materials
    var tree_data = _create_procedural_tree_mesh()
    mm.mesh = tree_data["trunk_mesh"]
    
    # Apply tree materials to make trees visible
    mmi.material_override = tree_data["trunk_material"]
    
    # Create a second MultiMeshInstance for leaves with different material
    var leaves_mmi := MultiMeshInstance3D.new()
    var leaves_mm := MultiMesh.new()
    leaves_mm.transform_format = MultiMesh.TRANSFORM_3D
    leaves_mm.mesh = tree_data["leaves_mesh"]  # Use separate leaves mesh
    leaves_mmi.material_override = tree_data["leaves_material"]
    
    # Pre-allocate maximum possible instances
    var max_total_trees = patch_count * trees_per_patch_target
    mm.instance_count = max_total_trees
    leaves_mm.instance_count = max_total_trees
    
    # IMPORTANT: do NOT resize instance_count after writing transforms.
    # Start with 0 visible and increase once we know "placed".
    mm.visible_instance_count = 0
    leaves_mm.visible_instance_count = 0
    
    mmi.multimesh = mm
    leaves_mmi.multimesh = leaves_mm
    
    # Create a parent node for both tree parts
    var forest_node := Node3D.new()
    forest_node.name = "ForestProcedural"
    forest_node.add_child(mmi)
    forest_node.add_child(leaves_mmi)
    root.add_child(forest_node)
    

    
    var placed = 0
    
    for patch_i in range(patch_count):
        var patch_stats = _place_trees_in_patch_procedural(mm, leaves_mm, placed, rng, trees_per_patch_target,
                                                           patch_radius_min, patch_radius_max, 
                                                           placement_attempts, placement_buffer)
        forest_stats["patches_created"] += 1
        forest_stats["total_trees_placed"] += patch_stats["trees_placed"]
        forest_stats["patch_details"].append(patch_stats)
        placed += patch_stats["trees_placed"]
    
    # Show only the instances we filled
    mm.visible_instance_count = placed
    leaves_mm.visible_instance_count = placed

func _create_procedural_tree_mesh() -> Dictionary:
    # Better looking tree: cylinder trunk + cone leaves (as user preferred)
    var trunk_mesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.6
    trunk_mesh.bottom_radius = 0.9
    trunk_mesh.height = 6.0
    
    var leaves_mesh = CylinderMesh.new()  # Use cone for better tree shape  
    leaves_mesh.top_radius = 0.0
    leaves_mesh.bottom_radius = 3.5
    leaves_mesh.height = 10.0
    
    # Create trunk mesh (simple) - positioned at origin
    var trunk_final = ArrayMesh.new()
    var st_trunk = SurfaceTool.new()
    var trunk_transform := Transform3D.IDENTITY.translated(Vector3(0.0, trunk_mesh.height * 0.5, 0.0))
    st_trunk.append_from(trunk_mesh, 0, trunk_transform)
    st_trunk.generate_normals()
    var trunk = st_trunk.commit()
    
    # Create leaves mesh - positioned above trunk center (trunk height/2 + leaves offset)
    var leaves_final = ArrayMesh.new()
    var st_leaves = SurfaceTool.new()
    var leaves_base_y: float = trunk_mesh.height * 0.75
    var leaves_transform := Transform3D.IDENTITY.translated(
        Vector3(0.0, leaves_base_y + leaves_mesh.height * 0.5, 0.0)
    )
    st_leaves.append_from(leaves_mesh, 0, leaves_transform)
    st_leaves.generate_normals()
    var leaves = st_leaves.commit()
    
    # Create tree materials
    var trunk_material = StandardMaterial3D.new()
    trunk_material.albedo_color = Color(0.4, 0.2, 0.1)  # Brown trunk
    trunk_material.roughness = 0.9
    trunk_material.metallic = 0.0
    
    var leaves_material = StandardMaterial3D.new()
    leaves_material.albedo_color = Color(0.05, 0.4, 0.05)  # Dark green leaves
    leaves_material.roughness = 0.9
    leaves_material.metallic = 0.0
    
    return {"trunk_mesh": trunk, "leaves_mesh": leaves, "trunk_material": trunk_material, "leaves_material": leaves_material}

func _place_trees_in_patch_procedural(trunk_mm: MultiMesh, leaves_mm: MultiMesh, start_index: int, rng: RandomNumberGenerator,
                                    target_trees: int, patch_radius_min: float, patch_radius_max: float,
                                    max_attempts: int, placement_buffer: float) -> Dictionary:
    var patch_stats = {
        "center": Vector3.ZERO,
        "radius": 0.0,
        "trees_placed": 0,
        "target_trees": target_trees
    }
    
    # Find patch center
    var patch_center: Vector3 = _terrain.find_land_point(rng, _sea_level + 8.0, 0.40, false)
    if patch_center == Vector3.ZERO:
        return patch_stats
        
    # Generate patch radius
    var patch_radius: float = rng.randf_range(patch_radius_min, patch_radius_max)
    patch_stats["center"] = patch_center
    patch_stats["radius"] = patch_radius
    
    # Check if patch location is valid
    if _too_close_to_settlements(patch_center, placement_buffer):
        return patch_stats
        
    if not _biome_allows_trees(patch_center.x, patch_center.z):
        return patch_stats
    
    # Place trees in patch
    var trees_placed = 0
    var attempts = 0
    
    for tree_i in range(target_trees):
        if attempts >= max_attempts:
            break
            
        # Random position within patch
        var angle = rng.randf() * TAU
        var distance = sqrt(rng.randf()) * patch_radius
        var tree_pos = patch_center + Vector3(
            cos(angle) * distance,
            0.0,
            sin(angle) * distance
        )
        
        # Validate position
        var height = _terrain.get_height_at(tree_pos.x, tree_pos.z)
        if height < _sea_level + 0.35:
            attempts += 1
            continue
            
        if _terrain.get_slope_at(tree_pos.x, tree_pos.z) > 34.0:
            attempts += 1
            continue
            
        if _too_close_to_settlements(tree_pos, 50.0):
            attempts += 1
            continue
            
        if _world_ctx and _world_ctx.is_in_lake(tree_pos.x, tree_pos.z, 5.0):
            attempts += 1
            continue
            
        # Place tree
        tree_pos.y = height
        var scale = rng.randf_range(0.65, 1.35)
        var t3 = Transform3D.IDENTITY
        t3 = t3.scaled(Vector3.ONE * scale)
        t3.origin = tree_pos
        t3 = t3.rotated_local(Vector3.UP, rng.randf() * TAU)
        
        # Set transform for both trunk and leaves MultiMeshInstances
        var instance_idx = start_index + trees_placed
        trunk_mm.set_instance_transform(instance_idx, t3)
        leaves_mm.set_instance_transform(instance_idx, t3)
        
        # DEBUG: Log tree placement
#        if trees_placed < 3:  # Only log first few trees to avoid spam
#            print("DEBUG: Placed tree at position: ", tree_pos, " with scale: ", scale)
        
        trees_placed += 1
        attempts = 0  # Reset attempts on successful placement
    
    patch_stats["trees_placed"] = trees_placed
    return patch_stats

func _build_forest_external_fit_based(root: Node3D, rng: RandomNumberGenerator,
                                    patch_count: int, trees_per_patch_target: int,
                                    patch_radius_min: float, patch_radius_max: float,
                                    placement_attempts: int, placement_buffer: float,
                                    external_tree_variants: Array[Mesh], forest_stats: Dictionary) -> void:
    # Create a MultiMesh for each tree variant (efficient batching)
    var mms: Array[MultiMeshInstance3D] = []
    var mms_mm: Array[MultiMesh] = []
    
    for i in range(min(external_tree_variants.size(), 12)):
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = external_tree_variants[i]
        mm.instance_count = 0
        var inst := MultiMeshInstance3D.new()
        inst.multimesh = mm
        root.add_child(inst)
        mms.append(inst)
        mms_mm.append(mm)
    
    var transforms_per_variant: Array[Array] = []
    for i in range(mms.size()):
        transforms_per_variant.append([])
    
    var total_placed = 0
    
    for patch_i in range(patch_count):
        # Find patch center
        var patch_center: Vector3 = _terrain.find_land_point(rng, _sea_level + 8.0, 0.40, false)
        if patch_center == Vector3.ZERO:
            continue
            
        # Generate patch radius
        var patch_radius: float = rng.randf_range(patch_radius_min, patch_radius_max)
        
        # Check if patch location is valid
        if _too_close_to_settlements(patch_center, placement_buffer):
            continue
            
        if not _biome_allows_trees(patch_center.x, patch_center.z):
            continue
        
        # Place trees in patch
        var patch_placed = 0
        var attempts = 0
        
        for tree_i in range(trees_per_patch_target):
            if attempts >= placement_attempts:
                break
                
            # Random position within patch
            var angle = rng.randf() * TAU
            var distance = sqrt(rng.randf()) * patch_radius
            var tree_pos = patch_center + Vector3(
                cos(angle) * distance,
                0.0,
                sin(angle) * distance
            )
            
            # Validate position
            var height = _terrain.get_height_at(tree_pos.x, tree_pos.z)
            if height < _sea_level + 0.35:
                attempts += 1
                continue
                
            if _terrain.get_slope_at(tree_pos.x, tree_pos.z) > 32.0:
                attempts += 1
                continue
                
            if _too_close_to_settlements(tree_pos, 50.0):
                attempts += 1
                continue
                
            if _world_ctx and _world_ctx.is_in_lake(tree_pos.x, tree_pos.z, 5.0):
                attempts += 1
                continue
            
            # Select tree variant
            var vi: int = rng.randi_range(0, external_tree_variants.size() - 1)
            if vi >= mms.size():
                vi = 0
                
            # Create transform
            var scale = rng.randf_range(0.75, 1.55)
            var t3 = Transform3D.IDENTITY
            t3 = t3.scaled(Vector3.ONE * scale)
            t3.origin = Vector3(tree_pos.x, height, tree_pos.z)
            t3 = t3.rotated_local(Vector3.UP, rng.randf() * TAU)
            
            transforms_per_variant[vi].append(t3)
            patch_placed += 1
            attempts = 0  # Reset attempts on successful placement
        
        total_placed += patch_placed
        forest_stats["patches_created"] += 1
        forest_stats["total_trees_placed"] += patch_placed
    
    # Batch upload transforms
    for i in range(mms.size()):
        if transforms_per_variant[i].size() > 0:
            mms_mm[i].instance_count = transforms_per_variant[i].size()
            for j in range(transforms_per_variant[i].size()):
                mms_mm[i].set_instance_transform(j, transforms_per_variant[i][j])

func _build_random_trees(root: Node3D, rng: RandomNumberGenerator, target_count: int,
                         clearance_buffer: float, slope_limit: float, placement_attempts: int) -> Dictionary:
    var random_stats = {
        "target_trees": target_count,
        "placed_trees": 0,
        "failed_placements": 0
    }
    
    if target_count <= 0:
        return random_stats
    
    var random_trees_root = Node3D.new()
    random_trees_root.name = "RandomTrees"
    root.add_child(random_trees_root)
    
    # Create procedural mesh for random trees
    var tree_data = _create_procedural_tree_mesh()
    var mmi = MultiMeshInstance3D.new()
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = tree_data["trunk_mesh"]
    mm.instance_count = target_count
    mm.visible_instance_count = 0
    mmi.multimesh = mm
    mmi.material_override = tree_data["trunk_material"]
    random_trees_root.add_child(mmi)
    
    # Create leaves for random trees
    var leaves_mmi = MultiMeshInstance3D.new()
    var leaves_mm = MultiMesh.new()
    leaves_mm.transform_format = MultiMesh.TRANSFORM_3D
    leaves_mm.mesh = tree_data["leaves_mesh"]
    leaves_mm.instance_count = target_count
    leaves_mm.visible_instance_count = 0
    leaves_mmi.multimesh = leaves_mm
    leaves_mmi.material_override = tree_data["leaves_material"]
    random_trees_root.add_child(leaves_mmi)
    
    for i in range(target_count):
        var placed = _try_place_random_tree(mm, leaves_mm, i, rng, clearance_buffer, slope_limit, placement_attempts)
        if placed:
            random_stats["placed_trees"] += 1
        else:
            random_stats["failed_placements"] += 1
    
    # Set final instance count for both trunk and leaves
    mm.instance_count = random_stats["placed_trees"]
    leaves_mm.instance_count = random_stats["placed_trees"]
    return random_stats

func _try_place_random_tree(trunk_mm: MultiMesh, leaves_mm: MultiMesh, index: int, rng: RandomNumberGenerator,
                           clearance_buffer: float, slope_limit: float, placement_attempts: int) -> bool:
    for attempt in range(placement_attempts):
        # Find random land point
        var pos = _terrain.find_land_point(rng, _sea_level + 8.0, 0.40, false)
        if pos == Vector3.ZERO:
            continue
            
        # Check slope
        if _terrain.get_slope_at(pos.x, pos.z) > slope_limit:
            continue
            
        # Check clearance from all features
        if not _has_clearance_from_features(pos, clearance_buffer):
            continue
            
        # Place tree
        var height = _terrain.get_height_at(pos.x, pos.z)
        pos.y = height
        var scale = rng.randf_range(0.65, 1.35)
        var t3 = Transform3D.IDENTITY
        t3 = t3.scaled(Vector3.ONE * scale)
        t3.origin = pos
        t3 = t3.rotated_local(Vector3.UP, rng.randf() * TAU)
        
        # Set transform for both trunk and leaves
        trunk_mm.set_instance_transform(index, t3)
        leaves_mm.set_instance_transform(index, t3)
        return true
    
    return false

func _build_settlement_trees(root: Node3D, rng: RandomNumberGenerator,
                           trees_per_building: float, urban_buffer: float,
                           park_density: int, roadside_spacing: float) -> Dictionary:
    var settlement_stats = {
        "buildings_processed": 0,
        "trees_placed": 0
    }
    
    # Simple implementation - place trees near settlement centers
    # In future, this could integrate with actual building positions
    if _settlements.is_empty():
        return settlement_stats
    
    var settlement_trees_root = Node3D.new()
    settlement_trees_root.name = "SettlementTrees"
    root.add_child(settlement_trees_root)
    
    # Create procedural mesh for settlement trees
    var tree_data = _create_procedural_tree_mesh()
    var mmi = MultiMeshInstance3D.new()
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = tree_data["trunk_mesh"]
    mm.instance_count = 100  # Maximum expected settlement trees
    mmi.multimesh = mm
    mmi.material_override = tree_data["trunk_material"]
    settlement_trees_root.add_child(mmi)
    
    # Create leaves for settlement trees
    var leaves_mmi = MultiMeshInstance3D.new()
    var leaves_mm = MultiMesh.new()
    leaves_mm.transform_format = MultiMesh.TRANSFORM_3D
    leaves_mm.mesh = tree_data["leaves_mesh"]
    leaves_mm.instance_count = 100  # Maximum expected settlement trees
    leaves_mmi.multimesh = leaves_mm
    leaves_mmi.material_override = tree_data["leaves_material"]
    settlement_trees_root.add_child(leaves_mmi)
    
    var placed = 0
    for settlement in _settlements:
        if not (settlement is Dictionary):
            continue
            
        var center = settlement.get("center", Vector3.ZERO)
        var buildings = settlement.get("building_count", 10)
        settlement_stats["buildings_processed"] += buildings
        
        var trees_for_settlement = int(buildings * trees_per_building)
        for _i in range(trees_for_settlement):
            if placed >= 100:
                break
                
            # Place tree near settlement center with urban buffer
            var angle = rng.randf() * TAU
            var distance = rng.randf_range(urban_buffer, urban_buffer + 50.0)
            var tree_pos = center + Vector3(
                cos(angle) * distance,
                0.0,
                sin(angle) * distance
            )
            
            # Validate position
            var height = _terrain.get_height_at(tree_pos.x, tree_pos.z)
            if height < _sea_level + 0.35:
                continue
                
            if _terrain.get_slope_at(tree_pos.x, tree_pos.z) > 34.0:
                continue
            
            # Place tree
            tree_pos.y = height
            var scale = rng.randf_range(0.8, 1.8)
            var t3 = Transform3D.IDENTITY
            t3 = t3.scaled(Vector3.ONE * scale)
            t3.origin = tree_pos
            t3 = t3.rotated_local(Vector3.UP, rng.randf() * TAU)
            
            mm.set_instance_transform(placed, t3)
            leaves_mm.set_instance_transform(placed, t3)
            placed += 1
            settlement_stats["trees_placed"] += 1
    
    # Set final instance count
    mm.instance_count = placed
    return settlement_stats

func _has_clearance_from_features(pos: Vector3, buffer: float) -> bool:
    # Check clearance from settlements
    if _too_close_to_settlements(pos, buffer):
        return false
        
    # Check clearance from lakes
    if _world_ctx and _world_ctx.is_in_lake(pos.x, pos.z, buffer):
        return false
    
    # Check clearance from roads (simplified - could be enhanced with actual road data)
    # For now, just check if position is too close to certain terrain features
    
    return true

func _log_tree_generation_metrics(forest_stats: Dictionary, random_stats: Dictionary, 
                                 settlement_stats: Dictionary, debug_enabled: bool) -> void:
    if not debug_enabled:
        return
        
    print("\n=== TREE GENERATION METRICS ===")
    print("Forest Patches:")
    print("  Patches Created: ", forest_stats["patches_created"])
    print("  Trees Placed: ", forest_stats["total_trees_placed"])
    
    print("Random Filler Trees:")
    print("  Target: ", random_stats["target_trees"])
    print("  Placed: ", random_stats["placed_trees"])
    print("  Failed: ", random_stats["failed_placements"])
    
    print("Settlement Trees:")
    print("  Buildings Processed: ", settlement_stats["buildings_processed"])
    print("  Trees Placed: ", settlement_stats["trees_placed"])
    
    var total_trees = forest_stats["total_trees_placed"] + random_stats["placed_trees"] + settlement_stats["trees_placed"]
    print("\nTOTAL TREES PLACED: ", total_trees)
    print("===============================\n")


## Build destructible trees in player flight areas
func _build_destructible_trees(root: Node3D, rng: RandomNumberGenerator, params: Dictionary) -> Dictionary:
    var stats: Dictionary = {
        "target_trees": 0,
        "placed_trees": 0,
        "failed_placements": 0
    }
    
    # ALL TREES ARE NOW DESTRUCTIBLE!
    # Increased count and radius to cover entire map (was 500 trees in 1000m radius)
    var destructible_tree_count: int = int(params.get("destructible_tree_count", 6000))
    stats["target_trees"] = destructible_tree_count

    # Cover the entire playable map (terrain is 4000x4000, so use 2000m radius = full map)
    var area_radius: float = float(params.get("destructible_tree_area_radius", 2000.0))
    
    var placed = 0
    var attempts = 0
    var max_attempts = destructible_tree_count * 20  # Allow more attempts to find valid spots
    
    print("🌲 ALL TREES DESTRUCTIBLE: Generating %d trees across ENTIRE MAP (%.0fm radius from center)" % [destructible_tree_count, area_radius])

    while placed < destructible_tree_count and attempts < max_attempts:
        attempts += 1

        # Generate random position in the circular area
        var angle = rng.randf() * TAU
        var distance = rng.randf() * area_radius
        var pos = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
        
        # Get terrain height at position
        var height = _terrain.get_height_at(pos.x, pos.z)
        
        # Skip if underwater
        if height < _sea_level - 0.5:
            continue
            
        # Skip if slope is too steep
        if _terrain.get_slope_at(pos.x, pos.z) > 34.0:
            continue
            
        # Skip if too close to settlements
        if _too_close_to_settlements(pos, 50.0):
            continue

        # Skip if too close to buildings
        if _too_close_to_buildings(pos, 8.0):
            continue

        # Skip if in lake
        if _world_ctx and _world_ctx.is_in_lake(pos.x, pos.z, 5.0):
            continue
            
        # Skip if not in a biome that allows trees
        if not _biome_allows_trees(pos.x, pos.z):
            continue
            
        # Create a destructible tree with collision and health
        var tree_node = _create_destructible_tree(pos.x, height, pos.z, rng)
        if tree_node:
            root.add_child(tree_node)
            tree_node.owner = root
            # NOTE: TreeDamageable initialization happens automatically via _ready()
            # No need to call initialize_damageable() manually

            # Add collision and damage capability using CollisionManager immediately
            # Use CollisionManager for consistent collision management
            print("🔍 TREE %d: '%s' - Adding collision..." % [placed, tree_node.name])
            print("  - CollisionManager exists: %s" % (CollisionManager != null))
            if CollisionManager:
                print("  - CollisionManager type: %s" % CollisionManager.get_class())
                if placed < 5:
                    print("  - Calling add_collision_to_object for '%s'" % tree_node.name)
                CollisionManager.add_collision_to_object(tree_node, "tree")
                if placed < 5:
                    print("🌲 DEBUG: Created destructible tree '%s' at (%.1f, %.1f, %.1f) with collision" % [tree_node.name, pos.x, height, pos.z])
            elif CollisionAdder:
                # Fallback to CollisionAdder if CollisionManager isn't available
                CollisionAdder.add_collision_to_tree(tree_node, "tree")
                if placed < 5:
                    print("🌲 DEBUG: Created destructible tree '%s' at (%.1f, %.1f, %.1f) with CollisionAdder" % [tree_node.name, pos.x, height, pos.z])
            else:
                print("⚠️ WARNING: No CollisionManager or CollisionAdder found!")

            placed += 1
            stats["placed_trees"] += 1
        else:
            stats["failed_placements"] += 1

    print("🌳 ALL TREES DESTRUCTIBLE: Placed %d/%d trees across ENTIRE MAP" % [stats["placed_trees"], stats["target_trees"]])

    # Show coverage info
    if stats["placed_trees"] > 0:
        print("🗺️ Full map coverage: 0,0 ± %.0fm radius (all trees shootable!)" % area_radius)

    return stats

## Get tree species based on random selection
func _get_tree_species(rng: RandomNumberGenerator) -> String:
    # Tree species with their probability weights
    var species = [
        {"name": "Pine", "weight": 25},
        {"name": "Oak", "weight": 20},
        {"name": "Birch", "weight": 15},
        {"name": "Maple", "weight": 15},
        {"name": "Spruce", "weight": 10},
        {"name": "Fir", "weight": 8},
        {"name": "Cedar", "weight": 4},
        {"name": "Ash", "weight": 3}
    ]
    
    # Calculate total weight
    var total_weight = 0
    for s in species:
        total_weight += s.weight
    
    # Select species based on weight
    var random_value = rng.randf() * total_weight
    var current_weight = 0
    
    for s in species:
        current_weight += s.weight
        if random_value <= current_weight:
            return s.name
    
    # Fallback to Pine if something goes wrong
    return "Pine"

## Create a destructible tree with collision and health
func _create_destructible_tree(x: float, y: float, z: float, rng: RandomNumberGenerator) -> Node3D:
    # Create a Node3D for the tree (CollisionManager will add collision separately)
    var tree_body = Node3D.new()
    var tree_species = _get_tree_species(rng)
    tree_body.name = "DestructibleTree_%s_%d_%d" % [tree_species, int(x), int(z)]
    tree_body.position = Vector3(x, y, z)

    # Create trunk
    var trunk_mi = MeshInstance3D.new()
    trunk_mi.name = "Trunk"
    trunk_mi.position = Vector3(0, 6.0, 0)  # Lift trunk so bottom is at ground (height 12/2 = 6)

    # Create trunk mesh (cylinder)
    var trunk_mesh = CylinderMesh.new()
    trunk_mesh.top_radius = 0.6  # Doubled from 0.3
    trunk_mesh.bottom_radius = 1.0  # Doubled from 0.5
    trunk_mesh.height = 12.0  # Doubled from 6.0
    trunk_mi.mesh = trunk_mesh

    # Create trunk material
    var trunk_mat = StandardMaterial3D.new()
    trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)  # Brown bark
    trunk_mesh.material = trunk_mat  # Set on mesh surface, not override

    # Create leaves
    var leaves_mi = MeshInstance3D.new()
    leaves_mi.name = "Leaves"
    leaves_mi.position = Vector3(0, 17.0, 0)  # Position on top of trunk (trunk top at 12, cone height 10, center at 17)

    # Leaves (cone-shaped like pine/fir trees)
    var leaves_mesh = CylinderMesh.new()
    leaves_mesh.top_radius = 0.0        # Point at top = cone shape
    leaves_mesh.bottom_radius = 3.5     # Wide at base (matching old procedural trees)
    leaves_mesh.height = 10.0           # Taller canopy (matching old trees)
    leaves_mesh.radial_segments = 8     # Fewer segments = more angular/stylized
    leaves_mesh.rings = 1               # Simple cone, no subdivision
    leaves_mi.mesh = leaves_mesh

    # Create leaves material (purple for Birch/Oak to distinguish tree types, green for conifers)
    var leaves_mat = StandardMaterial3D.new()
    if tree_species in ["Birch", "Oak", "Maple"]:
        leaves_mat.albedo_color = Color(0.35, 0.08, 0.35)  # Purple leaves for broadleaf trees
    else:
        leaves_mat.albedo_color = Color(0.08, 0.35, 0.12)  # Dark green leaves for conifers
    # Set material on MESH surface (not override) so damage system can find original color
    leaves_mesh.material = leaves_mat

    # Add visual components to the tree body (CollisionManager will add collision separately)
    tree_body.add_child(trunk_mi)
    trunk_mi.owner = tree_body
    tree_body.add_child(leaves_mi)
    leaves_mi.owner = tree_body

    # Add damageable component to make the tree destructible
    var damageable_obj = BuildingDamageableObject.new()
    damageable_obj.name = "TreeDamageable"
    # CRITICAL: Set building_type to match tree species BEFORE adding to tree
    # This ensures _ready() uses correct logic (tree vs building)
    damageable_obj.building_type = tree_species.to_lower()  # e.g., "pine", "oak", "maple"
    # Now add to tree - _ready() will auto-call initialize_damageable() with correct params
    tree_body.add_child(damageable_obj)
    damageable_obj.owner = tree_body

    # Add size variation (match old MultiMesh tree variety)
    var tree_scale = rng.randf_range(0.75, 1.55)  # 2x size range (small to large)
    tree_body.scale = Vector3(tree_scale, tree_scale, tree_scale)

    return tree_body
