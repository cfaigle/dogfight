extends WorldComponentBase
class_name OrganicBuildingPlacementComponent

## Places buildings on pre-generated plots
## Reuses existing collision system and building styles
## Priority: 65 (same as old settlement_buildings)

func get_priority() -> int:
    return 65

func get_dependencies() -> Array[String]:
    return ["building_plots", "heightmap"]

func get_optional_params() -> Dictionary:
    return {
        "building_count": 5000,  # Total number of buildings to place
        "building_placement_randomness": 0.7,  # How random vs systematic placement is (0.0 = systematic, 1.0 = fully random)
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx == null or ctx.terrain_generator == null:
        push_error("OrganicBuildingPlacementComponent: missing ctx/terrain_generator")
        return

    if not ctx.has_data("building_plots"):
        push_warning("OrganicBuildingPlacementComponent: no building_plots available")
        return

    var plots: Array = ctx.get_data("building_plots")

    var buildings_layer := ctx.get_layer("Buildings")

    if buildings_layer == null:
        push_error("OrganicBuildingPlacementComponent: Buildings layer is null!")
        return

    var placed_count := 0

    # Get desired building count from params
    var target_building_count: int = int(params.get("building_count", 5000))
    var max_building_count: int = min(target_building_count, plots.size())

    print("🏗️ OrganicBuildingPlacement: Attempting to place ", max_building_count, " buildings from ", plots.size(), " available plots")

    # Randomly select plots for building placement
    var plots_to_use: Array = plots.duplicate()
    plots_to_use.shuffle()  # Randomize the order

    for i in range(max_building_count):
        var plot = plots_to_use[i]

        # Create building
        var building := _place_building_on_plot(plot, rng)
        if building != null:
            buildings_layer.add_child(building)
            placed_count += 1

    print("🏗️ OrganicBuildingPlacement: Successfully placed ", placed_count, " buildings from ", max_building_count, " attempts")

func _place_building_on_plot(plot: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Get terrain height at plot position
    var height := ctx.terrain_generator.get_height_at(plot.position.x, plot.position.z)
    var final_pos := Vector3(plot.position.x, height, plot.position.z)

    # Skip building if underwater
    var sea_level := float(ctx.params.get("sea_level", 0.0))
    if height < sea_level - 0.5:  # Allow slightly below sea level
        return null

    # Try to create parametric building if parametric system is available
    if ctx.parametric_system != null:
        print("🏗️ Using parametric building system for plot at (", plot.position.x, ",", plot.position.z, ")")
        var building = _create_parametric_building(plot, final_pos, rng)
        if building != null:
            print("   ✅ Successfully created parametric building")
        else:
            print("   ❌ Failed to create parametric building, falling back to simple")
            building = _create_simple_building(plot, final_pos, rng)
        return building
    else:
        print("⚠️ Parametric system not available, using simple building")
        # Fallback to simple building
        return _create_simple_building(plot, final_pos, rng)

func _create_building_from_kit(plot: Dictionary, pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Map plot density to settlement style
    var style := "hamlet"
    match plot.get("density_class", "rural"):
        "urban_core":
            style = "city"
        "urban":
            style = "city"
        "suburban":
            style = "town"
        "rural":
            style = "hamlet"

    # Allow industrial buildings in commercial/mixed zones
    if plot.get("building_type", "residential") == "commercial" and rng.randf() < 0.2:
        style = "industrial"

    # Get building kit for this style
    var kit: Dictionary = ctx.building_kits.get(style, ctx.building_kits.get("town", {}))
    if kit.is_empty():
        return _create_simple_building(plot, pos, rng)

    # Calculate building dimensions
    var base_width: float = plot.lot_width
    var base_depth: float = plot.lot_depth
    var building_height := 0.0

    match plot.height_category:
        "tall":
            building_height = rng.randf_range(18.0, 36.0)
        "medium":
            building_height = rng.randf_range(9.0, 15.0)
        "low":
            building_height = rng.randf_range(3.0, 6.0)

    # Try external mesh first (if available)
    var external_meshes: Array = kit.get("external_meshes", [])
    if external_meshes.size() > 0 and rng.randf() < 0.3:  # 30% chance for external mesh
        var mesh_variant = external_meshes[rng.randi() % external_meshes.size()]
        var building := MeshInstance3D.new()
        building.mesh = mesh_variant.get("mesh")
        building.position = pos
        building.rotation.y = plot.yaw
        var scale_factor := minf(base_width / 12.0, base_depth / 12.0)
        building.scale = Vector3(scale_factor, building_height / 12.0, scale_factor)
        building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        return building

    # Otherwise use procedural variant (all 27+ building types)
    var variants: Array = kit.get("procedural_variants", [])
    if variants.is_empty():
        return _create_simple_building(plot, pos, rng)

    # Pick weighted random variant
    var total_weight := 0.0
    for v in variants:
        total_weight += float(v.get("weight", 1.0))

    var pick := rng.randf() * total_weight
    var running_weight := 0.0
    var chosen_variant: Dictionary = variants[0]

    for v in variants:
        running_weight += float(v.get("weight", 1.0))
        if pick <= running_weight:
            chosen_variant = v
            break

    # Build the variant
    var building := _build_procedural_variant(chosen_variant, base_width, base_depth, building_height, kit, pos, plot.yaw, rng)
    return building

func _build_procedural_variant(variant: Dictionary, base_width: float, base_depth: float, base_height: float, kit: Dictionary, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Apply variant multipliers
    var sx: float = base_width * float(variant.get("sx_mul", 1.0))
    var sz: float = base_depth * float(variant.get("sz_mul", 1.0))
    var sy: float = base_height * float(variant.get("sy_mul", 1.0))

    # Force square if needed
    if bool(variant.get("force_square", false)):
        var s := minf(sx, sz)
        sx = s
        sz = s

    # Get meshes
    var wall_mesh: Mesh = variant.get("wall_mesh")
    var roof_mesh: Mesh = variant.get("roof_mesh")
    var roof_kind: String = String(variant.get("roof_kind", "gable"))

    # Create wall - unit cube is centered, so offset by half height
    var building := MeshInstance3D.new()
    building.mesh = wall_mesh
    building.position = pos + Vector3(0, sy * 0.5, 0)  # Center of building at ground + half height
    building.scale = Vector3(sx, sy, sz)
    building.rotation.y = yaw
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    # Set wall material
    var wall_mat: Material = kit.get("wall_material")
    if wall_mat != null:
        building.material_override = wall_mat

    # Add roof as child (relative to building center)
    if roof_mesh != null:
        var roof := MeshInstance3D.new()
        roof.mesh = roof_mesh
        var roof_height := sy * 0.15
        if roof_kind == "flat":
            roof_height = sy * 0.08
        roof.position = Vector3(0, sy * 0.5 + roof_height * 0.5, 0)
        roof.scale = Vector3(sx * 1.05, roof_height, sz * 1.05)
        var roof_mat: Material = kit.get("roof_material")
        if roof_mat != null:
            roof.material_override = roof_mat
        building.add_child(roof)

    return building

func _create_parametric_building(plot: Dictionary, pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Determine building type from plot
    var building_type: String = plot.get("building_type", "residential")

    # Map to parametric style
    var parametric_style := "ww2_european"
    if building_type == "commercial":
        parametric_style = "american_art_deco" if rng.randf() < 0.5 else "ww2_european"
    elif building_type == "rural":
        parametric_style = "ww2_european"

    # Calculate building dimensions
    var width: float = plot.lot_width
    var depth: float = plot.lot_depth
    var building_height := 0.0
    var floors := 1

    match plot.height_category:
        "tall":
            building_height = rng.randf_range(18.0, 36.0)
            floors = int(building_height / 4.0)
        "medium":
            building_height = rng.randf_range(9.0, 15.0)
            floors = int(building_height / 4.0)
        "low":
            building_height = rng.randf_range(3.0, 6.0)
            floors = max(1, int(building_height / 4.0))

    # Generate parametric mesh
    var mesh: Mesh = ctx.parametric_system.create_parametric_building(
        building_type,
        parametric_style,
        width,
        depth,
        building_height,
        floors,
        2  # quality level (0=best, 2=lowest)
    )

    if mesh == null:
        # Fallback to simple building
        return _create_simple_building(plot, pos, rng)

    # Create mesh instance
    var building := MeshInstance3D.new()
    building.mesh = mesh
    building.position = pos
    building.rotation.y = plot.yaw
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    return building

func _create_simple_building(plot: Dictionary, pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
    var building := MeshInstance3D.new()
    var mesh := _generate_building_mesh(plot, rng)
    building.mesh = mesh
    building.position = pos
    building.rotation.y = plot.yaw
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    return building

func _generate_building_mesh(plot: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
    # Simple box building for now (can be enhanced with parametric system later)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()

    # Building dimensions - clamp to reasonable sizes
    var base_width: float = clampf(plot.lot_width, 4.0, 20.0)
    var base_depth: float = clampf(plot.lot_depth, 4.0, 20.0)

    # Height based on category
    var height := 0.0
    match plot.height_category:
        "tall":
            height = rng.randf_range(15.0, 30.0)
        "medium":
            height = rng.randf_range(8.0, 14.0)
        "low":
            height = rng.randf_range(3.0, 6.0)

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
    var base_idx := 0
    vertices.append_array([v0, v1, v5, v4])
    normals.append_array([Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1), Vector3(0, 0, -1)])
    indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])

    # Back face (+Z)
    base_idx = vertices.size()
    vertices.append_array([v2, v3, v7, v6])
    normals.append_array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
    indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])

    # Left face (-X)
    base_idx = vertices.size()
    vertices.append_array([v3, v0, v4, v7])
    normals.append_array([Vector3(-1, 0, 0), Vector3(-1, 0, 0), Vector3(-1, 0, 0), Vector3(-1, 0, 0)])
    indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])

    # Right face (+X)
    base_idx = vertices.size()
    vertices.append_array([v1, v2, v6, v5])
    normals.append_array([Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 0)])
    indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])

    # Top face (+Y)
    base_idx = vertices.size()
    vertices.append_array([v4, v5, v6, v7])
    normals.append_array([Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)])
    indices.append_array([base_idx, base_idx+1, base_idx+2, base_idx, base_idx+2, base_idx+3])

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
