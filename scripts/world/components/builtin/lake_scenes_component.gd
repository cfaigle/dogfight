extends WorldComponentBase
class_name LakeScenesComponent

## Handles LOD optimization for lake scenes
## Creates distance-based detail levels for performance

func get_priority() -> int:
    return 35  # After terrain mesh, but before detailed props

func get_optional_params() -> Dictionary:
    return {
        "lake_scene_lod_distance": 500.0,
        "lake_scene_max_detail_distance": 200.0,
        "enable_lake_scene_occlusion": true,
    }

func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if ctx.lakes.is_empty():
        return
    
    var lake_scenes_layer = ctx.get_layer("LakeScenes")
    var lod_root = Node3D.new()
    lod_root.name = "LakeScenes_LOD"
    lake_scenes_layer.add_child(lod_root)
    
    # Create LOD system for each lake scene
    for lake_data in ctx.lakes:
        if not lake_data.has("scene_root"):
            continue
            
        var lake_scene = lake_data.scene_root as Node3D
        if lake_scene == null:
            continue
            
        var lod_system = _create_optimized_lod_system(lod_root, lake_scene, lake_data, params)
        if lod_system != null:
            ctx.prop_lod_groups.append(lod_system)

func _create_optimized_lod_system(parent: Node3D, scene_root: Node3D, lake_data: Dictionary, params: Dictionary) -> Node3D:
    var lake_center = lake_data.get("center", Vector3.ZERO)
    var lod_distance = params.get("lake_scene_lod_distance", 500.0)
    
    # Create LOD controller
    var lod_controller = preload("res://scripts/world/lod/lake_scene_lod.gd").new()
    
    # Create LOD levels optimized for static scenes
    var high_detail = _create_high_detail_static(scene_root, lake_data)
    var medium_detail = _create_medium_detail_static(scene_root, lake_data)
    var low_detail = _create_low_detail_static(scene_root, lake_data)
    
    lod_controller.setup_static_lod(
        high_detail, medium_detail, low_detail,
        lake_center, lod_distance
    )
    
    parent.add_child(lod_controller)
    return lod_controller

func _create_high_detail_static(original_scene: Node3D, lake_data: Dictionary) -> Node3D:
    # High detail: use original scene with all objects
    var high_detail = original_scene.duplicate()
    high_detail.name = original_scene.name + "_High"
    
    # Ensure all objects are visible
    _set_descendants_visible(high_detail, true)
    
    return high_detail

func _create_medium_detail_static(original_scene: Node3D, lake_data: Dictionary) -> Node3D:
    # Medium detail: remove small props, simplify boats
    var medium_detail = original_scene.duplicate()
    medium_detail.name = original_scene.name + "_Medium"
    
    # Remove small accessories (towels, small items)
    _remove_small_accessories(medium_detail)
    
    # Simplify boats (remove detailed features)
    _simplify_boat_details(medium_detail)
    
    return medium_detail

func _create_low_detail_static(original_scene: Node3D, lake_data: Dictionary) -> Node3D:
    # Low detail: just water surface and major structures
    var low_detail = Node3D.new()
    low_detail.name = original_scene.name + "_Low"
    
    # Keep only major structures
    _keep_major_structures_only(low_detail, original_scene, lake_data)
    
    return low_detail

# --- LOD optimization helpers ---

func _remove_small_accessories(scene: Node3D) -> void:
    # Remove small decorative items to improve performance
    var to_remove = []
    
    # Find all small accessory nodes
    for child in _get_all_descendants(scene):
        var child_name = child.name.to_lower()
        if "towel" in child_name or "umbrella" in child_name or "bag" in child_name:
            if child is MeshInstance3D:
                to_remove.append(child)
    
    # Remove identified accessories
    for node in to_remove:
        node.get_parent().remove_child(node)
        node.queue_free()

func _simplify_boat_details(scene: Node3D) -> void:
    # Remove detailed boat features for medium LOD
    for child in _get_all_descendants(scene):
        if "boat" in child.name.to_lower():
            # Remove fishing gear, sail details, etc.
            _remove_boat_accessories(child)

func _remove_boat_accessories(boat_node: Node3D) -> void:
    var to_remove = []
    
    for child in _get_all_descendants(boat_node):
        var child_name = child.name.to_lower()
        if ("gear" in child_name or "sail" in child_name or 
            "windshield" in child_name or "engine" in child_name):
            to_remove.append(child)
    
    for node in to_remove:
        node.get_parent().remove_child(node)
        node.queue_free()

func _keep_major_structures_only(low_detail: Node3D, original_scene: Node3D, lake_data: Dictionary) -> void:
    # Low detail: only major docks, harbor buildings, and basic boats
    for child in original_scene.get_children():
        var child_name = child.name.to_lower()
        
        # Keep major structures
        if ("dock" in child_name or "pier" in child_name or 
            "harbor" in child_name or "breakwater" in child_name):
            var simplified = _simplify_structure(child)
            if simplified != null:
                low_detail.add_child(simplified)
        
        # Keep simplified boats
        elif "boat" in child_name:
            var simple_boat = _create_simple_boat(child, lake_data)
            if simple_boat != null:
                low_detail.add_child(simple_boat)
        
        # Keep major buoys
        elif "buoy" in child_name and "navigation" in child_name:
            var simple_buoy = _create_simple_buoy(child)
            if simple_buoy != null:
                low_detail.add_child(simple_buoy)

func _simplify_structure(structure_node: Node3D) -> Node3D:
    # Create simplified version of docks/harbor structures
    var structure_name = structure_node.name.to_lower()
    var simplified = Node3D.new()
    simplified.name = structure_node.name + "_Simple"
    simplified.transform = structure_node.transform
    
    # For docks, just create a simple platform
    if "dock" in structure_name or "pier" in structure_name:
        var platform = MeshInstance3D.new()
        platform.mesh = BoxMesh.new()
        platform.mesh.size = Vector3(20.0, 0.2, 4.0)  # Generic size
        platform.material_override = _create_simple_dock_material()
        simplified.add_child(platform)
    
    # For harbor buildings, create simple boxes
    elif ("office" in structure_name or "warehouse" in structure_name or 
        "building" in structure_name):
        var building = MeshInstance3D.new()
        building.mesh = BoxMesh.new()
        building.mesh.size = Vector3(10.0, 5.0, 8.0)  # Generic size
        building.material_override = _create_simple_building_material()
        simplified.add_child(building)
    
    return simplified

func _create_simple_boat(original_boat: Node3D, lake_data: Dictionary) -> Node3D:
    # Create very simple boat representation
    var simple_boat = Node3D.new()
    simple_boat.name = original_boat.name + "_Simple"
    simple_boat.transform = original_boat.transform
    
    # Simple hull
    var hull = MeshInstance3D.new()
    hull.mesh = BoxMesh.new()
    hull.mesh.size = Vector3(8.0, 1.5, 12.0)  # Generic boat size

    # Preserve the original boat's color scheme if available.
    var boat_type = ""
    if original_boat != null and original_boat.has_meta("boat_type"):
        boat_type = String(original_boat.get_meta("boat_type"))

    var color := Color(0.5, 0.5, 0.5)
    if original_boat != null and original_boat.has_meta("color_scheme"):
        var scheme = original_boat.get_meta("color_scheme")
        if typeof(scheme) == TYPE_DICTIONARY:
            # For sailboats the bright sail reads best at distance.
            if boat_type == "sailboat":
                color = scheme.get("sail", scheme.get("accent", scheme.get("hull", color)))
            else:
                color = scheme.get("hull", color)

    hull.material_override = _create_simple_boat_material(color)
    simple_boat.add_child(hull)
    
    return simple_boat

func _create_simple_buoy(original_buoy: Node3D) -> Node3D:
    # Create simple navigation buoy
    var simple_buoy = Node3D.new()
    simple_buoy.name = original_buoy.name + "_Simple"
    simple_buoy.transform = original_buoy.transform
    
    # Simple cylinder buoy
    var buoy = MeshInstance3D.new()
    buoy.mesh = CylinderMesh.new()
    buoy.mesh.height = 2.0
    buoy.mesh.top_radius = 0.6
    buoy.mesh.bottom_radius = 0.6
    buoy.material_override = _create_simple_buoy_material()
    simple_buoy.add_child(buoy)
    
    return simple_buoy

# --- Simple LOD materials ---

func _create_simple_dock_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 0.3, 0.2)
    mat.roughness = 0.7
    return mat

func _create_simple_building_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.6, 0.6, 0.65)
    mat.roughness = 0.6
    return mat

func _create_simple_boat_material(color: Color = Color(0.5, 0.5, 0.5)) -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.5
    return mat

func _create_simple_buoy_material() -> StandardMaterial3D:
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.8, 0.0)
    mat.roughness = 0.5
    return mat

# --- Utility helpers ---

func _set_descendants_visible(node: Node3D, visible: bool) -> void:
    for child in _get_all_descendants(node):
        if child is VisualInstance3D:
            child.visible = visible

func _get_all_descendants(node: Node) -> Array:
    var descendants = []
    _collect_descendants(node, descendants)
    return descendants

func _collect_descendants(node: Node, result: Array) -> void:
    result.append(node)
    for child in node.get_children():
        _collect_descendants(child, result)