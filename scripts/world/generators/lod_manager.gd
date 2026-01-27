class_name LODManager
extends RefCounted

## Manages Level of Detail updates for terrain and props based on camera distance
## Extracted from main.gd for modularity

var _terrain_generator: TerrainGenerator = null
var _prop_generator: PropGenerator = null

func set_terrain_generator(gen: TerrainGenerator) -> void:
    _terrain_generator = gen

func set_prop_generator(gen: PropGenerator) -> void:
    _prop_generator = gen

## Update all LOD systems based on camera position
func update(world_root: Node3D, camera_pos: Vector3, params: Dictionary) -> void:
    var lod_enabled: bool = params.get("lod_enabled", true)
    var lod0_radius: float = params.get("lod0_radius", 800.0)
    var lod1_radius: float = params.get("lod1_radius", 1600.0)

    # Update terrain LOD
    if _terrain_generator:
        _terrain_generator.apply_terrain_lod(camera_pos, lod_enabled, lod0_radius, lod1_radius)

    # Update prop LOD
    if _prop_generator:
        _apply_prop_lod(camera_pos, lod_enabled, lod0_radius, lod1_radius)

func _apply_prop_lod(cam_pos: Vector3, lod_enabled: bool, lod0_r: float, lod1_r: float) -> void:
    if not _prop_generator:
        return

    var lod_roots = _prop_generator.get_lod_roots()
    for root in lod_roots:
        if not is_instance_valid(root):
            continue

        var lod0 = root.get_node_or_null("LOD0")
        var lod1 = root.get_node_or_null("LOD1")
        var lod2 = root.get_node_or_null("LOD2")

        if not lod0:
            continue

        var root_pos: Vector3 = root.global_position
        var dist: float = cam_pos.distance_to(root_pos)

        var new_lod: int = 0
        if lod_enabled:
            if dist < lod0_r:
                new_lod = 0
            elif dist < lod1_r:
                new_lod = 1
            else:
                new_lod = 2

        var old_lod: int = root.get_meta("lod", -1)
        if old_lod == new_lod:
            continue

        root.set_meta("lod", new_lod)

        if lod0:
            lod0.visible = (new_lod == 0)
        if lod1:
            lod1.visible = (new_lod == 1)
        if lod2:
            lod2.visible = (new_lod == 2)
