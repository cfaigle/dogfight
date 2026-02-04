extends WorldComponentBase
class_name OrganicBuildingPlacementComponent

## Places buildings on pre-generated plots
## Reuses existing collision system and building styles
## Priority: 65 (same as old settlement_buildings)

# Import unified building type registry
const BuildingTypeRegistry = preload("res://scripts/building_systems/registry/building_type_registry.gd")

# Import BuildingConfig class
const BuildingConfig = BuildingTypeRegistry.BuildingConfig

# Import collision adder utility
const CollisionAdder = preload("res://scripts/util/collision_adder.gd")

# Geometry class imports for external building types
const RadioTowerGeometry = preload("res://scripts/world/building_geometries/radio_tower_geometry.gd")
const GrainSiloGeometry = preload("res://scripts/world/building_geometries/grain_silo_geometry.gd")
const CornFeederGeometry = preload("res://scripts/world/building_geometries/corn_feeder_geometry.gd")

# Template system classes (not used due to class recognition issues)
# const # BuildingTemplateRegistry = preload("res://scripts/building_systems/templates/building_template_registry.gd")
# const # BuildingTemplateGenerator = preload("res://scripts/building_systems/templates/building_template_generator.gd")
# var _template_registry: # BuildingTemplateRegistry



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

    # Initialize building positions array for tree placement collision detection
    var building_positions: Array = []

    # Get desired building count from params
    var target_building_count: int = int(params.get("building_count", 5000))
    var max_building_count: int = min(target_building_count, plots.size())

#    print("🏗️ OrganicBuildingPlacement: Attempting to place ", max_building_count, " buildings from ", plots.size(), " available plots")

    # Randomly select plots for building placement
    var plots_to_use: Array = plots.duplicate()
    plots_to_use.shuffle()  # Randomize the order

    for i in range(max_building_count):
        var plot = plots_to_use[i]

        # Create building
        var building := _place_building_on_plot(plot, rng)
        if building != null:
            buildings_layer.add_child(building)

            # Add collision and damage capability to the building
            var building_type = plot.get("building_type", "building")
            # Schedule collision addition for next frame to ensure building is in the scene tree
            # Skip if building already has a StaticBody3D parent (prevents double collision)
            if not building.get_parent() is StaticBody3D:
                print("🏗️ Scheduling collision for building: %s (type: %s)" % [building.name, building_type])
                call_deferred("_add_collision_to_building", building, building_type)

            # Track building position for tree collision avoidance
            # Store position and approximate radius based on building type
            var building_radius: float = 15.0  # Default radius for collision buffer
            building_positions.append({
                "position": building.global_position,
                "radius": building_radius
            })

            placed_count += 1

    # Store building positions in WorldContext for tree placement to access
    ctx.set_data("building_positions", building_positions)
    print("🏗️ OrganicBuildingPlacement: Stored %d building positions for tree collision avoidance" % building_positions.size())

# Add collision to a building in a deferred manner
func _add_collision_to_building(building, building_type: String) -> void:
    print("🏗️ _add_collision_to_building called for: %s (type: %s)" % [building.name, building_type])
    print("  - CollisionManager exists: %s" % (CollisionManager != null))

    # Use CollisionManager for proper damage system integration (sets damage_target metadata)
    if CollisionManager and CollisionManager.has_method("add_collision_to_object"):
        print("  - Using CollisionManager for building collision")
        CollisionManager.add_collision_to_object(building, "building")
    else:
        # Fallback to legacy CollisionAdder (doesn't support damage system)
        push_warning("CollisionManager not available for building, using legacy CollisionAdder")
        if Engine.has_singleton("CollisionAdder"):
            var collision_adder = Engine.get_singleton("CollisionAdder")
            collision_adder.add_collision_to_buildings(building, building_type)
        else:
            var collision_adder_script = load("res://scripts/util/collision_adder.gd")
            if collision_adder_script:
                collision_adder_script.add_collision_to_buildings(building, building_type)

#    print("🏗️ OrganicBuildingPlacement: Successfully placed ", placed_count, " buildings from ", max_building_count, " attempts")

func _place_building_on_plot(plot: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    # Get terrain height at plot position
    var terrain_height := ctx.terrain_generator.get_height_at(plot.position.x, plot.position.z)
    var final_pos := Vector3(plot.position.x, terrain_height, plot.position.z)

    # Skip building if underwater
    var sea_level := float(ctx.params.get("sea_level", 0.0))
    if terrain_height < sea_level - 0.5:  # Allow slightly below sea level
        return null

    # Use unified type registry for consistent building type resolution
    var building_type: String = ""
    var building_type_label: String = ""
    var building: MeshInstance3D = null
    var initial_building_type_label: String = ""

    # Try to get specific building type from plot data (PRIORITY ORDER)
    if plot.has("specific_building_type"):
        building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        building_type = plot.building_subtype
    elif plot.has("building_variant"):
        building_type = plot.building_variant
    elif plot.has("building_category"):
        building_type = plot.building_category
    elif plot.has("building_type"):
        building_type = plot.get("building_type", "")
    elif plot.has("subtype"):
        building_type = plot.subtype
    elif plot.has("variant"):
        building_type = plot.variant
    elif plot.has("category"):
        building_type = plot.category
    elif plot.has("type"):
        building_type = plot.type
    elif plot.has("style"):
        building_type = plot.style

    # If no specific building type found, use unified registry to get appropriate type for density
    if building_type == "":
        var density_class = plot.get("density_class", "rural")
        if ctx.unified_building_system != null:
            var type_registry = ctx.unified_building_system.get_type_registry()
            building_type = type_registry.get_building_type_for_density(density_class, rng)
        else:
            # Fallback to simple density-based types
            match density_class:
                "rural":
                    building_type = "stone_cottage"
                "suburban":
                    building_type = "house_victorian"
                "urban":
                    building_type = "shop"
                "urban_core":
                    building_type = "factory_building"
                _:
                    building_type = "stone_cottage"

    # Update plot with resolved building type
    plot["building_type"] = building_type
    building_type_label = building_type

    # Prefer unified building system if available
    if ctx.unified_building_system != null:
        building = ctx.unified_building_system.generate_adaptive_building(building_type, plot, rng)
        if building != null:
            building.position = Vector3.ZERO  # Position relative to parent
            building.rotation.y = plot.yaw
            building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

            # Update building_type_label with what was actually created
            building_type_label = plot.get("building_type", building_type)
            # print("✅ Successfully created unified system building: %s" % building_type_label)
        else:
            print("❌ Failed to create unified system building, falling back")
    elif ctx.parametric_system != null:
#        print("🏗️ Using parametric building system for plot at (", plot.position.x, ",", plot.position.z, ")")
        building = _create_parametric_building(plot, Vector3.ZERO, rng)  # Position relative to parent

        # IMPORTANT: Update building_type_label with what was actually created by parametric system
        # The parametric building function should have set plot["building_type"] to the correct type
        building_type_label = plot.get("building_type", initial_building_type_label)
#        print("🔄 UPDATED BUILDING TYPE LABEL to: '", building_type_label, "' (from parametric system)")
        if building != null:
#            print("   ✅ Successfully created parametric building")
            pass
            # Don't overwrite the building_type_label - it's already correct from the parametric system
        else:
            print("   ❌ Failed to create parametric building, falling back to building kits")
            # Try building kits as secondary option
            if ctx.building_kits.size() > 0:
                building = _create_building_from_kit(plot, Vector3.ZERO, rng)  # Position relative to parent
                if building != null:
#                    print("   ✅ Successfully created building kit building")
                    building_type_label = plot.get("building_type", "kit")
                else:
                    print("   ❌ Failed to create building kit building, falling back to simple")
                    building = _create_simple_building(plot, Vector3.ZERO, rng)  # Position relative to parent
                    building_type_label = plot.get("building_type", "simple")
            else:
                building = _create_simple_building(plot, Vector3.ZERO, rng)  # Position relative to parent
                building_type_label = plot.get("building_type", "simple")
    elif ctx.building_kits.size() > 0:
        # Try to use building kits if parametric system is not available but kits exist
#        print("🔧 Using building kit system for plot at (", plot.position.x, ",", plot.position.z, ")")
        building = _create_building_from_kit(plot, Vector3.ZERO, rng)  # Position relative to parent
        if building != null:
#            print("   ✅ Successfully created building kit building")
            building_type_label = plot.get("building_type", "kit")
        else:
            print("   ❌ Failed to create building kit building, falling back to simple")
            building = _create_simple_building(plot, Vector3.ZERO, rng)  # Position relative to parent
            building_type_label = plot.get("building_type", "simple")
    else:
        print("⚠️ No building systems available, using simple building")
        # Fallback to simple building
        building = _create_simple_building(plot, Vector3.ZERO, rng)  # Position relative to parent
        building_type_label = plot.get("building_type", "simple")

    if building == null:
        return null

    # Create a StaticBody3D to wrap the building with collision and damage capabilities
    var building_body = StaticBody3D.new()
    var readable_name = _get_readable_building_name(building_type_label)
    building_body.name = "BuildingWithCollision_%s" % readable_name
    building_body.position = final_pos  # Set the world position here
    building_body.rotation.y = plot.yaw

    # Set collision layers to match the raycast mask (layer 1)
    building_body.collision_layer = 1
    building_body.collision_mask = 1
    
    # Add metadata for reliable building type identification
    building_body.set_meta("building_type", building_type_label)
    building_body.set_meta("building_category", "building")
    print("DEBUG: Set building metadata - type: ", building_type_label, " on node: ", building_body.name)

    # Add the building mesh as a child of the StaticBody3D
    building_body.add_child(building)
    building.owner = building_body

    # Create collision shape based on the building's bounding box
    var collision_shape = CollisionShape3D.new()
    var aabb = building.get_aabb()

    # Create a box shape that encompasses the building
    var box_shape = BoxShape3D.new()
    box_shape.size = aabb.size
    collision_shape.shape = box_shape

    # Position the collision shape relative to the building (which is at (0,0,0) relative to parent)
    # Adjust Y position to account for building's position relative to ground
    collision_shape.position = Vector3(0, aabb.size.y / 2.0, 0)

    building_body.add_child(collision_shape)
    collision_shape.owner = building_body

    # Add damageable component to make the building destructible
    var damageable_obj = BuildingDamageableObject.new()
    damageable_obj.name = "BuildingDamageable"
    # Set building type so _ready() can handle initialization properly
    damageable_obj.building_type = building_type_label
    damageable_obj.set_meta("building_type", building_type_label)
    # Remove manual initialize_damageable() call - let _ready() handle it
    building_body.add_child(damageable_obj)
    damageable_obj.owner = building_body
    print("DEBUG: Added BuildingDamageable with type: ", building_type_label, " to: ", building_body.name)

    # Add optional building type label if enabled
    var enable_labels: bool = bool(ctx.params.get("enable_building_labels", true))

    # FINAL DEBUG: Show what building type will actually be used for label
#    print("🏷️ FINAL BUILDING TYPE FOR LABEL: '", building_type_label, "'")
    if enable_labels:
#        print("🏷️ Adding label for building type: ", building_type_label, " at position: ", final_pos)
        _add_building_label(building, building_type_label, final_pos, plot)
    else:
        # print("⏭️ Skipping label for building at: ", final_pos, " (labels enabled: ", enable_labels, ", building exists: ", building != null, ")")
        pass

    return building_body

# Add a text label above the building showing its type
func _add_building_label(building_node: MeshInstance3D, building_type: String, position: Vector3, plot: Dictionary) -> void:
    # Check if labels are enabled
    if not bool(ctx.params.get("enable_building_labels", true)):
        return

    # Create a label node in the world instead of as a child of the building
    # This ensures the label remains visible even if the building is transformed
    var label_root := Node3D.new()
    label_root.name = "LabelRoot_" + building_type.replace(" ", "_")

    # Position label above the building in world coordinates
    var label_height: float = position.y + 24.0  # 16 units above ground level (double the height)
    label_root.position = Vector3(position.x, label_height, position.z)

    # Add to the Infrastructure layer directly to ensure visibility
    var infra_layer = ctx.get_layer("Infrastructure")
    if infra_layer != null:
        infra_layer.add_child(label_root)
#        print("   🏷️ Added label to Infrastructure layer at: ", label_root.position)
    else:
        print("⚠️ Infrastructure layer not found, trying fallback...")
        # Fallback: add to same parent as building
        var parent_node = building_node.get_parent()
        if parent_node != null:
            parent_node.add_child(label_root)
#            print("   🏷️ Added label to building's parent at: ", label_root.position)
        else:
            print("⚠️ Could not find parent for label, skipping label for: ", building_type)
            label_root.queue_free()
            return

    # Add actual text using Label3D with proper font and visibility settings
    var label_3d := Label3D.new()
    label_3d.text = building_type
    label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label_3d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    
    # CRITICAL FIX: Load and assign a font to make text visible
    var font := ThemeDB.fallback_font
    if font != null:
        label_3d.font = font
#        print("   📝 Assigned fallback font to label")
    else:
        # Try to load our Special Elite font as fallback
        var system_font := load("res://assets/fonts/Special_Elite/SpecialElite-Regular.ttf")
        if system_font != null:
            label_3d.font = system_font
#            print("   📝 Assigned system font to label")
        else:
            # Create a basic font as last resort
            var basic_font := FontFile.new()
            label_3d.font = basic_font
#            print("   📝 Created basic font for label")
    
    # Fix color for better visibility (white text with outline)
    label_3d.modulate = Color.WHITE
    label_3d.outline_modulate = Color.BLACK
    label_3d.outline_size = 5
    
# Adjust positioning and scale for better visibility
    label_3d.position = Vector3(0, 3.0, 0)  # Higher position above building
    label_3d.scale = Vector3(2.5, 2.5, 2.5)  # 5x bigger scale (0.5 * 5 = 2.5)
    label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # Make label always face camera for better readability
    label_3d.no_depth_test = true  # Ensure label renders in front of other objects
    
    # Set proper pixel size for text rendering
    label_3d.pixel_size = 0.005  # Smaller pixel size for sharper text
    label_3d.font_size = 576 # 12x bigger font size for better readability

    label_root.add_child(label_3d)

#    print("   🏷️ Added label with text '", building_type, "' for building at world position: ", label_root.position)
    
#    # DEBUG: Add visible marker to verify label position
#    var debug_marker := MeshInstance3D.new()
#    var debug_cube := BoxMesh.new()
#    debug_cube.size = Vector3(5.0, 5.0, 5.0)  # 5x bigger debug cube
#    debug_marker.mesh = debug_cube
#    debug_marker.material_override = StandardMaterial3D.new()
#    debug_marker.material_override.albedo_color = Color.YELLOW
#    debug_marker.position = Vector3(0, 1.0, 0)  # Raise slightly above label position
#    label_root.add_child(debug_marker)
#    print("   🔍 Added 5x bigger debug marker at label position for verification")

# This function would create a texture with text rendered on it
# For now, we'll use a placeholder approach that creates a texture with text
# In a real implementation, you would need to use a font system to render text to a texture
func _create_text_texture(text: String, text_color: Color, bg_color: Color) -> Texture2D:
    # For now, return null to use the solid color approach
    # A full implementation would require creating a dynamic font texture
    # which is complex during world generation
    return null

func _create_building_from_kit(plot: Dictionary, pos: Vector3, rng: RandomNumberGenerator) -> MeshInstance3D:
    # Determine building type with priority for specific types
    var building_type: String = ""
    if plot.has("specific_building_type"):
        building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        building_type = plot.building_subtype
    elif plot.has("building_variant"):
        building_type = plot.building_variant
    elif plot.has("building_category"):
        building_type = plot.building_category
    elif plot.has("building_type"):
        building_type = plot.get("building_type", "residential")
    elif plot.has("subtype"):
        building_type = plot.subtype
    elif plot.has("variant"):
        building_type = plot.variant
    elif plot.has("category"):
        building_type = plot.category
    elif plot.has("type"):
        building_type = plot.type
    elif plot.has("style"):
        building_type = plot.style
    else:
        building_type = plot.get("density_class", "rural")

    # Map plot density to settlement style, but allow specific building types to override
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
    if building_type == "commercial" and rng.randf() < 0.2:
        style = "industrial"
    # If we have a specific building type that corresponds to a particular style, use that
    elif building_type in ["windmill", "radio_tower", "grain_silo", "corn_feeder", "barn", "blacksmith"]:
        style = "hamlet"  # Rural style for these specific building types
    elif building_type in ["factory", "industrial", "warehouse"]:
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
        building.set_meta("name", "ExternalMesh_%s_%d" % [building_type, rng.randi()])
        building.set_meta("building_type", building_type)
        building.set_meta("building_category", "building")
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
    if building != null:
        building.set_meta("name", "ProceduralVariant_%s_%d" % [building_type, rng.randi()])
    # Update the plot with the building type that was used
    plot["building_type"] = building_type

    # Allow specific building types to override density class using unified registry
    var specific_density_class: String = _get_preferred_density_class(building_type)
    if specific_density_class != "":
        plot["density_class"] = specific_density_class

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
    building.set_meta("name", "ProceduralBuilding_%s_%d" % [variant.get("name", "unknown"), rng.randi()])
    building.set_meta("building_type", variant.get("name", "unknown"))
    building.set_meta("building_category", "building")
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
        roof.name = "Roof_%s_%d" % [variant.get("name", "roof"), rng.randi()]
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
    # Determine building type from plot with enhanced detection
    var building_type: String = plot.get("building_type", "")

    # Enhanced detection for specific building types like "Windmill", "Blacksmith", etc.
    # Prioritize specific building types from plot data before falling back to generic ones
    if plot.has("specific_building_type"):
        building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        building_type = plot.building_subtype
    elif plot.has("building_variant"):
        building_type = plot.building_variant
    elif plot.has("building_category"):
        building_type = plot.building_category
    elif plot.has("subtype"):
        building_type = plot.subtype
    elif plot.has("variant"):
        building_type = plot.variant
    elif plot.has("category"):
        building_type = plot.category
    elif plot.has("type") and plot.type != "":
        building_type = plot.type
    elif plot.has("style") and plot.style != "":
        building_type = plot.style
    elif building_type == "":
        # Use more specific building types based on density and location
        var density_class = plot.get("density_class", "rural")
        var terrain_type = plot.get("terrain_type", "grassland")

        # Generate more specific building types based on context
        if density_class == "rural":
            var rural_types = [
                "stone_cottage", "thatched_cottage", "timber_cabin", "log_chalet",
                "barn", "windmill", "blacksmith", "mill", "farmhouse", "stable",
                "gristmill", "sawmill", "barn", "outbuilding", "granary"
            ]
            building_type = rural_types[rng.randi() % rural_types.size()]
        elif density_class == "suburban":
            var suburban_types = [
                "stone_cottage", "thatched_cottage", "white_stucco_house",
                "stone_farmhouse", "timber_cabin", "log_chalet", "cottage"
            ]
            building_type = suburban_types[rng.randi() % suburban_types.size()]
        elif density_class == "urban":
            var urban_types = [
                "stone_cottage", "factory_building", "warehouse", "shop",
                "bakery", "inn", "tavern", "pub", "workshop", "foundry"
            ]
            building_type = urban_types[rng.randi() % urban_types.size()]
        else:
            building_type = "residential"  # Final fallback

    # Update the plot with the detected building type so labels can use it
    plot["building_type"] = building_type

    # Allow specific building types to override density class
    # This enables buildings to register their preferred density class using unified registry
    var parametric_building_main_density_class: String = _get_preferred_density_class(building_type)
    if parametric_building_main_density_class != "":
        plot["density_class"] = parametric_building_main_density_class

    # DEBUG: Show what building type was detected for parametric building
#    print("🏗️ PARAMETRIC BUILDING TYPE DETECTED: '", building_type, "' for plot at (", pos.x, ",", pos.z, ")")

    var plot_style: String = building_type  # Use detected type

    # Check for the style in various possible fields
    if plot.has("style"):
        plot_style = plot.style
    elif plot.has("building_style"):
        plot_style = plot.building_style
    elif plot.has("type"):  # Sometimes the type field might contain the specific style
        plot_style = plot.type
    elif plot.has("building_type"):  # Check building_type field before density_class
        plot_style = plot.building_type
    elif plot.has("density_class"):  # Or it might be in the density class
        plot_style = plot.density_class
    else:
        # Use the building_type as the style to check for special geometry
        plot_style = building_type

    # Check if this is a special building type that needs specific geometry
    # Prioritize the specific building type from the plot over the style
    var special_building_mesh: Mesh = _create_special_building_geometry(plot_style, plot, rng)
    if special_building_mesh != null:
#        print("   🏯 Created special building - style:", plot_style)
        var building := MeshInstance3D.new()
        building.set_meta("name", "SpecialGeometry_%s_%d" % [plot_style, rng.randi()])
        building.set_meta("building_type", plot_style)
        building.set_meta("building_category", "building")
        building.mesh = special_building_mesh
        building.position = pos
        building.rotation.y = plot.yaw
        building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

        # Allow specific building types to override density class
        var special_building_density_class: String = _get_preferred_density_class(building_type)
        if special_building_density_class != "":
            plot["density_class"] = special_building_density_class

        return building


    # For regular buildings, use the unified building system if available
    if ctx.unified_building_system != null:
        # Use the unified system for better quality and consistency
        var unified_building = ctx.unified_building_system.generate_adaptive_building(building_type, plot, rng)
        if unified_building != null:
            unified_building.position = pos
            unified_building.rotation.y = plot.yaw
            unified_building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            # Update the plot with the actual building type that was created by the unified system
            plot["building_type"] = building_type
            return unified_building
    # End of unified system check

    # Fallback to the original parametric system if unified system not available
    var specific_building_type: String = building_type

    # Initialize parametric style variable
    var parametric_style: String = "ww2_european"  # Default fallback

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
            var rural_styles = ["ww2_european", "industrial_modern", "stone_cottage", "timber_cabin", "log_chalet", "barn", "windmill", "radio_tower", "grain_silo", "corn_feeder", "blacksmith"]
            parametric_style = rural_styles[rng.randi() % rural_styles.size()]
        _:
            # Default styles
            var default_styles = ["ww2_european", "american_art_deco", "industrial_modern"]
            parametric_style = default_styles[rng.randi() % default_styles.size()]

    # Check again if the randomly selected parametric style is a special building type
    # But prioritize any specific building type from the plot
    var special_building_mesh_b = _create_special_building_geometry(parametric_style, plot, rng)
    if special_building_mesh_b != null:
#        print("   🏯 Created special building from parametric style - style:", parametric_style)
        # IMPORTANT: Update the plot with the actual building type that was created
        plot["building_type"] = parametric_style

        # Allow specific building types to override density class
        var parametric_building_density_class: String = _get_preferred_density_class(parametric_style)
        if parametric_building_density_class != "":
            plot["density_class"] = parametric_building_density_class

        var building := MeshInstance3D.new()
        building.set_meta("name", "SpecialParametric_%s_%d" % [parametric_style, rng.randi()])
        building.set_meta("building_type", parametric_style)
        building.set_meta("building_category", "building")
        building.mesh = special_building_mesh_b
        building.position = pos
        building.rotation.y = plot.yaw
        building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        return building

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
    building.set_meta("name", "ParametricBuilding_%s_%s_%d" % [specific_building_type, parametric_style, rng.randi()])
    building.set_meta("building_type", specific_building_type)
    building.set_meta("building_category", "building")
    building.mesh = mesh
    building.position = pos
    building.rotation.y = plot.yaw
    building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    # IMPORTANT: Update the plot with the actual building type that was created
    plot["building_type"] = specific_building_type

    # Debug: Print building info
#    print("   🏢 Created parametric building - type:", specific_building_type, " style:", parametric_style, " dims:", width, "x", depth, " floors:", floors)

    return building

## Convert technical building type to human-readable name
func _get_readable_building_name(building_type: String) -> String:
    # Mapping of technical types to readable names
    var name_map = {
        # Rural buildings
        "stone_cottage": "StoneCottage",
        "stone_cottage_new": "StoneCottage", 
        "thatched_cottage": "ThatchedCottage",
        "cottage": "Cottage",
        "timber_cabin": "TimberCabin",
        "log_chalet": "LogChalet",
        "rustic_cabin": "RusticCabin",
        "farmhouse": "Farmhouse",
        "barn": "Barn",
        "stable": "Stable",
        "outbuilding": "Outbuilding",
        "granary": "Granary",
        
        # Commercial buildings
        "shop": "Shop",
        "store": "Store",
        "market": "Market",
        
        # Industrial buildings
        "factory": "Factory",
        "industrial": "IndustrialBuilding",
        "warehouse": "Warehouse",
        
        # Special buildings
        "windmill": "Windmill",
        "mill": "Windmill",
        "blacksmith": "BlacksmithShop",
        "radio_tower": "RadioTower",
        "grain_silo": "GrainSilo",
        "corn_feeder": "CornFeeder",
        "lighthouse": "Lighthouse",
        
        # Religious buildings
        "church": "Church",
        "temple": "Temple",
        "cathedral": "Cathedral",
        
        # Residential buildings
        "house_victorian": "VictorianHouse",
        "house_modern": "ModernHouse",
        
        # Military buildings
        "medieval_castle": "Castle",
        
        # Fallbacks
        "simple": "SimpleBuilding",
        "kit": "BuildingKit"
    }
    
    # Return mapped name or convert underscores to capitals as fallback
    if name_map.has(building_type):
        return name_map[building_type]
    else:
        # Fallback: convert underscores and capitalize
        var parts = building_type.split("_")
        var readable = ""
        for part in parts:
            if part.length() > 0:
                readable += part.capitalize()
        return readable if readable.length() > 0 else "UnknownBuilding"

# Create specific geometry for special building types
func _create_special_building_geometry(building_style: String, plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    # First, check if the plot has a specific building type that should take precedence
    var specific_building_type: String = ""
    if plot.has("specific_building_type"):
        specific_building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        specific_building_type = plot.building_subtype
    elif plot.has("building_variant"):
        specific_building_type = plot.building_variant
    elif plot.has("building_category"):
        specific_building_type = plot.building_category
    elif plot.has("building_type"):
        specific_building_type = plot.building_type
    elif plot.has("subtype"):
        specific_building_type = plot.subtype
    elif plot.has("variant"):
        specific_building_type = plot.variant
    elif plot.has("category"):
        specific_building_type = plot.category
    elif plot.has("type"):
        specific_building_type = plot.type
    elif plot.has("style"):
        specific_building_type = plot.style
    else:
        specific_building_type = building_style

    # Match against the specific building type first, then fall back to the style parameter
    match specific_building_type:
        "windmill", "mill":
            return _create_windmill_geometry(plot, rng)
        "radio_tower":
            return _create_radio_tower_geometry(plot, rng)
        "grain_silo":
            return _create_grain_silo_geometry(plot, rng)
        "corn_feeder":
            return _create_corn_feeder_geometry(plot, rng)
        "lighthouse":
            return _create_lighthouse_geometry(plot, rng)
        "barn":
            return _create_barn_geometry(plot, rng)
        "blacksmith":
            return _create_blacksmith_geometry(plot, rng)
        "factory_building", "industrial_modern", "factory", "industrial":
            return _create_factory_geometry_template(plot, rng)
        "stone_cottage", "stone_cabin":
            return _create_stone_cottage_geometry(plot, rng)
        "stone_cottage_new":
            return _create_stone_cottage_new_geometry(plot, rng)
        "house", "timber_cabin", "victorian_mansion", "residential", "cottage":
            return _create_house_geometry(plot, rng)
        "church", "temple", "cathedral":
            return _create_church_geometry(plot, rng)
        "castle_keep", "fortress", "tower":
            return _create_castle_geometry_template(plot, rng)
        _:
            # If the specific building type didn't match, try the original building_style parameter
            match building_style:
                "windmill", "mill":
                    return _create_windmill_geometry(plot, rng)
                "radio_tower":
                    return _create_radio_tower_geometry(plot, rng)
                "grain_silo":
                    return _create_grain_silo_geometry(plot, rng)
                "corn_feeder":
                    return _create_corn_feeder_geometry(plot, rng)
                "lighthouse":
                    return _create_lighthouse_geometry(plot, rng)
                "barn":
                    return _create_barn_geometry(plot, rng)
                "blacksmith":
                    return _create_blacksmith_geometry(plot, rng)
                "factory_building", "industrial_modern", "factory", "industrial":
                    return _create_factory_geometry_template(plot, rng)
                "stone_cottage", "stone_cabin":
                    return _create_stone_cottage_geometry(plot, rng)
                "stone_cottage_new":
                    return _create_stone_cottage_new_geometry(plot, rng)
                "house", "timber_cabin", "victorian_mansion", "residential", "cottage":
                    return _create_house_geometry(plot, rng)
                "church", "temple", "cathedral":
                    return _create_church_geometry(plot, rng)
                "castle_keep", "fortress", "tower":
                    return _create_castle_geometry_template(plot, rng)
                _:
                    # Not a special building type, return null to use regular parametric system
                    return null

# Create windmill geometry with proper architecture
func _create_windmill_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Windmill specifications
    var base_radius: float = max(plot.lot_width * 0.35, 3.0)  # Wider base for stability
    var base_height: float = rng.randf_range(20.0, 40.0)

    # Create cylindrical base/tower
    var sides: int = 16  # More sides for smoother appearance
    var base_y: float = 0.0
    var base_top_y: float = base_height

    # Generate base walls
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * base_radius
        var z1: float = sin(angle1) * base_radius
        var x2: float = cos(angle2) * base_radius
        var z2: float = sin(angle2) * base_radius

        # Define vertices for this wall segment
        var v0 := Vector3(x1, base_y, z1)  # Bottom left
        var v1 := Vector3(x2, base_y, z2)  # Bottom right
        var v2 := Vector3(x2, base_top_y, z2)  # Top right
        var v3 := Vector3(x1, base_top_y, z1)  # Top left

        # Add two triangles to form the quad (counter-clockwise for outside-facing normals)
        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)  # Normal should point outward
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create conical cap/roof on top of base
    var cap_radius: float = base_radius * 0.8  # Slightly smaller than base
    var cap_height: float = 4.0   # Conical cap height
    var cap_base_y: float = base_top_y
    var cap_top_y: float = cap_base_y + cap_height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        var x1: float = cos(angle1) * base_radius
        var z1: float = sin(angle1) * base_radius
        var x2: float = cos(angle2) * base_radius
        var z2: float = sin(angle2) * base_radius

        # Define vertices for the conical roof (from base edge to peak)
        var base_v1 := Vector3(x1, cap_base_y, z1)
        var base_v2 := Vector3(x2, cap_base_y, z2)
        var peak := Vector3(0, cap_top_y, 0)

        # Triangle forming the roof face - counter-clockwise for outward normals
        st.add_vertex(base_v1)  # Pointing outward from peak
        st.add_vertex(base_v2)
        st.add_vertex(peak)

    # Create windmill shaft (the rotating part that holds the sails)
    # -------------------------------------------------------------------
    # SIDE-MOUNTED ROTOR ASSEMBLY (shaft + vanes as a single unit)
    # Replaces the old vertical shaft + vertical vane blocks.
    # Assumptions:
    #   - Y is up
    #   - Tower center is at (0, *, 0)
    #   - +Z is "outward" from the windmill face
    # -------------------------------------------------------------------
    
    # Place the rotor roughly on the front side of the cap.
    var rotor_hub_x: float = 0.0
    # Place rotor at ~75% of the *tower* height (not the cap)
    var rotor_hub_y: float = base_y + base_height * 0.9
#    var rotor_hub_y: float = cap_base_y + cap_height * 0.65
    var rotor_hub_z: float = base_radius + 0.10  # slightly outside the wall
    
    var shaft_radius: float = base_radius * 0.3
    var shaft_height: float = 2.0
    var shaft_y: float = cap_top_y
    var shaft_top_y: float = shaft_y + shaft_height

    # Shaft parameters (horizontal, pointing out along +Z)
    var shaft_length: float = 1.20
#    var shaft_radius: float = 0.12
    var shaft_segments: int = 14
    
    var shaft_z0: float = rotor_hub_z
    var shaft_z1: float = rotor_hub_z + shaft_length
    
    # Build a cylinder aligned to +Z (rings in X/Y)
    for i in range(shaft_segments):
        var a0: float = (float(i) / float(shaft_segments)) * TAU
        var a1: float = (float(i + 1) / float(shaft_segments)) * TAU
    
        var x0: float = cos(a0) * shaft_radius
        var y0: float = sin(a0) * shaft_radius
        var x1: float = cos(a1) * shaft_radius
        var y1: float = sin(a1) * shaft_radius
    
        var v00 := Vector3(rotor_hub_x + x0, rotor_hub_y + y0, shaft_z0)
        var v01 := Vector3(rotor_hub_x + x1, rotor_hub_y + y1, shaft_z0)
        var v10 := Vector3(rotor_hub_x + x0, rotor_hub_y + y0, shaft_z1)
        var v11 := Vector3(rotor_hub_x + x1, rotor_hub_y + y1, shaft_z1)
    
        # Side faces (2 triangles)
        st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v11)
        st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v01)
    
    # Optional: cap the inner end of the shaft (at z0)
    var shaft_cap0_center := Vector3(rotor_hub_x, rotor_hub_y, shaft_z0)
    for i in range(shaft_segments):
        var a0c: float = (float(i) / float(shaft_segments)) * TAU
        var a1c: float = (float(i + 1) / float(shaft_segments)) * TAU
    
        var p0 := Vector3(rotor_hub_x + cos(a0c) * shaft_radius, rotor_hub_y + sin(a0c) * shaft_radius, shaft_z0)
        var p1 := Vector3(rotor_hub_x + cos(a1c) * shaft_radius, rotor_hub_y + sin(a1c) * shaft_radius, shaft_z0)
    
        # Winding chosen to face outward-ish once normals are generated
        st.add_vertex(shaft_cap0_center); st.add_vertex(p1); st.add_vertex(p0)
    
    # Optional: cap the outer end of the shaft (at z1)
    var shaft_cap1_center := Vector3(rotor_hub_x, rotor_hub_y, shaft_z1)
    for i in range(shaft_segments):
        var a0d: float = (float(i) / float(shaft_segments)) * TAU
        var a1d: float = (float(i + 1) / float(shaft_segments)) * TAU
    
        var p0d := Vector3(rotor_hub_x + cos(a0d) * shaft_radius, rotor_hub_y + sin(a0d) * shaft_radius, shaft_z1)
        var p1d := Vector3(rotor_hub_x + cos(a1d) * shaft_radius, rotor_hub_y + sin(a1d) * shaft_radius, shaft_z1)
    
        st.add_vertex(shaft_cap1_center); st.add_vertex(p0d); st.add_vertex(p1d)

    # Create windmill sails (blades that catch the wind)
    # Real windmills have 4 sails arranged in a cross pattern, perpendicular to the ground
    var sail_length: float = base_radius * 4.0  # Long enough to be visible
    var sail_width: float = 3.0  # Thickness of the sail
    var sail_height: float = 0.6  # Height of the sail cross-section
    var sail_center_y: float = shaft_top_y + shaft_height * 0.5  # Center of the shaft



    # Rotor (vane cross) mounted at the shaft tip
    var hub_pos := Vector3(rotor_hub_x, rotor_hub_y, shaft_z1)
    
    # Blade sizing (uses your existing variables from the function)
    # sail_length: overall blade length (we use half as radius from hub)
    # sail_width:  blade width within the rotor plane
    # sail_height: blade thickness along the shaft axis (+Z)
    var blade_radius: float = sail_length * 0.50
    var half_w: float = sail_width * 0.50
    var half_d: float = sail_height * 0.50
    
    for vane_idx in range(4):
        var a: float = (float(vane_idx) / 4.0) * TAU  # 0, 90, 180, 270 degrees
    
        # Blade direction in the rotor plane (X/Y)
        var dir_x: float = cos(a)
        var dir_y: float = sin(a)
    
        # Perpendicular in-plane vector for blade width
        var perp_x: float = -dir_y
        var perp_y: float = dir_x
    
        var base_c := hub_pos
        var tip_c := Vector3(hub_pos.x + dir_x * blade_radius, hub_pos.y + dir_y * blade_radius, hub_pos.z)
    
        var off_w := Vector3(perp_x * half_w, perp_y * half_w, 0.0)
        var off_d := Vector3(0.0, 0.0, half_d)  # thickness along shaft axis (Z)
    
        # 8 corners (base: b1..b4, tip: t1..t4)
        var b1 := base_c + off_w + off_d
        var b2 := base_c - off_w + off_d
        var b3 := base_c - off_w - off_d
        var b4 := base_c + off_w - off_d
    
        var t1 := tip_c + off_w + off_d
        var t2 := tip_c - off_w + off_d
        var t3 := tip_c - off_w - off_d
        var t4 := tip_c + off_w - off_d
    
        # 6 faces (each is 2 triangles)
        # +Z face
        st.add_vertex(b1); st.add_vertex(b2); st.add_vertex(t2)
        st.add_vertex(b1); st.add_vertex(t2); st.add_vertex(t1)
    
        # -Z face
        st.add_vertex(b4); st.add_vertex(t4); st.add_vertex(t3)
        st.add_vertex(b4); st.add_vertex(t3); st.add_vertex(b3)
    
        # +width face
        st.add_vertex(b1); st.add_vertex(t1); st.add_vertex(t4)
        st.add_vertex(b1); st.add_vertex(t4); st.add_vertex(b4)
    
        # -width face
        st.add_vertex(b3); st.add_vertex(t3); st.add_vertex(t2)
        st.add_vertex(b3); st.add_vertex(t2); st.add_vertex(b2)
    
        # Hub end cap
        st.add_vertex(b4); st.add_vertex(b3); st.add_vertex(b2)
        st.add_vertex(b4); st.add_vertex(b2); st.add_vertex(b1)
    
        # Tip end cap
        st.add_vertex(t1); st.add_vertex(t2); st.add_vertex(t3)
        st.add_vertex(t1); st.add_vertex(t3); st.add_vertex(t4)
    
    # Optional: small hub “disk” (a short cylinder) to make the center look solid
    var hub_disk_radius: float = shaft_radius * 1.20
    var hub_disk_half: float = shaft_radius * 0.45
    var hub_z0: float = hub_pos.z - hub_disk_half
    var hub_z1: float = hub_pos.z + hub_disk_half
    var hub_segs: int = 12
    
    for i in range(hub_segs):
        var a0h: float = (float(i) / float(hub_segs)) * TAU
        var a1h: float = (float(i + 1) / float(hub_segs)) * TAU
    
        var x0h: float = cos(a0h) * hub_disk_radius
        var y0h: float = sin(a0h) * hub_disk_radius
        var x1h: float = cos(a1h) * hub_disk_radius
        var y1h: float = sin(a1h) * hub_disk_radius
    
        var hv00 := Vector3(hub_pos.x + x0h, hub_pos.y + y0h, hub_z0)
        var hv01 := Vector3(hub_pos.x + x1h, hub_pos.y + y1h, hub_z0)
        var hv10 := Vector3(hub_pos.x + x0h, hub_pos.y + y0h, hub_z1)
        var hv11 := Vector3(hub_pos.x + x1h, hub_pos.y + y1h, hub_z1)
    
        st.add_vertex(hv00); st.add_vertex(hv10); st.add_vertex(hv11)
        st.add_vertex(hv00); st.add_vertex(hv11); st.add_vertex(hv01)







    # Generate normals automatically and finalize mesh
    st.generate_normals()
    var mesh := st.commit()

    # Apply windmill-appropriate material (traditional pale colors)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.9, 0.85, 0.75)  # Light beige/white for traditional windmill
    mat.roughness = 0.85
    mat.metallic = 0.05
    mesh.surface_set_material(0, mat)

    return mesh

# Create blacksmith shop geometry with proper normals
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

    # Main building structure - define vertices
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

    # Define faces with proper winding order for outward normals (counter-clockwise when viewed from outside)
    var faces := [
        # Front face (facing +Z): 3(bottom-left), 2(bottom-right), 6(top-right), 7(top-left)
        [3, 2, 6, 7],  # front - facing viewer
        # Back face (facing -Z): 1(bottom-right), 0(bottom-left), 4(top-left), 5(top-right)
        [1, 0, 4, 5],  # back - facing away from viewer
        # Left face (facing -X): 0(bottom-back), 3(bottom-front), 7(top-front), 4(top-back)
        [0, 3, 7, 4],  # left - facing left
        # Right face (facing +X): 2(bottom-front), 1(bottom-back), 5(top-back), 6(top-front)
        [2, 1, 5, 6],  # right - facing right
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create a pitched roof instead of flat roof for better aesthetics
    var roof_peak_y: float = top_y + height * 0.2  # Peak of the roof
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable (triangular roof face)
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(front_center_top)  # peak
    st.add_vertex(corners[6])  # front-right-top

    # Back gable
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(back_center_top)  # peak
    st.add_vertex(corners[5])  # back-right-top

    # Left roof slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)  # back peak

    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)  # back peak
    st.add_vertex(front_center_top)  # front peak

    # Right roof slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)  # front peak
    st.add_vertex(back_center_top)  # back peak

    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)  # back peak
    st.add_vertex(corners[1])  # back-right-bottom

    # Bottom face (floor - normal pointing down)
    # Clockwise when viewed from below (outside of building)
    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(corners[3])  # front-left-bottom

    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[2])  # front-right-bottom

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
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 0: back-left-bottom
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z - chimney_hw),  # 1: back-right-bottom
        Vector3(chimney_x + chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 2: front-right-bottom
        Vector3(chimney_x - chimney_hw, chimney_base_y, chimney_z + chimney_hw),  # 3: front-left-bottom
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 4: back-left-top
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z - chimney_hw),  # 5: back-right-top
        Vector3(chimney_x + chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 6: front-right-top
        Vector3(chimney_x - chimney_hw, chimney_top_y, chimney_z + chimney_hw),  # 7: front-left-top
    ]

    var chimney_faces := [
        # Back face: 0, 1, 5, 4
        [0, 1, 5, 4],  # back
        # Right face: 1, 2, 6, 5
        [1, 2, 6, 5],  # right
        # Front face: 2, 3, 7, 6
        [2, 3, 7, 6],  # front
        # Left face: 3, 0, 4, 7
        [3, 0, 4, 7],  # left
    ]

    for face in chimney_faces:
        var v0 = chimney_corners[face[0]]
        var v1 = chimney_corners[face[1]]
        var v2 = chimney_corners[face[2]]
        var v3 = chimney_corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Chimney top (normal pointing up)
    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[7])  # front-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top

    st.add_vertex(chimney_corners[4])  # back-left-top
    st.add_vertex(chimney_corners[6])  # front-right-top
    st.add_vertex(chimney_corners[5])  # back-right-top

    # Bottom of chimney (normal pointing down)
    st.add_vertex(chimney_corners[1])  # back-right-bottom
    st.add_vertex(chimney_corners[0])  # back-left-bottom
    st.add_vertex(chimney_corners[3])  # front-left-bottom

    st.add_vertex(chimney_corners[1])  # back-right-bottom
    st.add_vertex(chimney_corners[3])  # front-left-bottom
    st.add_vertex(chimney_corners[2])  # front-right-bottom

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
    st.add_vertex(front_center_top)
    st.add_vertex(corners[2])  # front-bottom-right

    # Back gable
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-bottom-right

    # Roof slopes
    # Left slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)

    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Bottom face (floor - normal pointing down)
    # Clockwise when viewed from below (outside of building)
    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(corners[3])  # front-left-bottom

    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[2])  # front-right-bottom

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

        # Add bottom and top faces for each smokestack
        # Bottom face (normal pointing down)
        st.add_vertex(stack_corners[1])  # back-right-bottom
        st.add_vertex(stack_corners[0])  # back-left-bottom
        st.add_vertex(stack_corners[3])  # front-left-bottom

        st.add_vertex(stack_corners[1])  # back-right-bottom
        st.add_vertex(stack_corners[3])  # front-left-bottom
        st.add_vertex(stack_corners[2])  # front-right-bottom

        # Top face (normal pointing up)
        st.add_vertex(stack_corners[4])  # back-left-top
        st.add_vertex(stack_corners[7])  # front-left-top
        st.add_vertex(stack_corners[6])  # front-right-top

        st.add_vertex(stack_corners[4])  # back-left-top
        st.add_vertex(stack_corners[6])  # front-right-top
        st.add_vertex(stack_corners[5])  # back-right-top

    st.generate_normals()
    var mesh := st.commit()

    # Apply factory-appropriate material (dark gray/industrial)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)  # Dark gray
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)

    return mesh

# Create factory geometry using the improved template system
func _create_factory_geometry_template(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
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

    # Create walls
    for i in range(4):
        var next = (i + 1) % 4
        # Triangle 1: v0-v1-v2
        st.add_vertex(corners[i])
        st.add_vertex(corners[next])
        st.add_vertex(corners[next + 4])
        # Triangle 2: v0-v2-v3
        st.add_vertex(corners[i])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i + 4])

    # Gable roof (makes it look more industrial)
    var roof_peak_y: float = top_y + height * 0.2
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable
    st.add_vertex(corners[3])  # front-bottom-left
    st.add_vertex(front_center_top)
    st.add_vertex(corners[2])  # front-bottom-right

    # Back gable
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-bottom-right

    # Roof slopes
    # Left slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)

    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Factory smokestacks (main industrial feature)
    var stack_count: int = 2
    for i in range(stack_count):
        var stack_width: float = 1.2
        var stack_height: float = height * 1.5
        var stack_hw: float = stack_width * 0.5
        var stack_x: float = -hw * 0.6 + (i * hw * 1.2)
        var stack_z: float = -hd * 0.7
        var stack_base_y: float = roof_peak_y

        # Stack structure
        var stack_corners := [
            Vector3(stack_x - stack_hw, stack_base_y, stack_z - stack_hw),  # 0
            Vector3(stack_x + stack_hw, stack_base_y, stack_z - stack_hw),  # 1
            Vector3(stack_x + stack_hw, stack_base_y, stack_z + stack_hw),  # 2
            Vector3(stack_x - stack_hw, stack_base_y, stack_z + stack_hw),  # 3
            Vector3(stack_x - stack_hw, stack_height, stack_z - stack_hw),  # 4
            Vector3(stack_x + stack_hw, stack_height, stack_z - stack_hw),  # 5
            Vector3(stack_x + stack_hw, stack_height, stack_z + stack_hw),  # 6
            Vector3(stack_x - stack_hw, stack_height, stack_z + stack_hw),  # 7
        ]

        # Create stack sides
        for j in range(4):
            var next = (j + 1) % 4
            # Triangle 1
            st.add_vertex(stack_corners[j])
            st.add_vertex(stack_corners[next])
            st.add_vertex(stack_corners[next + 4])
            # Triangle 2
            st.add_vertex(stack_corners[j])
            st.add_vertex(stack_corners[next + 4])
            st.add_vertex(stack_corners[j + 4])

    st.generate_normals()
    var mesh := st.commit()

    # Apply factory-appropriate material (dark gray/industrial)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)  # Dark gray
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)

    return mesh
    
    # Use direct factory implementation (template system avoided due to class issues)
    return _create_factory_geometry_template(plot, rng)

# Create fallback factory (simple box structure)
func _create_fallback_factory(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Simple factory box
    var width = max(plot.lot_width * 0.9, 8.0)
    var depth = max(plot.lot_depth * 0.8, 6.0)
    var height = rng.randf_range(10.0, 18.0)
    
    var hw = width * 0.5
    var hd = depth * 0.5
    
    # Simple box
    var corners = [
        Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd),
        Vector3(-hw, height, -hd), Vector3(hw, height, -hd), Vector3(hw, height, hd), Vector3(-hw, height, hd)
    ]
    
    # Walls
    for i in range(4):
        var next = (i + 1) % 4
        st.add_vertex(corners[i])
        st.add_vertex(corners[next])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i + 4])
    
    # Roof
    st.add_vertex(corners[4])
    st.add_vertex(corners[7])
    st.add_vertex(corners[6])
    st.add_vertex(corners[4])
    st.add_vertex(corners[6])
    st.add_vertex(corners[5])
    
    st.generate_normals()
    var mesh = st.commit()
    
    # Basic material
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.3, 0.35)
    mat.roughness = 0.95
    mesh.surface_set_material(0, mat)
    
    return mesh
    
# Create castle geometry using direct implementation
func _create_castle_geometry_template(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
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

    # Create walls
    for i in range(4):
        var next = (i + 1) % 4
        # Triangle 1: v0-v1-v2
        st.add_vertex(corners[i])
        st.add_vertex(corners[next])
        st.add_vertex(corners[next + 4])
        # Triangle 2: v0-v2-v3
        st.add_vertex(corners[i])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i + 4])

    # Flat roof
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(corners[5])  # back-right-top

    # Castle battlements (crenellations) - main castle feature
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

        # Front face of battlement
        st.add_vertex(Vector3(x_pos - bw, top_y, z_pos - bd))
        st.add_vertex(Vector3(x_pos + bw, top_y, z_pos - bd))
        st.add_vertex(Vector3(x_pos + bw, top_y + bh, z_pos - bd))

        # Back face
        st.add_vertex(Vector3(x_pos + bw, top_y, z_pos + bd))
        st.add_vertex(Vector3(x_pos - bw, top_y, z_pos + bd))
        st.add_vertex(Vector3(x_pos + bw, top_y + bh, z_pos + bd))

        # Side faces
        st.add_vertex(Vector3(x_pos + bw, top_y, z_pos - bd))
        st.add_vertex(Vector3(x_pos + bw, top_y, z_pos + bd))
        st.add_vertex(Vector3(x_pos + bw, top_y + bh, z_pos + bd))
        st.add_vertex(Vector3(x_pos + bw, top_y, z_pos - bd))
        st.add_vertex(Vector3(x_pos + bw, top_y + bh, z_pos + bd))

    # Corner towers - another main castle feature
    var tower_radius: float = 3.0
    var tower_height: float = height * 1.3
    var sides: int = 8
    
    # Corner positions
    var tower_positions = [
        Vector3(-hw + tower_radius, 0, hd - tower_radius),  # Front-left
        Vector3(hw - tower_radius, 0, hd - tower_radius),  # Front-right
        Vector3(hw - tower_radius, 0, -hd + tower_radius),  # Back-right
        Vector3(-hw + tower_radius, 0, -hd + tower_radius),  # Back-left
    ]

    # Generate corner towers
    for tower_pos in tower_positions:
        for i in range(sides):
            var angle1: float = (float(i) / float(sides)) * TAU
            var angle2: float = (float(i + 1) / float(sides)) * TAU

            # Calculate tower vertices
            var x1: float = tower_pos.x + cos(angle1) * tower_radius
            var z1: float = tower_pos.z + sin(angle1) * tower_radius
            var x2: float = tower_pos.x + cos(angle2) * tower_radius
            var z2: float = tower_pos.z + sin(angle2) * tower_radius

            # Tower wall triangles
            st.add_vertex(Vector3(x1, top_y, z1))
            st.add_vertex(Vector3(x2, top_y, z2))
            st.add_vertex(Vector3(x2, tower_height, z2))
            st.add_vertex(Vector3(x1, top_y, z1))
            st.add_vertex(Vector3(x2, tower_height, z2))
            st.add_vertex(Vector3(x1, tower_height, z1))

    st.generate_normals()
    var mesh := st.commit()

    # Apply castle-appropriate material
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.5, 0.5, 0.55)  # Stone gray
    mat.roughness = 0.9
    mesh.surface_set_material(0, mat)

    return mesh
    
    # Use direct castle implementation (template system avoided due to class issues)
    return _create_castle_geometry_template(plot, rng)

# Create fallback castle (simple box with battlements)
func _create_fallback_castle(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Simple castle box
    var width = plot.lot_width * 0.9
    var depth = plot.lot_depth * 0.9
    var height = rng.randf_range(15.0, 25.0)
    
    var hw = width * 0.5
    var hd = depth * 0.5
    
    # Main building
    var corners = [
        Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd),
        Vector3(-hw, height, -hd), Vector3(hw, height, -hd), Vector3(hw, height, hd), Vector3(-hw, height, hd)
    ]
    
    # Walls
    for i in range(4):
        var next = (i + 1) % 4
        st.add_vertex(corners[i])
        st.add_vertex(corners[next])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i])
        st.add_vertex(corners[next + 4])
        st.add_vertex(corners[i + 4])
    
    # Flat roof
    st.add_vertex(corners[4])
    st.add_vertex(corners[7])
    st.add_vertex(corners[6])
    st.add_vertex(corners[4])
    st.add_vertex(corners[6])
    st.add_vertex(corners[5])
    
    # Simple battlements
    var battlement_height = 2.0
    var battlement_width = 0.5
    var battlements = 8
    
    for i in range(battlements):
        var t = float(i) / float(battlements - 1)
        var x_pos = -hw + (hw * 2.0) * t
        var z_pos = hd if i < battlements / 2 else -hd
        
        # Create small battlement box
        var bw = battlement_width * 0.5
        st.add_vertex(Vector3(x_pos - bw, height, z_pos - bw))
        st.add_vertex(Vector3(x_pos + bw, height, z_pos - bw))
        st.add_vertex(Vector3(x_pos + bw, height + battlement_height, z_pos - bw))
        st.add_vertex(Vector3(x_pos - bw, height, z_pos - bw))
        st.add_vertex(Vector3(x_pos + bw, height + battlement_height, z_pos - bw))
        st.add_vertex(Vector3(x_pos - bw, height + battlement_height, z_pos - bw))
    
    st.generate_normals()
    var mesh = st.commit()
    
    # Basic material
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.5, 0.5, 0.55)
    mat.roughness = 0.9
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

    # Pitched roof using proper wall-top connections
    var roof_height: float = min(width, depth) * 0.4  # Traditional roof pitch
    var roof_peak_y: float = top_y + roof_height
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var back_center_top = Vector3(0, roof_peak_y, -hd)

    # Front gable triangle (top corners, not bottom!)
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(front_center_top)

    # Back gable triangle (top corners, not bottom!)
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(corners[5])  # back-right-top
    st.add_vertex(back_center_top)

    # Left roof slope - connect top corners to ridge
    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(corners[4])  # back-left-top
    st.add_vertex(back_center_top)

    st.add_vertex(corners[7])  # front-left-top
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right roof slope - connect top corners to ridge
    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(corners[6])  # front-right-top
    st.add_vertex(back_center_top)
    st.add_vertex(corners[5])  # back-right-top

    st.generate_normals()
    var mesh := st.commit()

    # Apply house-appropriate material (warm colors)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.85, 0.75, 0.6)  # Warm tan/beige
    mat.roughness = 0.85
    mesh.surface_set_material(0, mat)

    return mesh

# Create stone cottage NEW geometry using template system
func _create_stone_cottage_new_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    print("CREATING NEW STONE COTTAGE")
    # Use the unified building system to generate a proper stone cottage
    if ctx.unified_building_system == null:
        # Fallback to old method if unified system not available
        return _create_stone_cottage_new_geometry_legacy(plot, rng)

    # Create a clean little stone cottage from scratch
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    # Cottage dimensions - proper proportions for a cozy cottage
    var width: float = max(plot.lot_width * 0.8, 4.5)
    var depth: float = max(plot.lot_depth * 0.8, 4.0)
    var wall_height: float = 3.5  # Single story cottage
    var roof_height: float = wall_height * 0.5  # Steep traditional roof
    
    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var wall_top_y: float = wall_height
    var roof_peak_y: float = wall_height + roof_height
    
    # Define main structure corners (no randomization)
    var wall_corners := [
        Vector3(-hw, base_y, -hd),   # 0: back-left-bottom
        Vector3(hw, base_y, -hd),    # 1: back-right-bottom
        Vector3(hw, base_y, hd),     # 2: front-right-bottom
        Vector3(-hw, base_y, hd),    # 3: front-left-bottom
        Vector3(-hw, wall_top_y, -hd),   # 4: back-left-top
        Vector3(hw, wall_top_y, -hd),    # 5: back-right-top
        Vector3(hw, wall_top_y, hd),     # 6: front-right-top
        Vector3(-hw, wall_top_y, hd),    # 7: front-left-top
    ]
    
    # Create clean stone walls
    _create_fallback_walls(st, wall_corners)
    
    # Create proper gabled roof
    _create_fallback_roof(st, wall_corners, roof_peak_y)
    
    # Add a simple stone chimney
    _create_simple_chimney(st, width, depth, wall_height, roof_peak_y, rng)
    
    # Generate proper normals
    st.generate_normals()
    
    var mesh := st.commit()
    
    # Apply stone cottage material
    var mat := StandardMaterial3D.new()
#    mat.albedo_color = Color(0.65, 0.6, 0.5)  # Warm stone color
#    mat.roughness = 0.9
#    mat.metallic = 0.0
#    mat.normal_scale = 0.2
#    mesh.surface_set_material(0, mat)

    mat.albedo_color = Color(0.0, 0.0, 1.0)  # Warm stone color
    mat.roughness = 0.0
    mat.metallic = 1.0
    mat.normal_scale = 1.0
    mesh.surface_set_material(0, mat)
    
    return mesh

# Legacy stone cottage NEW geometry for fallback
func _create_stone_cottage_new_geometry_legacy(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    print("CREATING LEGACY STONE COTTAGE")
    # Randomly choose cottage style (stone vs thatched)
    var use_stone: bool = rng.randf() > 0.5

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Cottage dimensions - rustic, cozy proportions
    var width: float = max(plot.lot_width * 0.7, 4.5)
    var depth: float = max(plot.lot_depth * 0.6, 4.0)
    var wall_height: float = rng.randf_range(3.5, 5.0)
    var roof_height: float = wall_height * 0.4  # Traditional steep roof
    if not use_stone:
        roof_height = wall_height * 0.5  # Steeper thatched roof

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var wall_top_y: float = wall_height
    var roof_peak_y: float = wall_height + roof_height

    # Define main structure corners
    var wall_corners := [
        Vector3(-hw, base_y, -hd),   # 0: back-left-bottom
        Vector3(hw, base_y, -hd),    # 1: back-right-bottom
        Vector3(hw, base_y, hd),     # 2: front-right-bottom
        Vector3(-hw, base_y, hd),    # 3: front-left-bottom
        Vector3(-hw, wall_top_y, -hd),   # 4: back-left-top
        Vector3(hw, wall_top_y, -hd),    # 5: back-right-top
        Vector3(hw, wall_top_y, hd),     # 6: front-right-top
        Vector3(-hw, wall_top_y, hd),    # 7: front-left-top
    ]

    # Add slight randomization for rustic charm
    var rustic_offset := rng.randf_range(-0.1, 0.1)
    for i in range(wall_corners.size()):
        if i >= 4:  # Only affect top corners
            wall_corners[i].x += rustic_offset
            wall_corners[i].z += rustic_offset * 0.5

    # Create walls using fallback helper
    _create_fallback_walls(st, wall_corners)

    # Create cottage roof with proper normals
    _create_fallback_roof(st, wall_corners, roof_peak_y)

    # Add chimney (simplified)
    _create_simple_chimney(st, width, depth, wall_height, roof_peak_y, rng)

    # Ensure proper normals for solid appearance
    st.generate_normals()

    var mesh := st.commit()

    # Apply appropriate material based on style
    var mat := StandardMaterial3D.new()
    if use_stone:
        mat.albedo_color = Color(0.6, 0.55, 0.45)  # Stone gray-brown
        mat.roughness = 0.95  # Very rough stone surface
    else:
        mat.albedo_color = Color(0.6, 0.4, 0.2)  # Thatched brown
        mat.roughness = 0.9  # Rough thatch

    mat.metallic = 0.0
    mat.normal_scale = 0.3  # Enhance surface detail
    mesh.surface_set_material(0, mat)

    return mesh

# Create stone cottage geometry using the new template system
func _create_stone_cottage_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    # Use the unified building system to generate a proper stone cottage
    if ctx.unified_building_system == null:
        # Fallback to old method if unified system not available
        var mesh = _create_stone_cottage_geometry_legacy(plot, rng)
        return mesh

    # Generate using template system for proper quality
    var template_name = "stone_cottage_classic"
    var width = max(plot.lot_width * 0.8, 5.0)
    var depth = max(plot.lot_depth * 0.8, 4.0)
    var height = rng.randf_range(4.0, 6.0)
    var floors = 1

    var mesh = ctx.unified_building_system.generate_parametric_building_with_template(
        template_name,
        "stone_cottage",  # Use the actual building type
        width,
        depth,
        height,
        floors,
        2  # quality level
    )

    return mesh

# Legacy stone cottage geometry for fallback
func _create_stone_cottage_geometry_legacy(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    # Randomly choose cottage style (stone vs thatched)
    var use_stone: bool = rng.randf() > 0.5

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Cottage dimensions - rustic, cozy proportions
    var width: float = max(plot.lot_width * 0.7, 4.5)
    var depth: float = max(plot.lot_depth * 0.6, 4.0)
    var wall_height: float = rng.randf_range(3.5, 5.0)
    var roof_height: float = wall_height * 0.4  # Traditional steep roof
    if not use_stone:
        roof_height = wall_height * 0.5  # Steeper thatched roof

    var hw: float = width * 0.5
    var hd: float = depth * 0.5
    var base_y: float = 0.0
    var wall_top_y: float = wall_height
    var roof_peak_y: float = wall_height + roof_height

    # Define main structure corners
    var wall_corners := [
        Vector3(-hw, base_y, -hd),   # 0: back-left-bottom
        Vector3(hw, base_y, -hd),    # 1: back-right-bottom
        Vector3(hw, base_y, hd),     # 2: front-right-bottom
        Vector3(-hw, base_y, hd),    # 3: front-left-bottom
        Vector3(-hw, wall_top_y, -hd),   # 4: back-left-top
        Vector3(hw, wall_top_y, -hd),    # 5: back-right-top
        Vector3(hw, wall_top_y, hd),     # 6: front-right-top
        Vector3(-hw, wall_top_y, hd),    # 7: front-left-top
    ]

    # Add slight randomization for rustic charm
    var rustic_offset := rng.randf_range(-0.1, 0.1)
    for i in range(wall_corners.size()):
        if i >= 4:  # Only affect top corners
            wall_corners[i].x += rustic_offset
            wall_corners[i].z += rustic_offset * 0.5

    # Create walls using fallback helper
    _create_fallback_walls(st, wall_corners)

    # Create cottage roof
    _create_fallback_roof(st, wall_corners, roof_peak_y)

    # Add chimney (simplified)
    _create_simple_chimney(st, width, depth, wall_height, roof_peak_y, rng)

    # Ensure proper normals for solid appearance
    st.generate_normals()

    var mesh := st.commit()

    # Apply appropriate material based on style
    var mat := StandardMaterial3D.new()
    if use_stone:
        mat.albedo_color = Color(0.6, 0.55, 0.45)  # Stone gray-brown
        mat.roughness = 0.95  # Very rough stone surface
    else:
        mat.albedo_color = Color(0.6, 0.4, 0.2)  # Thatched brown
        mat.roughness = 0.9  # Rough thatch

    mat.metallic = 0.0
    mat.normal_scale = 0.3  # Enhance surface detail
    mesh.surface_set_material(0, mat)

    return mesh

# Function to get building configuration from unified registry
func _get_building_config(building_type: String) -> BuildingConfig:
    var registry = BuildingTypeRegistry.new()
    return registry.get_building_config(building_type)

# Function to check if building type uses template system
func _uses_template_system(building_type: String) -> bool:
    var config = _get_building_config(building_type)
    return config.preferred_template != "" and ctx.unified_building_system != null

func _create_simple_chimney(st: SurfaceTool, width: float, depth: float, wall_height: float, roof_peak_y: float, rng: RandomNumberGenerator) -> void:
    var chimney_x := width * 0.3
    var chimney_z := depth * 0.2
    var chimney_width := 0.8
    var chimney_depth := 0.8
    var chimney_height := roof_peak_y + rng.randf_range(1.5, 2.5)

    var chw: float = chimney_width * 0.5
    var chd := chimney_depth * 0.5

    # Chimney corners - base at wall_height (top of the wall)
    var chimney_corners: Array[Vector3] = [
        Vector3(chimney_x - chw, wall_height, chimney_z - chd),   # 0: bottom-left-back
        Vector3(chimney_x + chw, wall_height, chimney_z - chd),   # 1: bottom-right-back
        Vector3(chimney_x + chw, wall_height, chimney_z + chd),   # 2: bottom-right-front
        Vector3(chimney_x - chw, wall_height, chimney_z + chd),   # 3: bottom-left-front
        Vector3(chimney_x - chw, chimney_height, chimney_z - chd), # 4: top-left-back
        Vector3(chimney_x + chw, chimney_height, chimney_z - chd), # 5: top-right-back
        Vector3(chimney_x + chw, chimney_height, chimney_z + chd), # 6: top-right-front
        Vector3(chimney_x - chw, chimney_height, chimney_z + chd), # 7: top-left-front
    ]

    # Create chimney sides
    # Front face
    st.add_vertex(chimney_corners[3])  # bottom-left
    st.add_vertex(chimney_corners[2])  # bottom-right
    st.add_vertex(chimney_corners[6])  # top-right

    st.add_vertex(chimney_corners[3])  # bottom-left
    st.add_vertex(chimney_corners[6])  # top-right
    st.add_vertex(chimney_corners[7])  # top-left

    # Back face
    st.add_vertex(chimney_corners[0])  # bottom-left
    st.add_vertex(chimney_corners[4])  # top-left
    st.add_vertex(chimney_corners[5])  # top-right

    st.add_vertex(chimney_corners[0])  # bottom-left
    st.add_vertex(chimney_corners[5])  # top-right
    st.add_vertex(chimney_corners[1])  # bottom-right

    # Left face
    st.add_vertex(chimney_corners[0])  # bottom-back
    st.add_vertex(chimney_corners[3])  # bottom-front
    st.add_vertex(chimney_corners[7])  # top-front

    st.add_vertex(chimney_corners[0])  # bottom-back
    st.add_vertex(chimney_corners[7])  # top-front
    st.add_vertex(chimney_corners[4])  # top-back

    # Right face
    st.add_vertex(chimney_corners[1])  # bottom-back
    st.add_vertex(chimney_corners[5])  # top-back
    st.add_vertex(chimney_corners[6])  # top-front

    st.add_vertex(chimney_corners[1])  # bottom-back
    st.add_vertex(chimney_corners[6])  # top-front
    st.add_vertex(chimney_corners[2])  # bottom-front

    # Apply chimney material (dark brick/stone)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.3, 0.25, 0.2)  # Dark gray-brown for chimney
    mat.roughness = 0.9  # Rough surface
    mat.metallic = 0.0
    mat.normal_scale = 0.3  # Enhance surface detail


# Create radio tower geometry with lattice structure
func _create_radio_tower_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    return RadioTowerGeometry.create(plot, rng)

# Create grain silo geometry
func _create_grain_silo_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    return GrainSiloGeometry.create(plot, rng)

# Create corn feeder geometry
func _create_corn_feeder_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    return CornFeederGeometry.create(plot, rng)

func _create_lighthouse_geometry(plot: Dictionary, rng: RandomNumberGenerator) -> Mesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Lighthouse specifications
    var base_radius: float = max(plot.lot_width * 0.25, 3.0)  # Base radius
    var top_radius: float = base_radius * 0.6  # Tapered but not too much
    var tower_height: float = rng.randf_range(25.0, 45.0)  # Tall enough to be distinctive
    var lamp_house_height: float = 4.0  # Lantern room height
    var gallery_overhang: float = 0.8  # How far gallery extends from tower

    var sides: int = 16  # More sides for smoother appearance
    var base_y: float = 0.0
    var tower_top_y: float = tower_height
    var lamp_house_top_y: float = tower_top_y + lamp_house_height

    # Create main tapered tower with proper normals
    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Calculate radii at bottom and top of this segment
        var x1_bot: float = cos(angle1) * base_radius
        var z1_bot: float = sin(angle1) * base_radius
        var x2_bot: float = cos(angle2) * base_radius
        var z2_bot: float = sin(angle2) * base_radius

        var x1_top: float = cos(angle1) * top_radius
        var z1_top: float = sin(angle1) * top_radius
        var x2_top: float = cos(angle2) * top_radius
        var z2_top: float = sin(angle2) * top_radius

        # Define vertices
        var v0 := Vector3(x1_bot, base_y, z1_bot)  # Bottom left
        var v1 := Vector3(x2_bot, base_y, z2_bot)  # Bottom right
        var v2 := Vector3(x2_top, tower_top_y, z2_top)  # Top right
        var v3 := Vector3(x1_top, tower_top_y, z1_top)  # Top left

        # Add face with proper winding (counter-clockwise for outward normals)
        # Triangle 1: v0-v1-v2
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create lantern room (the glass-enclosed light chamber at the top)
    var lamp_house_radius: float = top_radius * 0.9  # Slightly smaller than tower top

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Lantern room walls
        var x1: float = cos(angle1) * lamp_house_radius
        var z1: float = sin(angle1) * lamp_house_radius
        var x2: float = cos(angle2) * lamp_house_radius
        var z2: float = sin(angle2) * lamp_house_radius

        var v0 := Vector3(x1, tower_top_y, z1)
        var v1 := Vector3(x2, tower_top_y, z2)
        var v2 := Vector3(x2, lamp_house_top_y, z2)
        var v3 := Vector3(x1, lamp_house_top_y, z1)

        # Add lantern room walls with proper winding
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Create domed top of lantern room
    var dome_segments: int = 6
    var dome_radius: float = lamp_house_radius * 0.95

    for seg in range(dome_segments):
        var y1: float = tower_top_y + (float(seg) / float(dome_segments)) * lamp_house_height * 0.8
        var y2: float = tower_top_y + (float(seg + 1) / float(dome_segments)) * lamp_house_height * 0.8

        var r1: float = lerp(dome_radius, 0.0, float(seg) / float(dome_segments))
        var r2: float = lerp(dome_radius, 0.0, float(seg + 1) / float(dome_segments))

        for i in range(sides):
            var angle1: float = (float(i) / float(sides)) * TAU
            var angle2: float = (float(i + 1) / float(sides)) * TAU

            var x1_1: float = cos(angle1) * r1
            var z1_1: float = sin(angle1) * r1
            var x1_2: float = cos(angle1) * r2
            var z1_2: float = sin(angle1) * r2
            var x2_1: float = cos(angle2) * r1
            var z2_1: float = sin(angle2) * r1
            var x2_2: float = cos(angle2) * r2
            var z2_2: float = sin(angle2) * r2

            var v1 := Vector3(x1_1, y1, z1_1)
            var v2 := Vector3(x2_1, y1, z2_1)
            var v3 := Vector3(x2_2, y2, z2_2)
            var v4 := Vector3(x1_2, y2, z1_2)

            # Add dome segment face with proper winding
            st.add_vertex(v1)
            st.add_vertex(v2)
            st.add_vertex(v3)

            st.add_vertex(v1)
            st.add_vertex(v3)
            st.add_vertex(v4)

    # Create observation gallery (the walkway around the lantern room)
    var gallery_start_y: float = tower_top_y + lamp_house_height * 0.3  # Positioned partway up lantern room
    var inner_radius: float = top_radius * 1.05  # Slightly larger than tower
    var outer_radius: float = inner_radius + gallery_overhang
    var gallery_height: float = 0.1  # Thin platform
    var rail_height: float = 1.1  # Standard railing height

    for i in range(sides):
        var angle1: float = (float(i) / float(sides)) * TAU
        var angle2: float = (float(i + 1) / float(sides)) * TAU

        # Inner circle points
        var ix1: float = cos(angle1) * inner_radius
        var iz1: float = sin(angle1) * inner_radius
        var ix2: float = cos(angle2) * inner_radius
        var iz2: float = sin(angle2) * inner_radius

        # Outer circle points
        var ox1: float = cos(angle1) * outer_radius
        var oz1: float = sin(angle1) * outer_radius
        var ox2: float = cos(angle2) * outer_radius
        var oz2: float = sin(angle2) * outer_radius

        # Gallery floor (at gallery_start_y)
        var floor_y: float = gallery_start_y
        var railing_y: float = floor_y + rail_height

        var iv0 := Vector3(ix1, floor_y, iz1)
        var iv1 := Vector3(ix2, floor_y, iz2)
        var ov0 := Vector3(ox1, floor_y, oz1)
        var ov1 := Vector3(ox2, floor_y, oz2)

        # Gallery floor surface (normal pointing down)
        st.add_vertex(iv0)
        st.add_vertex(ov1)
        st.add_vertex(ov0)

        st.add_vertex(iv0)
        st.add_vertex(iv1)
        st.add_vertex(ov1)

        # Gallery railing posts (simple vertical cylinders)
        var post_height: float = rail_height
        var post_radius: float = 0.08

        # Create small post at corner
        for j in range(8):  # 8-sided post
            var p_angle1: float = (float(j) / 8.0) * TAU
            var p_angle2: float = (float(j + 1) / 8.0) * TAU

            var px1: float = cos(p_angle1) * post_radius
            var pz1: float = sin(p_angle1) * post_radius
            var px2: float = cos(p_angle2) * post_radius
            var pz2: float = sin(p_angle2) * post_radius

            var post_v0 := Vector3(ox1 + px1, floor_y, oz1 + pz1)
            var post_v1 := Vector3(ox1 + px2, floor_y, oz1 + pz2)
            var post_v2 := Vector3(ox1 + px2, railing_y, oz1 + pz2)
            var post_v3 := Vector3(ox1 + px1, railing_y, oz1 + pz1)

            # Post face with proper winding
            st.add_vertex(post_v0)
            st.add_vertex(post_v1)
            st.add_vertex(post_v2)

            st.add_vertex(post_v0)
            st.add_vertex(post_v2)
            st.add_vertex(post_v3)

    st.generate_normals()
    var mesh := st.commit()

    # Apply lighthouse-appropriate material (white with some gray accents)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.98, 0.98, 0.95)  # Bright white
    mat.roughness = 0.85
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

    # Define faces with proper winding order for outward normals (counter-clockwise when viewed from outside)
    var faces := [
        # Front face: 3(bottom-left), 2(bottom-right), 6(top-right), 7(top-left)
        [3, 2, 6, 7],  # front - facing +Z
        # Back face: 1(bottom-right), 0(bottom-left), 4(top-left), 5(top-right)
        [1, 0, 4, 5],  # back - facing -Z
        # Left face: 0(bottom-back), 3(bottom-front), 7(top-front), 4(top-back)
        [0, 3, 7, 4],  # left - facing -X
        # Right face: 2(bottom-front), 1(bottom-back), 5(top-back), 6(top-front)
        [2, 1, 5, 6],  # right - facing +X
    ]

    for face in faces:
        var v0 = corners[face[0]]
        var v1 = corners[face[1]]
        var v2 = corners[face[2]]
        var v3 = corners[face[3]]

        # Triangle 1: v0-v1-v2 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v1)
        st.add_vertex(v2)

        # Triangle 2: v0-v2-v3 (counter-clockwise for outward normals)
        st.add_vertex(v0)
        st.add_vertex(v2)
        st.add_vertex(v3)

    # Bottom face (normal pointing down)
    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(corners[3])  # front-left-bottom

    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[2])  # front-right-bottom

    # Gable roof (triangle on front/back)
    var roof_peak_y: float = top_y + roof_height

    # Front gable (triangular roof face)
    var front_center_top = Vector3(0, roof_peak_y, hd)
    var front_bottom_left = Vector3(-hw, top_y, hd)
    var front_bottom_right = Vector3(hw, top_y, hd)

    # Triangle pointing outward (counter-clockwise when viewed from front)
    st.add_vertex(front_bottom_left)
    st.add_vertex(front_bottom_right)
    st.add_vertex(front_center_top)

    # Back gable
    var back_center_top = Vector3(0, roof_peak_y, -hd)
    var back_bottom_left = Vector3(-hw, top_y, -hd)
    var back_bottom_right = Vector3(hw, top_y, -hd)

    # Triangle pointing outward (counter-clockwise when viewed from back)
    st.add_vertex(back_bottom_right)
    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)

    # Roof sides (connect roof peak to roof edges)
    # Left roof slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(front_bottom_left)
    st.add_vertex(back_bottom_left)
    st.add_vertex(back_center_top)

    st.add_vertex(front_bottom_left)
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right roof slope - ensure counter-clockwise winding for outward normals
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
    st.add_vertex(front_center_top)
    st.add_vertex(corners[2])  # front-bottom-right

    # Back gable
    st.add_vertex(corners[0])  # back-bottom-left
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-bottom-right

    # Roof slopes
    # Left slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(back_center_top)

    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(front_center_top)

    # Right slope - ensure counter-clockwise winding for outward normals
    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(front_center_top)
    st.add_vertex(back_center_top)

    st.add_vertex(corners[2])  # front-right-bottom
    st.add_vertex(back_center_top)
    st.add_vertex(corners[1])  # back-right-bottom

    # Bottom face (floor - normal pointing down)
    # Clockwise when viewed from below (outside of building)
    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[0])  # back-left-bottom
    st.add_vertex(corners[3])  # front-left-bottom

    st.add_vertex(corners[1])  # back-right-bottom
    st.add_vertex(corners[3])  # front-left-bottom
    st.add_vertex(corners[2])  # front-right-bottom

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

    # Spire bottom face (normal pointing down)
    st.add_vertex(spire_corners[1])  # back-right-bottom
    st.add_vertex(spire_corners[0])  # back-left-bottom
    st.add_vertex(spire_corners[3])  # front-left-bottom

    st.add_vertex(spire_corners[1])  # back-right-bottom
    st.add_vertex(spire_corners[3])  # front-left-bottom
    st.add_vertex(spire_corners[2])  # front-right-bottom

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
    building.set_meta("name", "SimpleBuilding_%d" % rng.randi())
    building.set_meta("building_type", plot.get("building_type", "simple"))
    building.set_meta("building_category", "building")
    var mesh := _generate_building_mesh(plot, rng)
    building.mesh = mesh
    building.position = pos
    building.rotation.y = plot.yaw

    # Determine specific building type for labeling purposes
    var building_type: String = ""
    if plot.has("specific_building_type"):
        building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        building_type = plot.building_subtype
    elif plot.has("building_variant"):
        building_type = plot.building_variant
    elif plot.has("building_category"):
        building_type = plot.building_category
    elif plot.has("building_type"):
        building_type = plot.building_type
    elif plot.has("subtype"):
        building_type = plot.subtype
    elif plot.has("variant"):
        building_type = plot.variant
    elif plot.has("category"):
        building_type = plot.category
    elif plot.has("type"):
        building_type = plot.type
    elif plot.has("style"):
        building_type = plot.style
    else:
        building_type = plot.get("density_class", "rural")

    # Update the plot with the detected building type so labels can use it
    plot["building_type"] = building_type

    # Allow specific building types to override density class
    var specific_density_class: String = _get_preferred_density_class(building_type)
    if specific_density_class != "":
        plot["density_class"] = specific_density_class

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

    # Determine building type with priority for specific types
    var building_type: String = ""
    if plot.has("specific_building_type"):
        building_type = plot.specific_building_type
    elif plot.has("building_subtype"):
        building_type = plot.building_subtype
    elif plot.has("building_variant"):
        building_type = plot.building_variant
    elif plot.has("building_category"):
        building_type = plot.building_category
    elif plot.has("building_type"):
        building_type = plot.building_type
    elif plot.has("subtype"):
        building_type = plot.subtype
    elif plot.has("variant"):
        building_type = plot.variant
    elif plot.has("category"):
        building_type = plot.category
    elif plot.has("type"):
        building_type = plot.type
    elif plot.has("style"):
        building_type = plot.style
    else:
        building_type = plot.get("density_class", "rural")

    # Building type affects color
    var color := Color.WHITE
    match building_type:
        "commercial":
            color = Color(0.7, 0.7, 0.8)  # Gray/blue commercial
        "residential":
            color = Color(0.9, 0.85, 0.7)  # Warm residential
        "mixed":
            color = Color(0.8, 0.8, 0.75)  # Mixed
        "rural":
            color = Color(0.85, 0.75, 0.6)  # Earthy rural
        # Specific building types
        "windmill", "mill", "radio_tower", "grain_silo", "corn_feeder", "barn", "blacksmith", "farmhouse", "stable", "gristmill", "sawmill", "outbuilding", "granary", "fishing_hut", "shepherd_hut":
            color = Color(0.6, 0.5, 0.4)  # Earthy brown for rural buildings
        "factory", "industrial", "factory_building", "warehouse", "workshop", "foundry", "mill_factory", "power_station", "sawmill", "oil_mill", "paper_mill", "brewery", "distillery", "granary", "armory", "guard_house", "watchtower", "gatehouse":
            color = Color(0.5, 0.5, 0.6)  # Industrial gray
        "castle", "fortress", "castle_keep", "tower", "fort", "keep", "bastion", "redoubt", "barracks", "monastery", "church", "cathedral":
            color = Color(0.6, 0.6, 0.65)  # Stone gray
        "stone_cottage", "stone_cabin", "thatched_cottage", "cottage", "rustic_cabin", "log_chalet", "timber_cabin", "house_victorian", "house_colonial", "house_tudor", "manor", "mansion", "villa", "cabin", "villa_italian", "farmhouse", "homestead":
            color = Color(0.8, 0.75, 0.65)  # Warm residential with variation
        _:
            # Default based on density class if no specific type matched
            match plot.density_class:
                "commercial":
                    color = Color(0.7, 0.7, 0.8)  # Gray/blue commercial
                "residential":
                    color = Color(0.9, 0.85, 0.7)  # Warm residential
                "mixed":
                    color = Color(0.8, 0.8, 0.75)  # Mixed
                "rural":
                    color = Color(0.85, 0.75, 0.6)  # Earthy rural
                _:
                    color = Color(0.85, 0.75, 0.65)  # Default warm color
    

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

# Helper function to create fallback walls
func _create_fallback_walls(st: SurfaceTool, corners: PackedVector3Array) -> void:
    # Front wall - counter-clockwise winding for outward normal
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[3])  # front-left-bottom
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[2])  # front-right-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[6])  # front-right-top

    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[3])  # front-left-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[6])  # front-right-top
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[7])  # front-left-top

    # Back wall - counter-clockwise winding for outward normal
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1])  # back-right-bottom
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0])  # back-left-bottom
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[4])  # back-left-top

    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1])  # back-right-bottom
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[4])  # back-left-top
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[5])  # back-right-top

    # Left wall - counter-clockwise winding for outward normal
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0])  # back-left-bottom
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[3])  # front-left-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[7])  # front-left-top

    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0])  # back-left-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[7])  # front-left-top
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[4])  # back-left-top

    # Right wall - counter-clockwise winding for outward normal
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[2])  # front-right-bottom
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1])  # back-right-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[5])  # back-right-top

    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[2])  # front-right-bottom
    st.set_uv(Vector2(1, 1))
    st.add_vertex(corners[5])  # back-right-top
    st.set_uv(Vector2(0, 1))
    st.add_vertex(corners[6])  # front-right-top

# Helper function to create fallback roof
func _create_fallback_roof(st: SurfaceTool, corners: PackedVector3Array, roof_peak_y: float) -> void:
    # Define ridge points - ridge runs from front center to back center of the building
    var ridge_center_front: Vector3 = Vector3(0, roof_peak_y, corners[7].z)  # Ridge at front center (same Z as front-left-top)
    var ridge_center_back: Vector3 = Vector3(0, roof_peak_y, corners[4].z)   # Ridge at back center (same Z as back-left-top)

    # Front gable (triangular end) - counter-clockwise winding for outward normal
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[3])  # front-left-top
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[2])  # front-right-top
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_front)  # ridge center front

    # Back gable (triangular end) - counter-clockwise winding for outward normal
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[0])  # back-left-top
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1])  # back-right-top
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_back)  # ridge center back

    # Left roof slope - two triangles forming the roof from left eave to ridge
    # Triangle 1: front-left-top -> back-left-top -> ridge_center_back
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[3])  # front-left-top
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[0])  # back-left-top
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_back)  # ridge center back

    # Triangle 2: front-left-top -> ridge_center_back -> ridge_center_front
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[3])  # front-left-top
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_back)  # ridge center back
    st.set_uv(Vector2(0.5, 0))
    st.add_vertex(ridge_center_front)  # ridge center front

    # Right roof slope - two triangles forming the roof from right eave to ridge
    # Triangle 1: front-right-top -> ridge_center_front -> ridge_center_back
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[2])  # front-right-top
    st.set_uv(Vector2(0.5, 0))
    st.add_vertex(ridge_center_front)  # ridge center front
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_back)  # ridge center back

    # Triangle 2: front-right-top -> ridge_center_back -> back-right-top
    st.set_uv(Vector2(0, 0))
    st.add_vertex(corners[2])  # front-right-top
    st.set_uv(Vector2(0.5, 1))
    st.add_vertex(ridge_center_back)  # ridge center back
    st.set_uv(Vector2(1, 0))
    st.add_vertex(corners[1])  # back-right-top


func _mark_building_in_grid(pos: Vector3, grid: Dictionary, cell_size: float, building_width: float) -> void:
    var radius := int(building_width / cell_size) + 1
    var center_cell := Vector2i(int(pos.x / cell_size), int(pos.z / cell_size))

    for dx in range(-radius, radius + 1):
        for dz in range(-radius, radius + 1):
            var cell := center_cell + Vector2i(dx, dz)
            grid[cell] = true

# Helper function to get preferred density class for building types
func _get_preferred_density_class(building_type: String) -> String:
    # Rural buildings
    if building_type in ["stone_cottage", "stone_cottage_new", "thatched_cottage", "timber_cabin", "log_chalet",
                          "rustic_cabin", "barn", "stable", "farmhouse", "outbuilding", "granary", "windmill",
                          "blacksmith", "mill", "gristmill", "sawmill"]:
        return "rural"
    
    # Suburban buildings
    if building_type in ["white_stucco_house", "stone_farmhouse", "cottage_small", "cottage_medium",
                          "cottage_large", "house_victorian", "house_colonial", "house_tudor"]:
        return "suburban"
    
    # Urban buildings
    if building_type in ["factory", "industrial", "factory_building", "warehouse", "workshop", "foundry",
                          "mill_factory", "power_station", "shop", "bakery", "inn", "tavern", "pub"]:
        return "urban"
    
    # Urban core buildings
    if building_type in ["victorian_mansion", "manor", "mansion", "villa", "chateau", "villa_italian",
                          "train_station", "market_stall", "church", "temple", "cathedral"]:
        return "urban_core"
    
    # Special cases
    if building_type in ["lighthouse", "castle_keep", "fortress", "tower"]:
        return "rural"  # These are typically in rural/coastal areas
    
    # Default fallback
    return ""
