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
            print("   ❌ Failed to create parametric building, falling back to building kits")
            # Try building kits as secondary option
            if ctx.building_kits.size() > 0:
                building = _create_building_from_kit(plot, final_pos, rng)
                if building != null:
                    print("   ✅ Successfully created building kit building")
                else:
                    print("   ❌ Failed to create building kit building, falling back to simple")
                    building = _create_simple_building(plot, final_pos, rng)
            else:
                building = _create_simple_building(plot, final_pos, rng)
        return building
    elif ctx.building_kits.size() > 0:
        # Try to use building kits if parametric system is not available but kits exist
        print("🔧 Using building kit system for plot at (", plot.position.x, ",", plot.position.z, ")")
        var building = _create_building_from_kit(plot, final_pos, rng)
        if building != null:
            print("   ✅ Successfully created building kit building")
        else:
            print("   ❌ Failed to create building kit building, falling back to simple")
            building = _create_simple_building(plot, final_pos, rng)
        return building
    else:
        print("⚠️ No building systems available, using simple building")
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
    var parametric_style: String = plot.get("building_type", "residential")  # Use the specific type as style

    # Check if this is a special building type that needs specific geometry
    var special_building_mesh: Mesh = _create_special_building_geometry(parametric_style, plot, rng)
    if special_building_mesh != null:
        print("   🏯 Created special building - type:", parametric_style)
        var building := MeshInstance3D.new()
        building.mesh = special_building_mesh
        building.position = pos
        building.rotation.y = plot.yaw
        building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        return building

    # For regular buildings, use the parametric system with more appropriate style selection
    var specific_building_type: String = building_type

    # Select a specific building style with more variety based on plot characteristics
    # Use more varied styles based on plot characteristics
    match plot.density_class:
        "urban_core":
            # Urban cores get more diverse styles
            var urban_styles = ["american_art_deco", "industrial_modern", "ww2_european", "victorian_mansion", "factory_building", "train_station"]
            parametric_style = urban_styles[rng.randi() % urban_styles.size()]
        "urban":
            var urban_styles = ["american_art_deco", "ww2_european", "industrial_modern", "victorian_mansion", "market_stall", "church"]
            parametric_style = urban_styles[rng.randi() % urban_styles.size()]
        "suburban":
            var sub_styles = ["ww2_european", "american_art_deco", "stone_cottage", "timber_cabin", "white_stucco_house"]
            parametric_style = sub_styles[rng.randi() % sub_styles.size()]
        "rural":
            var rural_styles = ["ww2_european", "industrial_modern", "stone_cottage", "timber_cabin", "log_chalet", "barn", "windmill", "blacksmith"]
            parametric_style = rural_styles[rng.randi() % rural_styles.size()]
        _:
            # Default styles
            var default_styles = ["ww2_european", "american_art_deco", "industrial_modern"]
            parametric_style = default_styles[rng.randi() % default_styles.size()]

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
        specific_building_type,
        parametric_style,
        width,
        depth,
        building_height,
        floors,
        2  # quality level (0=best, 2=lowest)
    )

    if mesh == null:
        print("⚠️ Failed to create parametric building for type:", specific_building_type, " style:", parametric_style)
        # Fallback to simple building
        return _create_simple_building(plot, pos, rng)

    # Create mesh instance
    var building := MeshInstance3D.new()
    building.mesh = mesh
    building.position = pos
    building.rotation.y = plot.yaw
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    # Debug: Print building info
    print("   🏢 Created parametric building - type:", specific_building_type, " style:", parametric_style, " dims:", width, "x", depth, " floors:", floors)

    return building

# Create specific geometry for special building types
func _create_special_building_geometry(building_style: String, plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    match building_style:
        "windmill":
            return _create_windmill_geometry(plot, rng)
        "lighthouse":
            return _create_lighthouse_geometry(plot, rng)
        "barn":
            return _create_barn_geometry(plot, rng)
        "church":
            return _create_church_geometry(plot, rng)
        "castle_keep":
            return _create_castle_geometry(plot, rng)
        "blacksmith":
            return _create_blacksmith_geometry(plot, rng)
        "factory_building":
            return _create_factory_geometry(plot, rng)
        "house":
            return _create_house_geometry(plot, rng)
        "timber_cabin":
            return _create_house_geometry(plot, rng)  # Use house geometry as base
        "stone_cottage":
            return _create_house_geometry(plot, rng)  # Use house geometry as base
        "victorian_mansion":
            return _create_house_geometry(plot, rng)  # Use house geometry as base
        _:
            # Not a special building type, return null to use regular parametric system
            return null

# Create windmill geometry
func _create_windmill_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Mill body (cylindrical or rectangular tower)
    var width: float = max(plot.lot_width * 0.6, 3.0)  # Ensure minimum size
    var depth: float = max(plot.lot_depth * 0.6, 3.0)  # Ensure minimum size
    var height: float = rng.randf_range(15.0, 25.0)

    # Create a cylindrical mill body
    var sides: int = 12  # More sides for smoother cylinder
    var radius: float = min(width, depth) * 0.5

    # Create cylindrical tower
    var base_y: float = 0.0
    var top_y: float = height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * radius
        var z1: float = sin(angle1) * radius
        var x2: float = cos(angle2) * radius
        var z2: float = sin(angle2) * radius

        # Bottom vertices
        var v0 := Vector3(x1, base_y, z1)
        var v1 := Vector3(x2, base_y, z2)
        # Top vertices
        var v2 := Vector3(x2, top_y, z2)
        var v3 := Vector3(x1, top_y, z1)

        # Add face (counter-clockwise for outside)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Windmill blades (4 blades)
    var blade_length: float = radius * 2.0  # Make blades more prominent
    var blade_width: float = 0.4  # Make blades wider
    var blade_height: float = 0.2  # Make blades thicker

    for blade_idx in range(4):
        var blade_angle: float = (float(blade_idx) / 4.0) * TAU

        # Create blade at top of mill
        var center_x: float = 0.0
        var center_z: float = 0.0
        var center_y: float = top_y + blade_height * 0.5  # Slightly above the mill top

        # Blade extends in the blade_angle direction
        var blade_end_x: float = center_x + cos(blade_angle) * blade_length
        var blade_end_z: float = center_z + sin(blade_angle) * blade_length

        # Create rectangular blade
        var perp_angle: float = blade_angle + PI/2  # Perpendicular for blade width
        var half_width: float = blade_width * 0.5

        var p1 := Vector3(center_x + cos(perp_angle) * half_width, center_y, center_z + sin(perp_angle) * half_width)
        var p2 := Vector3(center_x - cos(perp_angle) * half_width, center_y, center_z - sin(perp_angle) * half_width)
        var p3 := Vector3(blade_end_x - cos(perp_angle) * half_width, center_y, blade_end_z - sin(perp_angle) * half_width)
        var p4 := Vector3(blade_end_x + cos(perp_angle) * half_width, center_y, blade_end_z + sin(perp_angle) * half_width)

        # Top face of blade
        st.add_vertex(p1)
        st.add_vertex(p2)
        st.add_vertex(p3)

        st.add_vertex(p1)
        st.add_vertex(p3)
        st.add_vertex(p4)

        # Bottom face
        st.add_vertex(p1)
        st.add_vertex(p4)
        st.add_vertex(p3)

        st.add_vertex(p1)
        st.add_vertex(p3)
        st.add_vertex(p2)

        # Side faces
        # Side 1
        st.add_vertex(p1)
        st.add_vertex(p2)
        st.add_vertex(p2 + Vector3(0, blade_height, 0))
        st.add_vertex(p1)
        st.add_vertex(p1 + Vector3(0, blade_height, 0))
        st.add_vertex(p2 + Vector3(0, blade_height, 0))

        # Side 2
        st.add_vertex(p2)
        st.add_vertex(p3)
        st.add_vertex(p3 + Vector3(0, blade_height, 0))
        st.add_vertex(p2)
        st.add_vertex(p2 + Vector3(0, blade_height, 0))
        st.add_vertex(p3 + Vector3(0, blade_height, 0))

    st.generate_normals()
    var mesh := st.commit()

    # Apply windmill-appropriate material
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.8, 0.7, 0.6)  # Light tan/wood color
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh

# Create blacksmith shop geometry
func _create_blacksmith_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Blacksmith shop - rectangular building with chimney
    var width: float = max(plot.lot_width * 0.8, 4.0)
    var depth: float = max(plot.lot_depth * 0.7, 4.0)
    var height: float = rng.randf_range(8.0, 12.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main building structure
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces
    var faces := [
        [3, 2, 6, 7],  # front
        [1, 0, 4, 5],  # back
        [0, 3, 7, 4],  # left
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Flat roof
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[5])  # back-right-top

    # Chimney
    var chimney_width: float = 1.0
    var chimney_height: float = 5.0
    var chimney_hw: float = chimney_width * 0.5
    var chimney_x: float = -hw * 0.5  # Offset from center
    var chimney_z: float = -hd * 0.5  # Offset from center
    var chimney_base_y: float = top_y
    var chimney_top_y: float = chimney_base_y + chimney_height

    # Chimney structure
    var chimney_corners := [
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 0
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 1
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 2
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 3
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 4
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 5
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 6
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 7
    ]

    var chimney_faces := [
        [0, 1, 5, 4],  # back
        [1, 2, 6, 5],  # right
        [2, 3, 7, 6],  # front
        [3, 0, 4, 7],  # left
    ]

    for face in chimney_faces:
        var v0 = chimney_corners[face[0]]
        var v1 = chimney_corners[face[1]]
        var v2 = chimney_corners[face[2]]
        var v3 = chimney_corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Chimney top
    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[7])  # front-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top
    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top
    st.add_vertex(chimney_corners[5])  # back-right-top

    st.generate_normals()
    var mesh := st.commit()

    # Apply blacksmith-appropriate material (dark brown/gray)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.25)  # Dark brown/wood
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh

# Create factory building geometry
func _create_factory_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Factory building - large rectangular structure with smokestacks
    var width: float = max(plot.lot_width * 0.9, 8.0)
    var depth: float = max(plot.lot_depth * 0.8, 6.0)
    var height: float = rng.randf_range(10.0, 18.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main building structure
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces
    var faces := [
        [3, 2, 6, 7],  # front
        [1, 0, 4, 5],  # back
        [0, 3, 7, 4],  # left
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Gable roof (makes it look more industrial)
    var roof_peak_y: float = top_y + height * 0.2
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable
    st.add_vertex(corners[3])  # front-bottom-left
    st.add_vertex(corners[2])  # front-bottom-right
    st.add_vertex(front_center_top)

    # Back gable
    st.add_vertex(corners[1])  # back-bottom-right
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)

    # Roof slopes
    # Left slope
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Factory smokestacks
    var stack_count: int = 2
    for i in range(stack_count):
        var stack_width: float = 1.2
        var stack_height: float = height * 1.5
        var stack_hw: float = stack_width * 0.5
        var stack_x: float = -hw * 0.6 + (i * hw * 1.2)  # Space them apart
        var stack_z: float = -hd * 0.7  # Near back
        var stack_base_y: float = roof_peak_y
        var stack_top_y: float = stack_base_y + stack_height

        # Stack structure
        var stack_corners := [
            Vector3(stack_x - stack_hw, stack_base_y, stack_z - stack_hw),  # 0
            Vector3(stack_x + stack_hw, stack_base_y, stack_z - stack_hw),  # 1
            Vector3(stack_x + stack_hw, stack_base_y, stack_z + stack_hw),  # 2
            Vector3(stack_x - stack_hw, stack_base_y, stack_z + stack_hw),  # 3
            Vector3(stack_x - stack_hw, stack_top_y, stack_z - stack_hw),  # 4
            Vector3(stack_x + stack_hw, stack_top_y, stack_z - stack_hw),  # 5
            Vector3(stack_x + stack_hw, stack_top_y, stack_z + stack_hw),  # 6
            Vector3(stack_x - stack_hw, stack_top_y, stack_z + stack_hw),  # 7
        ]

        var stack_faces := [
            [0, 1, 5, 4],  # back
            [1, 2, 6, 5],  # right
            [2, 3, 7, 6],  # front
            [3, 0, 4, 7],  # left
        ]

        for face in stack_faces:
            var v0 = stack_corners[face[0]]
            var v1 = stack_corners[face[1]]
            var v2 = stack_corners[face[2]]
            var v3 = stack_corners[face[3]]

            # Triangle 1: v0, v1, v2
            st.add_vertex(v0)
            st.add_vertex(v1)
            st.add_vertex(v2)

            # Triangle 2: v0, v2, v3
            st.add_vertex(v0)
            st.add_vertex(v2)
            st.add_vertex(v3)

    st.generate_normals()
    var mesh := st.commit()

    # Apply factory-appropriate material (dark gray/industrial)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)  # Dark gray
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)

    return mesh

# Create house geometry
func _create_house_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # House - typical residential building with pitched roof
    var width: float = max(plot.lot_width * 0.8, 5.0)
    var depth: float = max(plot.lot_depth * 0.7, 4.0)
    var height: float = rng.randf_range(6.0, 10.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main building structure
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces
    var faces := [
        [3, 2, 6, 7],  # front
        [1, 0, 4, 5],  # back
        [0, 3, 7, 4],  # left
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Pitched roof
    var roof_peak_y: float = top_y + height * 0.3
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable
    st.add_vertex(corners[3])  # front-bottom-left
    st.add_vertex(corners[2])  # front-bottom-right
    st.add_vertex(front_center_top)

    # Back gable
    st.add_vertex(corners[1])  # back-bottom-right
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)

    # Roof slopes
    # Left slope
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    st.generate_normals()
    var mesh := st.commit()

    # Apply house-appropriate material (warm colors)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.85, 0.75, 0.6)  # Warm tan/beige
    mat.roughness = 0.85
    mesh.surface_set_material(0, mat)

    return mesh

# Create lighthouse geometry
func _create_lighthouse_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Lighthouse tower (tapered cylinder)
    var base_radius: float = plot.lot_width * 0.3
    var top_radius: float = base_radius * 0.4  # Tapered
    var height: float = rng.randf_range(25.0, 40.0)

    var sides: int = 12
    var segments: int = 8

    # Create tapered tower
    for seg in range(segments):
        var y1: float = (float(seg) / float(segments)) * height
        var y2: float = (float(seg + 1) / float(segments)) * height

        var r1: float = lerp(base_radius, top_radius, float(seg) / float(segments))
        var r2: float = lerp(base_radius, top_radius, float(seg + 1) / float(segments))

        for i in range(sides):
            var angle1: float = (float(i) / float(sides)) * TAU
            var angle2: float = (float(i + 1) / float(sides)) * TAU

            var x11: float = cos(angle1) * r1
            var z11: float = sin(angle1) * r1
            var x12: float = cos(angle1) * r2
            var z12: float = sin(angle1) * r2
            var x21: float = cos(angle2) * r1
            var z21: float = sin(angle2) * r1
            var x22: float = cos(angle2) * r2
            var z22: float = sin(angle2) * r2

            var v1 := Vector3(x11, y1, z11)
            var v2 := Vector3(x21, y1, z21)
            var v3 := Vector3(x22, y2, z22)
            var v4 := Vector3(x12, y2, z12)

            # Face
            st.add_vertex(v1)
            st.add_vertex(v2)
            st.add_vertex(v3)

            st.add_vertex(v1)
            st.add_vertex(v3)
            st.add_vertex(v4)

    # Lighthouse lamp at top
    var lamp_radius: float = top_radius * 0.8
    var lamp_height: float = 3.0
    var lamp_y: float = height

    # Create lamp dome
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * lamp_radius
        var z1: float = sin(angle1) * lamp_radius
        var x2: float = cos(angle2) * lamp_radius
        var z2: float = sin(angle2) * lamp_radius

        # Create dome-like cap
        var top := Vector3(0, lamp_y + lamp_height, 0)
        var v1 := Vector3(x1, lamp_y, z1)
        var v2 := Vector3(x2, lamp_y, z2)

        # Triangle from base to top
        st.add_vertex(v1)
        st.add_vertex(v2)
        st.add_vertex(top)

    st.generate_normals()
    var mesh := st.commit()

    # Apply lighthouse-appropriate material (white with some gray)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.95, 0.95, 0.95)  # White
    mat.roughness = 0.8
    mesh.surface_set_material(0, mat)

    return mesh

# Create barn geometry
func _create_barn_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var width: float = plot.lot_width * 0.9
    var depth: float = plot.lot_depth * 0.8
    var height: float = rng.randf_range(8.0, 15.0)
    var roof_height: float = height * 0.4  # Gable roof height

    # Main barn structure (rectangular box)
    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Create main building
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces (each face is 2 triangles)
    var faces := [
        # Bottom (not visible, but for completeness)
        [0, 1, 2, 3],  # bottom
        # Top (will be replaced by roof)
        [4, 7, 6, 5],  # top
        # Front
        [3, 2, 6, 7],  # front
        # Back
        [1, 0, 4, 5],  # back
        # Left
        [0, 3, 7, 4],  # left
        # Right
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Gable roof (triangle on front/back)
    var roof_peak_y: float = top_y + roof_height

    # Front gable (triangular roof face)
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var front_bottom_left = Vector3(-hw, top_y, hd)
    var front_bottom_right = Vector3(hw, top_y, hd)

    st.add_vertex(front_bottom_left)
    st.add_vertex(front_bottom_right)
    st.add_vertex(front_center_top)

    # Back gable
    var back_center_top = Vector3(0, roof_peak_y, -hd)
    var back_bottom_left = Vector3(-hw, top_y, -hd)
    var back_bottom_right = Vector3(hw, top_y, -hd)

    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)
    st.add_vertex(back_bottom_right)

    # Roof sides (connect roof peak to roof edges)
    # Left roof slope
    st.add_vertex(front_bottom_left)
    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)

    st.add_vertex(front_bottom_left)
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right roof slope
    st.add_vertex(front_bottom_right)
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(front_bottom_right)
    st.add_vertex(back_center_top)
    st.add_vertex(back_bottom_right)

    st.generate_normals()
    var mesh := st.commit()

    # Apply barn-appropriate material (red with white trim)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.7, 0.1, 0.1)  # Red barn color
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh

# Create church geometry
func _create_church_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Church main building
    var width: float = plot.lot_width * 0.7
    var depth: float = plot.lot_depth * 0.8
    var height: float = rng.randf_range(12.0, 20.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main rectangular building
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces
    var faces := [
        [3, 2, 6, 7],  # front
        [1, 0, 4, 5],  # back
        [0, 3, 7, 4],  # left
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Gable roof
    var roof_peak_y: float = top_y + height * 0.3  # Pointed roof
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable
    st.add_vertex(corners[3])  # front-bottom-left
    st.add_vertex(corners[2])  # front-bottom-right
    st.add_vertex(front_center_top)

    # Back gable
    st.add_vertex(corners[1])  # back-bottom-right
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)

    # Roof slopes
    # Left slope
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Church steeple
    var spire_base_width: float = width * 0.2
    var spire_height: float = height * 0.8
    var spire_hw: float = spire_base_width * 0.5
    var spire_base_y: float = roof_peak_y
    var spire_top_y: float = spire_base_y + spire_height

    # Square steeple base
    var spire_corners := [
        Vector3(-spire_hw, spire_base_y, -spire_hw),  # 0
        Vector3(spire_hw, spire_base_y, -spire_hw),   # 1
        Vector3(spire_hw, spire_base_y, spire_hw),    # 2
        Vector3(-spire_hw, spire_base_y, spire_hw),   # 3
        Vector3(-spire_hw, spire_top_y, -spire_hw),   # 4
        Vector3(spire_hw, spire_top_y, -spire_hw),    # 5
        Vector3(spire_hw, spire_top_y, spire_hw),     # 6
        Vector3(-spire_hw, spire_top_y, spire_hw),    # 7
    ]

    var spire_faces := [
        [0, 1, 5, 4],  # back
        [1, 2, 6, 5],  # right
        [2, 3, 7, 6],  # front
        [3, 0, 4, 7],  # left
    ]

    for face in spire_faces:
        var v0 = spire_corners[face[0]]
        var v1 = spire_corners[face[1]]
        var v2 = spire_corners[face[2]]
        var v3 = spire_corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Spire top (pyramid)
    var spire_peak = Vector3(0, spire_top_y + height * 0.2, 0)
    for i in range(4):
        var corner1 = spire_corners[4 + i]  # Top corners
        var corner2 = spire_corners[4 + ((i + 1) % 4)]  # Next top corner
        st.add_vertex(corner1)
        st.add_vertex(corner2)
        st.add_vertex(spire_peak)

    st.generate_normals()
    var mesh := st.commit()

    # Apply church-appropriate material (light gray/white)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.85, 0.85, 0.85)  # Light gray
    mat.roughness = 0.8
    mesh.surface_set_material(0, mat)

    return mesh

# Create castle geometry
func _create_castle_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Castle main structure
    var width: float = plot.lot_width * 0.9
    var depth: float = plot.lot_depth * 0.9
    var height: float = rng.randf_range(15.0, 25.0)

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var top_y: float = height

    # Main rectangular building
    var corners := [
        Vector3(-hw, base_y, -hd),  # 0: back-left-bottom
        Vector3(hw, base_y, -hd),   # 1: back-right-bottom
        Vector3(hw, base_y, hd),    # 2: front-right-bottom
        Vector3(-hw, base_y, hd),   # 3: front-left-bottom
        Vector3(-hw, top_y, -hd),   # 4: back-left-top
        Vector3(hw, top_y, -hd),    # 5: back-right-top
        Vector3(hw, top_y, hd),     # 6: front-right-top
        Vector3(-hw, top_y, hd),    # 7: front-left-top
    ]

    # Define faces
    var faces := [
        [3, 2, 6, 7],  # front
        [1, 0, 4, 5],  # back
        [0, 3, 7, 4],  # left
        [2, 1, 5, 6],  # right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0, v1, v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0, v2, v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Flat roof
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[5])  # back-right-top

    # Castle battlements (crenellations)
    var battlement_height: float = 2.0
    var battlement_width: float = 0.5
    var battlement_spacing: float = 2.0

    # Front battlements
    var front_segments: int = int(depth / battlement_spacing)
    for i in range(front_segments):
        var t: float = float(i) / float(max(1, front_segments - 1))
        var x_pos: float = -hw + (hw * 2.0) * t
        var z_pos: float = hd

        # Create a small rectangular battlement
        var bh: float = battlement_height
        var bw: float = battlement_width * 0.5
        var bd: float = battlement_width * 0.5

        var battlement_corners := [
            Vector3(x_pos - bw, top_y, z_pos - bd),  # 0: left-bottom
            Vector3(x_pos + bw, top_y, z_pos - bd),  # 1: right-bottom
            Vector3(x_pos + bw, top_y + bh, z_pos - bd),  # 2: right-top
            Vector3(x_pos - bw, top_y + bh, z_pos - bd),  # 3: left-top
        ]

        # Front face of battlement
        st.add_vertex(battlement_corners[0])
        st.add_vertex(battlement_corners[1])
        st.add_vertex(battlement_corners[2])
        st.add_vertex(battlement_corners[0])
        st.add_vertex(battlement_corners[2])
        st.add_vertex(battlement_corners[3])

        # Back face
        var back_corners := [
            Vector3(x_pos - bw, top_y, z_pos + bd),  # 0: left-bottom
            Vector3(x_pos + bw, top_y, z_pos + bd),  # 1: right-bottom
            Vector3(x_pos + bw, top_y + bh, z_pos + bd),  # 2: right-top
            Vector3(x_pos - bw, top_y + bh, z_pos + bd),  # 3: left-top
        ]

        st.add_vertex(back_corners[1])
        st.add_vertex(back_corners[0])
        st.add_vertex(back_corners[2])
        st.add_vertex(back_corners[0])
        st.add_vertex(back_corners[3])
        st.add_vertex(back_corners[2])

        # Side faces
        st.add_vertex(battlement_corners[1])
        st.add_vertex(back_corners[1])
        st.add_vertex(back_corners[2])
        st.add_vertex(battlement_corners[1])
        st.add_vertex(back_corners[2])
        st.add_vertex(battlement_corners[2])

        st.add_vertex(back_corners[0])
        st.add_vertex(battlement_corners[0])
        st.add_vertex(battlement_corners[3])
        st.add_vertex(back_corners[0])
        st.add_vertex(battlement_corners[3])
        st.add_vertex(back_corners[3])

    st.generate_normals()
    var mesh := st.commit()

    # Apply castle-appropriate material (gray stone)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.5, 0.5, 0.55)  # Gray stone
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)

    return mesh

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
