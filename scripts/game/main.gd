extends Node3D

# Main scene driver. World + props are spawned procedurally so the project is self-contained.

const PlayerPlaneScript = preload("res://scripts/actors/plane/player_plane.gd")
const EnemyPlaneScript  = preload("res://scripts/actors/plane/enemy_plane.gd")
const HUDScript         = preload("res://scripts/ui/hud.gd")
const CameraRigScript   = preload("res://scripts/game/camera_rig.gd")
const TerrainShader     = preload("res://resources/shaders/terrain_ww2.gdshader")
const WorldGen          = preload("res://scripts/game/world_gen.gd")
const AssetLibraryScript = preload("res://scripts/util/asset_library.gd")
const ParametricBuildingSystem = preload("res://scripts/building_systems/parametric_buildings.gd")
const FontManagerScript = preload("res://scripts/util/font_manager.gd")

@export var plane_defs: Resource = preload("res://resources/defs/plane_defs.tres")
@export var weapon_defs: Resource = preload("res://resources/defs/weapon_defs.tres")

var _hud: CanvasLayer
var _player: Node3D
var _camrig: Node3D
var _cam: Camera3D

var _spawn_timer: float = 0.0
var _wave_size: int = 2

# World cache
var _world_root: Node3D
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _hmap: PackedFloat32Array = PackedFloat32Array()
var _hmap_res: int = 0
var _hmap_step: float = 0.0
var _hmap_half: float = 0.0
var _terrain_size: float = 4000.0  # Default terrain size matching Game.gd
var _terrain_amp: float = 220.0
var _terrain_res: int = 128

# Terrain render LOD (adjusted for smaller world)
var _terrain_render_root: Node3D
var _terrain_lod_enabled: bool = true
var _terrain_lod0_r: float = 3250.0  # Half of original (was 6500)
var _terrain_lod1_r: float = 8000.0  # Half of original (was 16000)
var _terrain_lod_update: float = 0.25
var _terrain_lod_timer: float = 0.0

# Prop LOD (settlements, shacks, forests, etc.)
var _prop_lod_enabled: bool = true
var _prop_lod0_r: float = 5500.0
var _prop_lod1_r: float = 14000.0
var _prop_lod_update: float = 0.35
var _prop_lod_timer: float = 0.0

var _assets

var _runway_len: float = 900.0
var _runway_w: float = 80.0
var _runway_spawn: Vector3 = Vector3(0.0, 200.0, -320.0)

var _rivers: Array = []
var _settlements: Array = [] # Array[Dictionary]
var _prop_lod_groups: Array = [] # Array[Dictionary] - generic LOD groups for props

var _peaceful_mode: bool = false

var _hide_xform: Transform3D = Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), Vector3(0.0, -10000.0, 0.0))

var scenery_visible: bool = true
var original_mesh_visibility: Dictionary = {}

# NEW: Parametric building system variables
var _enable_parametric_buildings: bool = true
var _parametric_system: RefCounted = null  # BuildingParametricSystem (untyped to avoid load-order issues)
var _parametric_materials: Dictionary = {}
var _current_building_styles: Dictionary = {}
var _parametric_building_variants: Dictionary = {}

var _roof_mesh_gable: ArrayMesh
var _roof_mesh_hip: ArrayMesh
var _roof_mesh_mansard: ArrayMesh
var _roof_mesh_gambrel: ArrayMesh
var _roof_mesh_flat: ArrayMesh
var _window_mesh: ArrayMesh
var _door_mesh: ArrayMesh
var _trim_mesh: ArrayMesh
var _damage_mesh: ArrayMesh

var _mesh_unit_box: BoxMesh
var _mesh_unit_flat: BoxMesh
var _mesh_unit_cyl: CylinderMesh
var _mesh_unit_cone: CylinderMesh
var _mesh_chimney: CylinderMesh

# Building kits organized by settlement style
var _building_kits: Dictionary = {} # style -> BuildingKit

# NEW: Modular world generation system
var _world_builder: WorldBuilder = null


func _ready() -> void:
    # Initialize font manager first
    FontManagerScript.initialize_fonts()
    print("🔤 Main: Initialized font manager")

    GameEvents.reset()
    _setup_camera()
    _setup_world()
    _setup_player()
    _setup_hud()
    _peaceful_mode = bool(Game.settings.get("peaceful_mode", false))

    if not _peaceful_mode:
        _spawn_wave(1)

    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if bool(Game.settings.get("mouse_flight", true)) else Input.MOUSE_MODE_VISIBLE

    GameEvents.player_destroyed.connect(_on_player_destroyed)
    GameEvents.enemy_destroyed.connect(_on_enemy_destroyed)
    GameEvents.red_square_destroyed.connect(_spawn_rising_ukrainian_flag)


func _process(dt: float) -> void:
    # Keep terrain LOD responsive even in peaceful mode.
    if not Game.is_paused and _terrain_render_root != null and is_instance_valid(_terrain_render_root):
        _terrain_lod_timer += dt
        if _terrain_lod_timer >= _terrain_lod_update:
            _terrain_lod_timer = 0.0
            var cam_pos: Vector3 = _runway_spawn
            if _cam != null and is_instance_valid(_cam):
                cam_pos = _cam.global_position
            _apply_terrain_lod(_terrain_render_root, cam_pos, _terrain_lod_enabled, _terrain_lod0_r, _terrain_lod1_r)

    # Props LOD (settlements, shacks, etc.)
    if not Game.is_paused:
        _prop_lod_timer += dt
        if _prop_lod_timer >= _prop_lod_update:
            _prop_lod_timer = 0.0
            var cam_pos2: Vector3 = _runway_spawn
            if _cam != null and is_instance_valid(_cam):
                cam_pos2 = _cam.global_position
            _apply_prop_lod(cam_pos2, _prop_lod_enabled, _prop_lod0_r, _prop_lod1_r)

    if Game.is_paused or _peaceful_mode:
        return

    # Spawn a new wave when the skies are clear.
    if get_tree().get_nodes_in_group("enemies").is_empty():
        _spawn_timer += dt
        if _spawn_timer > 1.25:
            _spawn_timer = 0.0
            GameEvents.set_wave(GameEvents.wave + 1)
            _spawn_wave(GameEvents.wave)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_ESCAPE:
                Game.toggle_pause()
            KEY_F2:
                _rebuild_world(true)
            KEY_F3:
                _rebuild_world(false)
            KEY_F4:
                _toggle_peaceful_mode()
            KEY_F5:
                _toggle_collision_visualization()
            KEY_F6:
                _toggle_scenery_visibility()
            KEY_F7:
                _toggle_external_assets()
            KEY_F8:
                _toggle_building_labels()
            KEY_F9:
                _toggle_target_lock()


func _setup_camera() -> void:
    # Chase camera rig so 3D world is visible even with a fully-procedural scene.
    _camrig = Node3D.new()
    _camrig.name = "CameraRig"
    _camrig.set_script(CameraRigScript)

    _cam = Camera3D.new()
    _cam.name = "MainCamera"
    _cam.current = true
    _cam.near = 0.1
    _cam.far = 45000.0
    _cam.fov = float(Game.settings.get("fov_base", 72.0))
    _camrig.add_child(_cam)
    add_child(_camrig)

    Game.main_camera = _cam
    Game.camera_rig = _camrig


func _setup_world() -> void:
    _ensure_environment()

    if _assets == null:
        _assets = AssetLibraryScript.new()

    if _world_root == null:
        _world_root = Node3D.new()
        _world_root.name = "World"
        add_child(_world_root)


    # Initialize modular world builder
    if _world_builder == null:
        _world_builder = WorldBuilder.new()
        print("✨ Initialized modular WorldBuilder")

    # Initialize modular world builder
    if _world_builder == null:
        _world_builder = WorldBuilder.new()
        print("✨ Initialized modular WorldBuilder")

    var seed: int = int(Game.settings.get("world_seed", -1))
    var new_seed: bool = seed == -1
    _rebuild_world(new_seed)


func _ensure_environment() -> void:
    # Environment + sun are created once.
    if get_node_or_null("WorldEnvironment") == null:
        var we := WorldEnvironment.new()
        we.name = "WorldEnvironment"
        var env := Environment.new()
        env.background_mode = Environment.BG_SKY

        var sky := Sky.new()
        var sm := ProceduralSkyMaterial.new()
        sm.sky_top_color = Color(0.16, 0.32, 0.60, 1.0)
        sm.sky_horizon_color = Color(0.72, 0.80, 0.88, 1.0)
        sm.ground_horizon_color = Color(0.45, 0.45, 0.46, 1.0)
        sm.sun_angle_max = 0.75
        sm.sun_curve = 0.12
        sky.sky_material = sm
        env.sky = sky

        env.tonemap_mode = Environment.TONE_MAPPER_ACES
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 1.05
        env.glow_enabled = false

        env.fog_enabled = true
        env.fog_light_color = Color(0.78, 0.82, 0.88, 1.0)
        env.fog_density = float(Game.settings.get("fog_density", 0.00045))
        env.fog_sun_scatter = float(Game.settings.get("fog_sun_scatter", 0.28))

        we.environment = env
        add_child(we)

    if get_node_or_null("Sun") == null:
        var sun := DirectionalLight3D.new()
        sun.name = "Sun"
        sun.light_color = Color(1.0, 0.96, 0.90)
        sun.light_energy = 2.2
        sun.shadow_enabled = true
        sun.directional_shadow_max_distance = 8000.0
        sun.shadow_bias = 0.02
        sun.rotation_degrees = Vector3(-42.0, 25.0, 0.0)
        add_child(sun)


func _toggle_peaceful_mode() -> void:
    _peaceful_mode = not _peaceful_mode
    Game.settings["peaceful_mode"] = _peaceful_mode
    Game.save_settings()

    # Clean up enemies when going peaceful.
    if _peaceful_mode:
        for e in get_tree().get_nodes_in_group("enemies"):
            if e is Node:
                (e as Node).queue_free()
        _spawn_timer = 0.0


func _toggle_external_assets() -> void:
    # Toggle external mesh usage (res://assets/external/manifest.json) and rebuild.
    var cur: bool = bool(Game.settings.get("use_external_assets", false))
    Game.settings["use_external_assets"] = not cur
    Game.save_settings()
    _rebuild_world(false)


func _toggle_building_labels() -> void:
    # Toggle building labels visibility and rebuild world.
    var current_labels_setting: bool = bool(Game.settings.get("enable_building_labels", false))  # Default to false (hidden)
    Game.settings["enable_building_labels"] = not current_labels_setting
    Game.save_settings()
    _rebuild_world(false)


func _toggle_target_lock() -> void:
    # Toggle target-lock mode on/off
    var current_target_lock: bool = bool(Game.settings.get("enable_target_lock", true))  # Default to true (enabled)
    Game.settings["enable_target_lock"] = not current_target_lock
    Game.save_settings()

    # Update HUD to show current state
    print("Target Lock Mode: ", "ENABLED" if not current_target_lock else "DISABLED")


func _toggle_collision_visualization() -> void:
    if CollisionManager:
        var current = CollisionManager.debug_visualization_enabled
        CollisionManager.toggle_collision_visualization(not current)
        print("Collision visualization: %s" % ("ON" if not current else "OFF"))


func _toggle_scenery_visibility() -> void:
    toggle_world_scenery(not scenery_visible)
    print("World scenery: %s" % ("ON" if scenery_visible else "OFF"))


func toggle_world_scenery(enabled: bool) -> void:
    scenery_visible = enabled

    if not enabled:
        _set_scenery_visibility_recursive(self, false)
    else:
        _restore_scenery_visibility()


func _set_scenery_visibility_recursive(node: Node, visible: bool) -> void:
    if node is MeshInstance3D and not node.is_in_group("DebugVisualization"):
        var mesh_inst = node as MeshInstance3D
        var instance_id = mesh_inst.get_instance_id()

        if not original_mesh_visibility.has(instance_id):
            original_mesh_visibility[instance_id] = mesh_inst.visible

        mesh_inst.visible = visible

    for child in node.get_children():
        _set_scenery_visibility_recursive(child, visible)


func _restore_scenery_visibility() -> void:
    for instance_id in original_mesh_visibility:
        var original_visible = original_mesh_visibility[instance_id]
        var mesh_inst = instance_from_id(instance_id)
        if is_instance_valid(mesh_inst) and mesh_inst is MeshInstance3D:
            mesh_inst.visible = original_visible

    original_mesh_visibility.clear()


## Systematic parameter mapping: copy world-generation settings from Game.settings to world params
func _add_world_gen_params(params: Dictionary) -> void:
    # Core terrain and world settings
    params["terrain_size"] = Game.settings.get("terrain_size", 4000.0)
    params["terrain_res"] = Game.settings.get("terrain_res", 1024)
    params["terrain_amp"] = Game.settings.get("terrain_amp", 300.0)
    params["terrain_chunk_cells"] = Game.settings.get("terrain_chunk_cells", 8)
    params["terrain_lod_enabled"] = Game.settings.get("terrain_lod_enabled", true)
    params["terrain_lod0_radius"] = Game.settings.get("terrain_lod0_radius", 3250.0)
    params["terrain_lod1_radius"] = Game.settings.get("terrain_lod1_radius", 8000.0)
    params["terrain_lod_update"] = Game.settings.get("terrain_lod_update", 0.25)
    params["landmark_count"] = Game.settings.get("landmark_count", 0)
    params["sea_level"] = Game.settings.get("sea_level", 0.0)
    params["fog_density"] = Game.settings.get("fog_density", 0.00015)
    params["fog_sun_scatter"] = Game.settings.get("fog_sun_scatter", 0.08)
    params["random_terrain"] = Game.settings.get("random_terrain", true)
    
    # Asset and rendering settings
    params["use_external_assets"] = Game.settings.get("use_external_assets", false)
    params["prop_lod_enabled"] = Game.settings.get("prop_lod_enabled", true)
    params["prop_lod0_radius"] = Game.settings.get("prop_lod0_radius", 5500.0)
    params["prop_lod1_radius"] = Game.settings.get("prop_lod1_radius", 14000.0)
    params["prop_lod_update"] = Game.settings.get("prop_lod_update", 0.35)
    
    # Settlement and prop variety settings
    params["settlement_variants_near"] = Game.settings.get("settlement_variants_near", 12)
    params["settlement_variants_mid"] = Game.settings.get("settlement_variants_mid", 6)
    params["settlement_variants_far"] = Game.settings.get("settlement_variants_far", 2)
    params["beach_shack_variants_near"] = Game.settings.get("beach_shack_variants_near", 4)
    params["beach_shack_variants_mid"] = Game.settings.get("beach_shack_variants_mid", 2)
    
    # Forest control settings
    params["forest_patch_count"] = Game.settings.get("forest_patch_count", 30)
    params["forest_patch_trees_per_patch"] = Game.settings.get("forest_patch_trees_per_patch", 180)
    params["forest_patch_radius_min"] = Game.settings.get("forest_patch_radius_min", 180.0)
    params["forest_patch_radius_max"] = Game.settings.get("forest_patch_radius_max", 520.0)
    params["forest_patch_placement_attempts"] = Game.settings.get("forest_patch_placement_attempts", 50)
    params["forest_patch_placement_buffer"] = Game.settings.get("forest_patch_placement_buffer", 250.0)
    params["random_tree_count"] = Game.settings.get("random_tree_count", 1000)
    params["random_tree_clearance_buffer"] = Game.settings.get("random_tree_clearance_buffer", 50.0)
    params["random_tree_slope_limit"] = Game.settings.get("random_tree_slope_limit", 55.0)
    params["random_tree_placement_attempts"] = Game.settings.get("random_tree_placement_attempts", 10)
    params["settlement_tree_count_per_building"] = Game.settings.get("settlement_tree_count_per_building", 0.2)
    params["urban_tree_buffer_distance"] = Game.settings.get("urban_tree_buffer_distance", 80.0)
    params["park_tree_density"] = Game.settings.get("park_tree_density", 6)
    params["roadside_tree_spacing"] = Game.settings.get("roadside_tree_spacing", 70.0)
    params["forest_biome_tree_types"] = Game.settings.get("forest_biome_tree_types", {})
    params["use_external_tree_assets"] = Game.settings.get("use_external_tree_assets", true)
    params["tree_lod_distance"] = Game.settings.get("tree_lod_distance", 200.0)
    params["tree_max_instances_per_mesh"] = Game.settings.get("tree_max_instances_per_mesh", 8000)
    params["tree_debug_metrics"] = Game.settings.get("tree_debug_metrics", true)
    
    # Additional game settings that might be used by world gen
    params["world_seed"] = Game.settings.get("world_seed", -1)
    params["peaceful_mode"] = Game.settings.get("peaceful_mode", false)
    params["enable_target_lock"] = Game.settings.get("enable_target_lock", true)

func _rebuild_world(new_seed: bool) -> void:
    # Clear prior world content.
    if _world_root:
        for c in _world_root.get_children():
            (c as Node).queue_free()

    _terrain_render_root = null
    _prop_lod_groups = []

    # Also clear enemies (world regen shouldn't keep dogfights alive).
    for e in get_tree().get_nodes_in_group("enemies"):
        if e is Node:
            (e as Node).queue_free()

    var seed: int = int(Game.settings.get("world_seed", -1))
    if new_seed or seed == -1:
        seed = randi()
        Game.settings["world_seed"] = seed
        Game.save_settings()

    # Load knobs.
    _terrain_size = float(Game.settings.get("terrain_size", 4000.0))
    _terrain_res = int(Game.settings.get("terrain_res", 192))
    _terrain_amp = float(Game.settings.get("terrain_amp", 300.0))
    Game.sea_level = float(Game.settings.get("sea_level", 0.0))

    _terrain_lod_enabled = bool(Game.settings.get("terrain_lod_enabled", true))
    _terrain_lod0_r = float(Game.settings.get("terrain_lod0_radius", 6500.0))
    _terrain_lod1_r = float(Game.settings.get("terrain_lod1_radius", 16000.0))
    _terrain_lod_update = float(Game.settings.get("terrain_lod_update", 0.25))

    # External assets (optional)
    if _assets != null:
        _assets.reload(bool(Game.settings.get("use_external_assets", false)))

    # Build building kits after assets are loaded
    _ensure_building_kits()

    _prop_lod_enabled = bool(Game.settings.get("prop_lod_enabled", true))
    _prop_lod0_r = float(Game.settings.get("prop_lod0_radius", 5500.0))
    _prop_lod1_r = float(Game.settings.get("prop_lod1_radius", 14000.0))
    _prop_lod_update = float(Game.settings.get("prop_lod_update", 0.35))
    _prop_lod_timer = 0.0

    if _assets != null:
        (_assets as RefCounted).call("reload", bool(Game.settings.get("use_external_assets", false)))
    _terrain_lod_timer = 0.0

    _runway_len = 900.0
    _runway_w = 80.0

    Game.ground_height_callable = Callable(self, "_ground_height")

    # Initialize parametric system BEFORE building world
    _init_parametric_system()

    # --- Modular world builder (HARD SWITCH) ---
    # The legacy monolithic world build path has been removed from the runtime.
    # If something breaks, fix the component pipeline; don't revive the old code.
    if _world_builder == null:
        push_error("WorldBuilder missing - cannot build world")
        return

    # Pass shared refs
    _world_builder.set_assets(_assets)
    _world_builder.set_mesh_cache(_mesh_cache)
    _world_builder.set_material_cache(_material_cache)
    _world_builder.set_building_kits(_building_kits)
    _world_builder.set_parametric_system(_parametric_system)

    # Create params dictionary with systematic world-gen parameter mapping
    var params: Dictionary = {
        "seed": seed,
    }
    
    # Add all world-generation parameters from Game.settings systematically
    _add_world_gen_params(params)
    

    
    # Override some params with local variables (to maintain existing behavior)
    params["terrain_size"] = _terrain_size
    params["terrain_res"] = _terrain_res
    params["terrain_amp"] = _terrain_amp
    params["sea_level"] = Game.sea_level
    params["runway_len"] = _runway_len
    params["runway_w"] = _runway_w
    
    # Override LOD parameters with local variables
    params["terrain_lod_enabled"] = _terrain_lod_enabled
    params["terrain_lod0_r"] = _terrain_lod0_r
    params["terrain_lod1_r"] = _terrain_lod1_r
    
    # Legacy parameters and overrides (maintain existing behavior)
    params["river_count"] = int(Game.settings.get("river_count", 7))
    params["river_source_min"] = float(Game.settings.get("river_source_min", Game.sea_level + 35.0))
    params["world_components"] = Game.settings.get("world_components", null)
    params["city_buildings"] = int(Game.settings.get("city_buildings", 600))
    params["town_count"] = int(Game.settings.get("town_count", 5))
    params["hamlet_count"] = int(Game.settings.get("hamlet_count", 12))
    params["enable_building_labels"] = bool(Game.settings.get("enable_building_labels", false))
    params["enable_roads"] = true
    params["enable_regional_roads"] = bool(Game.settings.get("enable_regional_roads", true))
    params["regional_road_spacing"] = float(Game.settings.get("regional_road_spacing", 1500.0))
    params["regional_highway_spacing"] = float(Game.settings.get("regional_highway_spacing", 4000.0))
    params["road_width"] = float(Game.settings.get("road_width", 16.0))
    params["road_k_neighbors"] = int(Game.settings.get("road_k_neighbors", 6))
    params["road_density_target"] = float(Game.settings.get("road_density_target", 3.5))
    params["road_smooth"] = bool(Game.settings.get("road_smooth", true))
    params["allow_bridges"] = bool(Game.settings.get("allow_bridges", true))
    
    # Legacy tree parameters (different from new forest control parameters)
    params["tree_count"] = int(Game.settings.get("tree_count", 8000))
    params["forest_patches"] = int(Game.settings.get("forest_patches", 26))
    params["pond_count"] = 0  # DISABLED: Ponds disabled - appear as giant blue circles
    params["lake_count"] = 0  # DISABLED: Lakes disabled due to circular appearance
    params["biome_map_res"] = int(Game.settings.get("biome_map_res", 256))
    params["farm_patch_count"] = int(Game.settings.get("farm_patch_count", 14))
    
    # Lake scene parameters
    params["lake_scene_percentage"] = float(Game.settings.get("lake_scene_percentage", 1.0))
    params["lake_type_weights"] = Game.settings.get("lake_type_weights", {"basic": 0.3, "recreational": 0.3, "fishing": 0.25, "harbor": 0.15})
    params["boat_density_per_lake"] = float(Game.settings.get("boat_density_per_lake", 0.4))
    params["buoy_density_per_radius"] = float(Game.settings.get("buoy_density_per_radius", 2.0))
    params["dock_probability"] = float(Game.settings.get("dock_probability", 0.5))
    params["shore_feature_probability"] = float(Game.settings.get("shore_feature_probability", 0.7))
    params["max_boats_per_lake"] = int(Game.settings.get("max_boats_per_lake", 8))
    params["max_buoys_per_lake"] = int(Game.settings.get("max_buoys_per_lake", 20))
    params["max_docks_per_lake"] = int(Game.settings.get("max_docks_per_lake", 3))
    params["lake_scene_lod_distance"] = float(Game.settings.get("lake_scene_lod_distance", 500.0))
    params["lake_scene_max_detail_distance"] = float(Game.settings.get("lake_scene_max_detail_distance", 200.0))

    # If world_components was left null, drop it so builder uses defaults.
    if params["world_components"] == null:
        params.erase("world_components")

    var out: Dictionary = _world_builder.build_world(_world_root, seed, params)

    # Hook outputs into existing systems (ground query, LOD, spawn, etc.)
    _hmap = out.get("hmap", PackedFloat32Array()) as PackedFloat32Array
    _hmap_res = int(out.get("hmap_res", 0))
    _hmap_step = float(out.get("hmap_step", 0.0))
    _hmap_half = float(out.get("hmap_half", 0.0))
    _rivers = out.get("rivers", []) as Array

    _terrain_render_root = out.get("terrain_root", null) as Node3D
    _prop_lod_groups = out.get("prop_lod_groups", []) as Array
    _settlements = out.get("settlements", []) as Array

    _runway_spawn = out.get("runway_spawn", Vector3(0.0, Game.sea_level + 40.0, 0.0)) as Vector3

    # Reposition player to the runway spawn if we already exist.
    if _player != null and is_instance_valid(_player):
        _player.global_position = _runway_spawn
        if _player is RigidBody3D:
            var rb := _player as RigidBody3D
            rb.linear_velocity = Vector3.ZERO
            rb.angular_velocity = Vector3.ZERO

    # Print building statistics after world generation
    if _world_builder and _world_builder.get_unified_building_system():
        _world_builder.get_unified_building_system().print_building_statistics()

    # Add Moskva cruiser after world generation
    _build_moskva_cruiser(_world_root)

    # Add Red Square building
    _build_red_square(_world_root)

    _spawn_timer = 0.0
    return


func _build_ocean() -> void:
    var ocean := MeshInstance3D.new()
    ocean.name = "Ocean"
    var pm := PlaneMesh.new()
    pm.size = Vector2(82000.0, 82000.0)
    pm.subdivide_width = 24
    pm.subdivide_depth = 24
    ocean.mesh = pm
    ocean.position = Vector3(0.0, Game.sea_level - 0.35, 0.0)

    var mat := ShaderMaterial.new()
    mat.shader = preload("res://resources/shaders/ocean.gdshader")
    ocean.material_override = mat
    ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _world_root.add_child(ocean)


func _ground_height(x: float, z: float) -> float:
    if _hmap_res <= 0 or _hmap.is_empty():
        return float(Game.sea_level)

    var u: float = (x + _hmap_half) / _hmap_step
    var v: float = (z + _hmap_half) / _hmap_step

    u = clamp(u, 0.0, float(_hmap_res))
    v = clamp(v, 0.0, float(_hmap_res))

    var x0: int = int(floor(u))
    var z0: int = int(floor(v))
    var x1: int = min(x0 + 1, _hmap_res)
    var z1: int = min(z0 + 1, _hmap_res)

    var fu: float = u - float(x0)
    var fv: float = v - float(z0)

    var w: int = _hmap_res + 1
    var h00: float = float(_hmap[z0 * w + x0])
    var h10: float = float(_hmap[z0 * w + x1])
    var h01: float = float(_hmap[z1 * w + x0])
    var h11: float = float(_hmap[z1 * w + x1])

    var a: float = lerp(h00, h10, fu)
    var b: float = lerp(h01, h11, fu)
    return lerp(a, b, fv)


func _slope_at(x: float, z: float) -> float:
    var h: float = _ground_height(x, z)
    var hx: float = _ground_height(x + _hmap_step, z)
    var hz: float = _ground_height(x, z + _hmap_step)
    var sx: float = absf(hx - h) / maxf(0.001, _hmap_step)
    var sz: float = absf(hz - h) / maxf(0.001, _hmap_step)
    return maxf(sx, sz)


func _h_at_idx(ix: int, iz: int) -> float:
    var res: int = _terrain_res
    var w: int = res + 1
    ix = clampi(ix, 0, res)
    iz = clampi(iz, 0, res)
    return float(_hmap[iz * w + ix])


func _n_at_idx(ix: int, iz: int, step: float) -> Vector3:
    # Normal from full-res heightmap gradients for seam-free lighting across chunks/LODs.
    var hL: float = _h_at_idx(ix - 1, iz)
    var hR: float = _h_at_idx(ix + 1, iz)
    var hD: float = _h_at_idx(ix, iz - 1)
    var hU: float = _h_at_idx(ix, iz + 1)
    var nx: float = hL - hR
    var nz: float = hD - hU
    var n := Vector3(nx, 2.0 * step, nz)
    if n.length() < 0.0001:
        return Vector3.UP
    return n.normalized()


func _pick_chunk_cells(res: int, requested: int) -> int:
    # Pick a chunk cell size that divides `res` cleanly.
    # Also try to be divisible by 4 so LOD2 (stride=4) aligns well.
    requested = clampi(requested, 8, max(8, res))
    var best: int = 0
    var best_score: float = 1e18

    for d in range(4, res + 1):
        if res % d != 0:
            continue
        var score: float = absf(float(d - requested))
        # Prefer multiples of 4.
        if d % 4 != 0:
            score += 50.0
        # Slight preference for chunk sizes in a sane range.
        if d < 16:
            score += 25.0
        if d > 96:
            score += 20.0
        if score < best_score:
            best_score = score
            best = d

    if best == 0:
        best = res
    return best


func _make_terrain_chunk_mesh(ix0: int, iz0: int, cells: int, stride: int, half: float, step: float) -> ArrayMesh:
    var res: int = _terrain_res
    var nx: int = int(cells / stride) + 1
    var nz: int = int(cells / stride) + 1

    var verts := PackedVector3Array()
    var norms := PackedVector3Array()
    var uvs := PackedVector2Array()
    verts.resize(nx * nz)
    norms.resize(nx * nz)
    uvs.resize(nx * nz)

    for j in range(nz):
        var gz: int = iz0 + j * stride
        var z: float = -half + float(gz) * step
        var v: float = float(gz) / float(res)
        for i in range(nx):
            var gx: int = ix0 + i * stride
            var x: float = -half + float(gx) * step
            var u: float = float(gx) / float(res)
            var y: float = _h_at_idx(gx, gz)

            var idx: int = j * nx + i
            verts[idx] = Vector3(x, y, z)
            norms[idx] = _n_at_idx(gx, gz, step)
            uvs[idx] = Vector2(u, v)

    var indices := PackedInt32Array()
    indices.resize((nx - 1) * (nz - 1) * 6)
    var k: int = 0
    for j in range(nz - 1):
        for i in range(nx - 1):
            var a: int = j * nx + i
            var b: int = a + 1
            var c: int = a + nx
            var d: int = c + 1
            indices[k + 0] = a
            indices[k + 1] = b
            indices[k + 2] = c
            indices[k + 3] = b
            indices[k + 4] = d
            indices[k + 5] = c
            k += 6

    var arr := []
    arr.resize(Mesh.ARRAY_MAX)
    arr[Mesh.ARRAY_VERTEX] = verts
    arr[Mesh.ARRAY_NORMAL] = norms
    arr[Mesh.ARRAY_TEX_UV] = uvs
    arr[Mesh.ARRAY_INDEX] = indices

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
    return mesh


func _build_terrain() -> void:
    # Chunked terrain rendering + optional LOD rings.
    # Collision stays as a single HeightMapShape3D (fast + accurate).

    var terrain_root := Node3D.new()
    terrain_root.name = "Terrain"
    _world_root.add_child(terrain_root)

    var half: float = _terrain_size * 0.5
    var res: int = _terrain_res
    var step: float = _terrain_size / float(res)

    var tmat := ShaderMaterial.new()
    tmat.shader = TerrainShader
    tmat.set_shader_parameter("sea_level", Game.sea_level)

    # Load and apply terrain textures if available
    if _assets != null and _assets.enabled():
        var grass_textures: Dictionary = _assets.get_texture_set("terrain_grass")
        var pavement_textures: Dictionary = _assets.get_texture_set("terrain_pavement")

        if grass_textures.has("albedo") and pavement_textures.has("albedo"):
            tmat.set_shader_parameter("use_textures", true)
            tmat.set_shader_parameter("grass_texture", grass_textures["albedo"])
            tmat.set_shader_parameter("pavement_texture", pavement_textures["albedo"])
            tmat.set_shader_parameter("texture_scale", 32.0)

    var want_cells: int = int(Game.settings.get("terrain_chunk_cells", 32))
    var cells: int = _pick_chunk_cells(res, want_cells)

    _terrain_render_root = terrain_root

    var lod_enabled: bool = _terrain_lod_enabled
    var lod0_r: float = _terrain_lod0_r
    var lod1_r: float = _terrain_lod1_r

    var chunks_per_side: int = int(res / cells)

    # Build chunks.
    for cz in range(chunks_per_side):
        for cx in range(chunks_per_side):
            var ix0: int = cx * cells
            var iz0: int = cz * cells

            var chunk := Node3D.new()
            chunk.name = "Chunk_%d_%d" % [cx, cz]
            terrain_root.add_child(chunk)

            # Center point for LOD switching.
            var center_x: float = -half + (float(ix0) + float(cells) * 0.5) * step
            var center_z: float = -half + (float(iz0) + float(cells) * 0.5) * step
            chunk.set_meta("center", Vector2(center_x, center_z))
            chunk.set_meta("lod", -1)

            # LOD meshes (stride 1/2/4). Always create them; visibility is controlled.
            var mi0 := MeshInstance3D.new()
            mi0.name = "LOD0"
            mi0.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 1, half, step)
            mi0.material_override = tmat
            chunk.add_child(mi0)

            var mi1 := MeshInstance3D.new()
            mi1.name = "LOD1"
            mi1.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 2, half, step)
            mi1.material_override = tmat
            mi1.visible = false
            chunk.add_child(mi1)

            var mi2 := MeshInstance3D.new()
            mi2.name = "LOD2"
            mi2.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 4, half, step)
            mi2.material_override = tmat
            mi2.visible = false
            chunk.add_child(mi2)

    # Collision: HeightMapShape3D (matches cached heightmap)
    var ground := StaticBody3D.new()
    ground.name = "TerrainBody"
    ground.position = Vector3(-half, 0.0, -half)
    ground.scale = Vector3(step, 1.0, step)

    var shape := HeightMapShape3D.new()
    shape.map_width = res + 1
    shape.map_depth = res + 1
    shape.map_data = _hmap

    var cs := CollisionShape3D.new()
    cs.shape = shape
    ground.add_child(cs)
    _world_root.add_child(ground)

    # Pick initial LODs based on current camera position (or runway spawn).
    var cam_pos: Vector3 = _runway_spawn
    if _cam != null and is_instance_valid(_cam):
        cam_pos = _cam.global_position

    _apply_terrain_lod(terrain_root, cam_pos, lod_enabled, lod0_r, lod1_r)


func _apply_terrain_lod(terrain_root: Node3D, cam_pos: Vector3, lod_enabled: bool, lod0_r: float, lod1_r: float) -> void:
    # Switch per-chunk LOD based on distance to camera (XZ).
    if terrain_root == null:
        return

    for chunk in terrain_root.get_children():
        if not (chunk is Node3D):
            continue

        var c2: Vector2 = (chunk as Node3D).get_meta("center", Vector2.ZERO)
        var dx: float = cam_pos.x - c2.x
        var dz: float = cam_pos.z - c2.y
        var dist: float = sqrt(dx * dx + dz * dz)

        var lod: int = 0
        if lod_enabled:
            lod = 0 if dist < lod0_r else (1 if dist < lod1_r else 2)
        else:
            lod = 0

        var cur: int = int((chunk as Node3D).get_meta("lod", -1))
        if cur == lod:
            continue
        (chunk as Node3D).set_meta("lod", lod)

        var mi0 := (chunk as Node3D).get_node("LOD0") as MeshInstance3D
        var mi1 := (chunk as Node3D).get_node("LOD1") as MeshInstance3D
        var mi2 := (chunk as Node3D).get_node("LOD2") as MeshInstance3D
        mi0.visible = (lod == 0)
        mi1.visible = (lod == 1)
        mi2.visible = (lod == 2)


func _apply_prop_lod(cam_pos: Vector3, lod_enabled: bool, lod0_r: float, lod1_r: float) -> void:
    if _prop_lod_groups.is_empty():
        return

    for g in _prop_lod_groups:
        if not (g is Dictionary):
            continue
        var center: Vector3 = g.get("center", Vector3.ZERO)
        var dist: float = Vector2(cam_pos.x - center.x, cam_pos.z - center.z).length()

        var lod: int = 0
        if lod_enabled:
            lod = 0 if dist < lod0_r else (1 if dist < lod1_r else 2)
        else:
            lod = 0

        var cur: int = int(g.get("lod", -1))
        if cur == lod:
            continue
        g["lod"] = lod

        var n0: Node3D = g.get("lod0", null)
        var n1: Node3D = g.get("lod1", null)
        var n2: Node3D = g.get("lod2", null)
        if n0 != null and is_instance_valid(n0):
            n0.visible = (lod == 0)
        if n1 != null and is_instance_valid(n1):
            n1.visible = (lod == 1)
        if n2 != null and is_instance_valid(n2):
            n2.visible = (lod == 2)


func _build_runway() -> void:
    var spawn_z: float = -_runway_len * 0.35
    var y: float = maxf(_ground_height(0.0, spawn_z) + 50.0, Game.sea_level + 160.0)  # Doubled starting height

    _runway_spawn = Vector3(0.0, y, spawn_z)

    var runway_y: float = _ground_height(0.0, 0.0) + 0.05

    var runway := MeshInstance3D.new()
    runway.name = "Runway"
    var pm := PlaneMesh.new()
    pm.size = Vector2(_runway_w, _runway_len)
    pm.subdivide_depth = 8
    runway.mesh = pm
    runway.position = Vector3(0.0, runway_y, 0.0)
    var rmat := StandardMaterial3D.new()
    rmat.albedo_color = Color(0.07, 0.07, 0.075)
    rmat.roughness = 0.95
    runway.material_override = rmat
    _world_root.add_child(runway)

    var line := MeshInstance3D.new()
    line.name = "RunwayLine"
    var bm := BoxMesh.new()
    bm.size = Vector3(2.4, 0.15, _runway_len * 0.88)
    line.mesh = bm
    line.position = runway.position + Vector3(0.0, 0.10, 0.0)
    var lmat := StandardMaterial3D.new()
    lmat.albedo_color = Color(0.92, 0.92, 0.86)
    lmat.roughness = 1.0
    line.material_override = lmat
    _world_root.add_child(line)


    # A couple of WW2-style hangars for easy orientation.
    var hang_body_mat := StandardMaterial3D.new()
    hang_body_mat.albedo_color = Color(0.26, 0.28, 0.22) # olive drab
    hang_body_mat.roughness = 0.95

    var hang_roof_mat := StandardMaterial3D.new()
    hang_roof_mat.albedo_color = Color(0.20, 0.19, 0.18) # dark roof
    hang_roof_mat.roughness = 0.92

    for s in [-1, 1]:
        var hangar := Node3D.new()
        hangar.name = "Hangar_%s" % str(s)
        hangar.position = Vector3(float(s) * 92.0, runway_y, -140.0)
        _world_root.add_child(hangar)

        var base := MeshInstance3D.new()
        var hb := BoxMesh.new()
        hb.size = Vector3(46.0, 14.0, 72.0)
        base.mesh = hb
        base.position = Vector3(0.0, hb.size.y * 0.5, 0.0)
        base.material_override = hang_body_mat
        hangar.add_child(base)

        var roof := MeshInstance3D.new()
        roof.mesh = _get_gable_roof_mesh()
        roof.material_override = hang_roof_mat
        # Base of roof sits at y=0 in roof mesh, so place at top of walls.
        roof.position = Vector3(0.0, hb.size.y, 0.0)
        roof.scale = Vector3(hb.size.x * 1.08, 9.0 * 2.0, hb.size.z * 1.04)
        hangar.add_child(roof)

        # Front door face
        var door := MeshInstance3D.new()
        var db := BoxMesh.new()
        db.size = Vector3(hb.size.x * 0.96, hb.size.y * 0.75, 0.8)
        door.mesh = db
        door.position = Vector3(0.0, db.size.y * 0.5, -hb.size.z * 0.5 + 0.5)
        var dmat := StandardMaterial3D.new()
        dmat.albedo_color = Color(0.14, 0.14, 0.14)
        dmat.roughness = 0.98
        door.material_override = dmat
        hangar.add_child(door)


func _build_landmarks() -> void:
    # Distant pillars on the horizon: easy navigation markers.
    var rng := RandomNumberGenerator.new()
    rng.seed = int(Game.settings.get("world_seed", 0)) + 1337

    for i in range(10):
        var m := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.0
        cm.bottom_radius = rng.randf_range(420.0, 980.0)
        cm.height = rng.randf_range(650.0, 1900.0)
        m.mesh = cm
        var a: float = float(i) / 10.0 * TAU
        var dist: float = rng.randf_range(_terrain_size * 0.62, _terrain_size * 0.92)
        var x: float = cos(a) * dist
        var z: float = sin(a) * dist
        var y: float = _ground_height(x, z) + cm.height * 0.50 - 20.0
        m.position = Vector3(x, y, z)
        var mm := StandardMaterial3D.new()
        mm.albedo_color = Color(0.22, 0.23, 0.24)
        mm.roughness = 1.0
        m.material_override = mm
        _world_root.add_child(m)


func _build_rivers() -> void:
    if _rivers.is_empty():
        return

    var root := Node3D.new()
    root.name = "Rivers"
    _world_root.add_child(root)

    var river_mat := ShaderMaterial.new()
    river_mat.shader = preload("res://resources/shaders/ocean.gdshader")

    for r in _rivers:
        if not (r is Dictionary):
            continue
        var pts: PackedVector3Array = (r as Dictionary).get("points", PackedVector3Array())
        if pts.size() < 6:
            continue

        var w0: float = float((r as Dictionary).get("width0", 12.0))
        var w1: float = float((r as Dictionary).get("width1", 44.0))

        var mi := MeshInstance3D.new()
        mi.material_override = river_mat
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)

        for i in range(pts.size()):
            var t: float = float(i) / float(max(1, pts.size() - 1))
            var width: float = lerp(w0, w1, pow(t, 0.85))

            var p: Vector3 = pts[i]
            var p_prev: Vector3 = pts[max(0, i - 1)]
            var p_next: Vector3 = pts[min(pts.size() - 1, i + 1)]

            var dir: Vector3 = (p_next - p_prev)
            dir.y = 0.0
            if dir.length() < 0.001:
                dir = Vector3(1, 0, 0)
            dir = dir.normalized()
            var side: Vector3 = dir.cross(Vector3.UP).normalized()

            var y: float = _ground_height(p.x, p.z) + 0.18
            var py: Vector3 = Vector3(p.x, maxf(y, Game.sea_level + 0.05), p.z)

            var left: Vector3 = py - side * (width * 0.5)
            var right: Vector3 = py + side * (width * 0.5)

            # Build as a strip of quads.
            if i > 0:
                var t0: float = float(i - 1) / float(max(1, pts.size() - 1))
                var w_prev: float = lerp(w0, w1, pow(t0, 0.85))

                var pp: Vector3 = pts[i - 1]
                var pp_prev: Vector3 = pts[max(0, i - 2)]
                var pp_next: Vector3 = pts[min(pts.size() - 1, i)]
                var d2: Vector3 = (pp_next - pp_prev)
                d2.y = 0.0
                if d2.length() < 0.001:
                    d2 = Vector3(1, 0, 0)
                d2 = d2.normalized()
                var s2: Vector3 = d2.cross(Vector3.UP).normalized()

                var yy: float = _ground_height(pp.x, pp.z) + 0.18
                var ppy: Vector3 = Vector3(pp.x, maxf(yy, Game.sea_level + 0.05), pp.z)

                var l0: Vector3 = ppy - s2 * (w_prev * 0.5)
                var r0: Vector3 = ppy + s2 * (w_prev * 0.5)

                # Two tris: l0-r0-left and r0-right-left
                st.add_vertex(l0)
                st.add_vertex(r0)
                st.add_vertex(left)

                st.add_vertex(r0)
                st.add_vertex(right)
                st.add_vertex(left)

        st.generate_normals()
        mi.mesh = st.commit()
        root.add_child(mi)


func _build_set_dressing() -> void:
    var sd := Node3D.new()
    sd.name = "SetDressing"
    _world_root.add_child(sd)

    var seed: int = int(Game.settings.get("world_seed", 0))
    var rng := RandomNumberGenerator.new()
    rng.seed = seed + 9001

    _settlements = []

    var city_buildings: int = int(Game.settings.get("city_buildings", 1200))
    var town_count: int = int(Game.settings.get("town_count", 5))
    var hamlet_count: int = int(Game.settings.get("hamlet_count", 14))

    var city_center: Vector3 = _find_land_point(rng, Game.sea_level + 6.0, 0.50, true)
    var city := _build_settlement(sd, city_center, city_buildings, rng.randf_range(520.0, 820.0), 38.0, 160.0, Color(0.18, 0.18, 0.20))
    _settlements.append(city)

    # Towns
    for _i in range(town_count):
        var c: Vector3 = _find_land_point(rng, Game.sea_level + 6.0, 0.55, false)
        if _too_close_to_settlements(c, 1200.0):
            continue
        var t := _build_settlement(sd, c, rng.randi_range(220, 420), rng.randf_range(300.0, 520.0), 18.0, 90.0, Color(0.19, 0.19, 0.21))
        _settlements.append(t)

    # Hamlets (small clusters)
    for _i in range(hamlet_count):
        var c2: Vector3 = _find_land_point(rng, Game.sea_level + 6.0, 0.65, false)
        if _too_close_to_settlements(c2, 650.0):
            continue
        var h := _build_settlement(sd, c2, rng.randi_range(40, 110), rng.randf_range(150.0, 280.0), 10.0, 45.0, Color(0.20, 0.20, 0.22))
        _settlements.append(h)

    _build_roads(sd, rng)

    _build_fields(sd, rng, int(Game.settings.get("field_patches", 22)))
    _build_ponds(sd, int(Game.settings.get("pond_count", 10)), rng)
    _build_farm_barns(sd, int(Game.settings.get("farm_sites", 90)), rng)
    _build_industry(sd, int(Game.settings.get("industry_sites", 8)), rng)
    _build_boats(sd, rng)

    _build_beach_shacks(sd, rng, int(Game.settings.get("beach_shacks", 220)))
    _build_ww2_props(sd, rng)


func _too_close_to_settlements(p: Vector3, buffer: float) -> bool:
    for s in _settlements:
        if not (s is Dictionary):
            continue
        var c: Vector3 = (s as Dictionary).get("center", Vector3.ZERO)
        var r: float = float((s as Dictionary).get("radius", 300.0))
        if p.distance_to(c) < (r + buffer):
            return true
    return false


func _is_near_coast(x: float, z: float, rad: float) -> bool:
    var dirs := [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1), Vector2(0.707,0.707), Vector2(-0.707,0.707), Vector2(0.707,-0.707), Vector2(-0.707,-0.707)]
    for d in dirs:
        var xx: float = x + (d as Vector2).x * rad
        var zz: float = z + (d as Vector2).y * rad
        if _ground_height(xx, zz) <= Game.sea_level + 0.25:
            return true
    return false


func _find_land_point(rng: RandomNumberGenerator, min_h: float, slope_max: float, prefer_coast: bool) -> Vector3:
    # Finds a point on land, away from runway and steep cliffs.
    var half: float = _terrain_size * 0.5
    var runway_excl: float = 650.0

    for _try in range(1200):
        var x: float = rng.randf_range(-half, half)
        var z: float = rng.randf_range(-half, half)

        if Vector2(x, z).length() < runway_excl:
            continue

        var y: float = _ground_height(x, z)
        if y < min_h:
            continue

        var slope: float = _slope_at(x, z)
        if slope > slope_max:
            continue

        if prefer_coast:
            if not _is_near_coast(x, z, 520.0):
                continue

        return Vector3(x, y, z)

    # Fallback near runway outskirts.
    var fx: float = rng.randf_range(-half * 0.7, half * 0.7)
    var fz: float = rng.randf_range(-half * 0.7, half * 0.7)
    var fy: float = _ground_height(fx, fz)
    return Vector3(fx, fy, fz)


func _build_roads(parent: Node3D, rng: RandomNumberGenerator) -> void:
    var road_mat := StandardMaterial3D.new()
    road_mat.albedo_color = Color(0.10, 0.10, 0.11)
    road_mat.roughness = 0.98
    road_mat.metallic = 0.0

    # Artery roads: runway -> city, and city -> towns.
    if _settlements.size() >= 1 and (_settlements[0] is Dictionary):
        var city_center: Vector3 = (_settlements[0] as Dictionary).get("center", Vector3.ZERO)
        _make_road(parent, Vector3(0.0, 0.0, 0.0), city_center, 16.0, road_mat)

        for i in range(1, _settlements.size()):
            if not (_settlements[i] is Dictionary):
                continue
            var c: Vector3 = (_settlements[i] as Dictionary).get("center", Vector3.ZERO)
            _make_road(parent, city_center, c, 11.0, road_mat)

    # A couple of scenic diagonals.
    _make_road(parent, Vector3(-3600.0, 0.0, 900.0), Vector3(3600.0, 0.0, 900.0), 10.0, road_mat)
    _make_road(parent, Vector3(-1200.0, 0.0, -3600.0), Vector3(-1200.0, 0.0, 3600.0), 10.0, road_mat)


func _make_road(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> void:
    var dir: Vector3 = b - a
    dir.y = 0.0
    var dist: float = dir.length()
    if dist < 0.01:
        return
    var steps: int = max(2, int(dist / 90.0))
    var stepv: Vector3 = dir / float(steps)

    var mesh := BoxMesh.new()
    mesh.size = Vector3(width, 0.20, stepv.length())

    var n: Vector3 = dir.normalized()
    for i in range(steps):
        var p0: Vector3 = a + stepv * float(i)
        var p1: Vector3 = a + stepv * float(i + 1)
        var mid: Vector3 = (p0 + p1) * 0.5

        mid.y = _ground_height(mid.x, mid.z) + 0.12

        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.material_override = mat
        mi.position = mid

        parent.add_child(mi)
        mi.look_at(mid + n, Vector3.UP)


func _palette_pick(rng: RandomNumberGenerator, pal: Array) -> Color:
    if pal.is_empty():
        return Color(1, 1, 1)
    var idx: int = rng.randi_range(0, pal.size() - 1)
    return pal[idx] as Color


func _ensure_prop_mesh_cache() -> void:
    if _mesh_unit_box == null:
        _mesh_unit_box = BoxMesh.new()
        _mesh_unit_box.size = Vector3(1.0, 1.0, 1.0)

    if _mesh_unit_flat == null:
        _mesh_unit_flat = BoxMesh.new()
        _mesh_unit_flat.size = Vector3(1.0, 1.0, 1.0)

    if _mesh_unit_cyl == null:
        _mesh_unit_cyl = CylinderMesh.new()
        _mesh_unit_cyl.top_radius = 0.5
        _mesh_unit_cyl.bottom_radius = 0.5
        _mesh_unit_cyl.height = 1.0
        _mesh_unit_cyl.radial_segments = 12

    if _mesh_unit_cone == null:
        _mesh_unit_cone = CylinderMesh.new()
        _mesh_unit_cone.top_radius = 0.0
        _mesh_unit_cone.bottom_radius = 0.5
        _mesh_unit_cone.height = 1.0
        _mesh_unit_cone.radial_segments = 10

    if _mesh_chimney == null:
        _mesh_chimney = CylinderMesh.new()
        _mesh_chimney.top_radius = 0.5
        _mesh_chimney.bottom_radius = 0.5
        _mesh_chimney.height = 1.0
        _mesh_chimney.radial_segments = 8


func _get_gable_roof_mesh() -> ArrayMesh:
    # Unit gable roof mesh:
    # - Base spans x,z in [-0.5, 0.5]
    # - Base sits at y=0.0 (top of walls), ridge at y=0.5
    if _roof_mesh_gable != null:
        return _roof_mesh_gable

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var A := Vector3(-0.5, 0.0, -0.5)
    var B := Vector3( 0.5, 0.0, -0.5)
    var C := Vector3( 0.0, 0.5, -0.5)

    var D := Vector3(-0.5, 0.0,  0.5)
    var E := Vector3( 0.5, 0.0,  0.5)
    var F := Vector3( 0.0, 0.5,  0.5)

    # Front triangle
    st.add_vertex(A); st.add_vertex(B); st.add_vertex(C)
    # Back triangle
    st.add_vertex(D); st.add_vertex(F); st.add_vertex(E)

    # Left roof face (two tris)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(F)
    st.add_vertex(A); st.add_vertex(F); st.add_vertex(D)

    # Right roof face (two tris)
    st.add_vertex(B); st.add_vertex(E); st.add_vertex(F)
    st.add_vertex(B); st.add_vertex(F); st.add_vertex(C)

    # Bottom (optional)
    st.add_vertex(A); st.add_vertex(D); st.add_vertex(E)
    st.add_vertex(A); st.add_vertex(E); st.add_vertex(B)

    st.generate_normals()
    _roof_mesh_gable = st.commit()
    return _roof_mesh_gable


func _get_hip_roof_mesh() -> ArrayMesh:
    # Unit hip roof (pyramid-ish): base in [-0.5,0.5], apex at y=0.5.
    if _roof_mesh_hip != null:
        return _roof_mesh_hip

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var A := Vector3(-0.5, 0.0, -0.5)
    var B := Vector3( 0.5, 0.0, -0.5)
    var C := Vector3( 0.5, 0.0,  0.5)
    var D := Vector3(-0.5, 0.0,  0.5)
    var P := Vector3( 0.0, 0.5,  0.0)

    # Four roof faces
    st.add_vertex(A); st.add_vertex(B); st.add_vertex(P)
    st.add_vertex(B); st.add_vertex(C); st.add_vertex(P)
    st.add_vertex(C); st.add_vertex(D); st.add_vertex(P)
    st.add_vertex(D); st.add_vertex(A); st.add_vertex(P)

    # Bottom
    st.add_vertex(A); st.add_vertex(D); st.add_vertex(C)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(B)

    st.generate_normals()
    _roof_mesh_hip = st.commit()
    return _roof_mesh_hip

func _get_mansard_roof_mesh() -> ArrayMesh:
    # Unit mansard roof: base in [-0.5,0.5], lower slope steep, upper slope shallow
    if _roof_mesh_mansard != null:
        return _roof_mesh_mansard

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Base points
    var A := Vector3(-0.5, 0.0, -0.5)
    var B := Vector3( 0.5, 0.0, -0.5)
    var C := Vector3( 0.5, 0.0,  0.5)
    var D := Vector3(-0.5, 0.0,  0.5)
    
    # Mid points (where slope changes)
    var Am := Vector3(-0.35, 0.25, -0.35)
    var Bm := Vector3( 0.35, 0.25, -0.35)
    var Cm := Vector3( 0.35, 0.25,  0.35)
    var Dm := Vector3(-0.35, 0.25,  0.35)
    
    # Top points
    var At := Vector3(-0.20, 0.50, -0.20)
    var Bt := Vector3( 0.20, 0.50, -0.20)
    var Ct := Vector3( 0.20, 0.50,  0.20)
    var Dt := Vector3(-0.20, 0.50,  0.20)

    # Lower slope (steep) - front
    st.add_vertex(A); st.add_vertex(Am); st.add_vertex(B)
    st.add_vertex(B); st.add_vertex(Am); st.add_vertex(Bm)
    
    # Lower slope - right
    st.add_vertex(B); st.add_vertex(Bm); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Bm); st.add_vertex(Cm)
    
    # Lower slope - back
    st.add_vertex(C); st.add_vertex(Cm); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Cm); st.add_vertex(Dm)
    
    # Lower slope - left
    st.add_vertex(D); st.add_vertex(Dm); st.add_vertex(A)
    st.add_vertex(A); st.add_vertex(Dm); st.add_vertex(Am)

    # Upper slope (shallow) - front
    st.add_vertex(Am); st.add_vertex(At); st.add_vertex(Bm)
    st.add_vertex(Bm); st.add_vertex(At); st.add_vertex(Bt)
    
    # Upper slope - right
    st.add_vertex(Bm); st.add_vertex(Bt); st.add_vertex(Cm)
    st.add_vertex(Cm); st.add_vertex(Bt); st.add_vertex(Ct)
    
    # Upper slope - back
    st.add_vertex(Cm); st.add_vertex(Ct); st.add_vertex(Dm)
    st.add_vertex(Dm); st.add_vertex(Ct); st.add_vertex(Dt)
    
    # Upper slope - left
    st.add_vertex(Dm); st.add_vertex(Dt); st.add_vertex(Am)
    st.add_vertex(Am); st.add_vertex(Dt); st.add_vertex(At)

    # Top cap
    st.add_vertex(At); st.add_vertex(Bt); st.add_vertex(Ct)
    st.add_vertex(At); st.add_vertex(Ct); st.add_vertex(Dt)

    st.generate_normals()
    _roof_mesh_mansard = st.commit()
    return _roof_mesh_mansard

func _get_gambrel_roof_mesh() -> ArrayMesh:
    # Unit gambrel roof (barn-style): base in [-0.5,0.5], two slopes per side
    if _roof_mesh_gambrel != null:
        return _roof_mesh_gambrel

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Base points
    var A := Vector3(-0.5, 0.0, -0.5)
    var B := Vector3( 0.5, 0.0, -0.5)
    var C := Vector3( 0.5, 0.0,  0.5)
    var D := Vector3(-0.5, 0.0,  0.5)
    
    # Mid points
    var Am := Vector3(-0.5, 0.30, 0.0)
    var Bm := Vector3( 0.5, 0.30, 0.0)
    var Cm := Vector3( 0.0, 0.30,  0.5)
    var Dm := Vector3( 0.0, 0.30, -0.5)
    
    # Top points
    var P := Vector3( 0.0, 0.50,  0.0)

    # Front gambrel
    st.add_vertex(A); st.add_vertex(Am); st.add_vertex(P)
    st.add_vertex(B); st.add_vertex(Bm); st.add_vertex(P)
    st.add_vertex(A); st.add_vertex(P); st.add_vertex(B)

    # Back gambrel
    st.add_vertex(C); st.add_vertex(Cm); st.add_vertex(P)
    st.add_vertex(D); st.add_vertex(Dm); st.add_vertex(P)
    st.add_vertex(C); st.add_vertex(P); st.add_vertex(D)

    # Left end
    st.add_vertex(A); st.add_vertex(Am); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Am); st.add_vertex(Dm)

    # Right end
    st.add_vertex(B); st.add_vertex(Bm); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Bm); st.add_vertex(Cm)

    st.generate_normals()
    _roof_mesh_gambrel = st.commit()
    return _roof_mesh_gambrel

func _get_flat_roof_mesh() -> ArrayMesh:
    # Unit flat roof with slight parapet
    if _roof_mesh_flat != null:
        return _roof_mesh_flat

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var A := Vector3(-0.5, 0.0, -0.5)
    var B := Vector3( 0.5, 0.0, -0.5)
    var C := Vector3( 0.5, 0.0,  0.5)
    var D := Vector3(-0.5, 0.0,  0.5)
    
    var At := Vector3(-0.45, 0.05, -0.45)
    var Bt := Vector3( 0.45, 0.05, -0.45)
    var Ct := Vector3( 0.45, 0.05,  0.45)
    var Dt := Vector3(-0.45, 0.05,  0.45)

    # Top surface
    st.add_vertex(At); st.add_vertex(Bt); st.add_vertex(Ct)
    st.add_vertex(At); st.add_vertex(Ct); st.add_vertex(Dt)

    # Parapet - front
    st.add_vertex(A); st.add_vertex(At); st.add_vertex(B)
    st.add_vertex(B); st.add_vertex(At); st.add_vertex(Bt)

    # Parapet - right
    st.add_vertex(B); st.add_vertex(Bt); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Bt); st.add_vertex(Ct)

    # Parapet - back
    st.add_vertex(C); st.add_vertex(Ct); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Ct); st.add_vertex(Dt)

    # Parapet - left
    st.add_vertex(D); st.add_vertex(Dt); st.add_vertex(A)
    st.add_vertex(A); st.add_vertex(Dt); st.add_vertex(At)

    st.generate_normals()
    _roof_mesh_flat = st.commit()
    return _roof_mesh_flat

func _create_window_mesh() -> ArrayMesh:
    # Simple window mesh with frame and glass
    if _window_mesh != null:
        return _window_mesh

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Window frame (0.2m deep)
    var frame_width = 0.1
    var frame_depth = 0.2
    var glass_thickness = 0.02
    
    # Outer frame
    var A := Vector3(-0.5, -0.5, 0.0)
    var B := Vector3( 0.5, -0.5, 0.0)
    var C := Vector3( 0.5,  0.5, 0.0)
    var D := Vector3(-0.5,  0.5, 0.0)
    
    var Af := Vector3(-0.5, -0.5, -frame_depth)
    var Bf := Vector3( 0.5, -0.5, -frame_depth)
    var Cf := Vector3( 0.5,  0.5, -frame_depth)
    var Df := Vector3(-0.5,  0.5, -frame_depth)

    # Inner frame (glass area)
    var Ai := Vector3(-0.5 + frame_width, -0.5 + frame_width, 0.0)
    var Bi := Vector3( 0.5 - frame_width, -0.5 + frame_width, 0.0)
    var Ci := Vector3( 0.5 - frame_width,  0.5 - frame_width, 0.0)
    var Di := Vector3(-0.5 + frame_width,  0.5 - frame_width, 0.0)
    
    # Inner frame (glass area)
    var Aif := Vector3(-0.5 + frame_width, -0.5 + frame_width, -frame_depth)
    var Bif := Vector3( 0.5 - frame_width, -0.5 + frame_width, -frame_depth)
    var Cif := Vector3( 0.5 - frame_width,  0.5 - frame_width, -frame_depth)
    var Dif := Vector3(-0.5 + frame_width,  0.5 - frame_width, -frame_depth)

    # Frame front
    st.add_vertex(A); st.add_vertex(B); st.add_vertex(C)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(D)
    
    # Frame back
    st.add_vertex(Df); st.add_vertex(Cf); st.add_vertex(Bf)
    st.add_vertex(Df); st.add_vertex(Bf); st.add_vertex(Af)

    # Frame sides
    st.add_vertex(A); st.add_vertex(Af); st.add_vertex(B)
    st.add_vertex(B); st.add_vertex(Af); st.add_vertex(Bf)
    
    st.add_vertex(B); st.add_vertex(Bf); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Bf); st.add_vertex(Cf)
    
    st.add_vertex(C); st.add_vertex(Cf); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Cf); st.add_vertex(Df)
    
    st.add_vertex(D); st.add_vertex(Df); st.add_vertex(A)
    st.add_vertex(A); st.add_vertex(Df); st.add_vertex(Af)

    # Inner frame (glass area) - front
    st.add_vertex(Ai); st.add_vertex(Bi); st.add_vertex(Ci)
    st.add_vertex(Ai); st.add_vertex(Ci); st.add_vertex(Di)
    
    # Inner frame - back
    st.add_vertex(Dif); st.add_vertex(Cif); st.add_vertex(Bif)
    st.add_vertex(Dif); st.add_vertex(Bif); st.add_vertex(Aif)

    # Glass (thin plane)
    st.add_vertex(Ai); st.add_vertex(Aif); st.add_vertex(Bi)
    st.add_vertex(Bi); st.add_vertex(Aif); st.add_vertex(Bif)
    
    st.add_vertex(Bi); st.add_vertex(Bif); st.add_vertex(Ci)
    st.add_vertex(Ci); st.add_vertex(Bif); st.add_vertex(Cif)
    
    st.add_vertex(Ci); st.add_vertex(Cif); st.add_vertex(Di)
    st.add_vertex(Di); st.add_vertex(Cif); st.add_vertex(Dif)
    
    st.add_vertex(Di); st.add_vertex(Dif); st.add_vertex(Ai)
    st.add_vertex(Ai); st.add_vertex(Dif); st.add_vertex(Aif)

    st.generate_normals()
    _window_mesh = st.commit()
    return _window_mesh

func _create_door_mesh() -> ArrayMesh:
    # Simple door mesh with frame
    if _door_mesh != null:
        return _door_mesh

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Door dimensions (2m tall, 0.8m wide, 0.1m thick)
    var width = 0.8
    var height = 2.0
    var thickness = 0.1
    
    var A := Vector3(-width/2, 0.0, 0.0)
    var B := Vector3( width/2, 0.0, 0.0)
    var C := Vector3( width/2, height, 0.0)
    var D := Vector3(-width/2, height, 0.0)
    
    var Af := Vector3(-width/2, 0.0, -thickness)
    var Bf := Vector3( width/2, 0.0, -thickness)
    var Cf := Vector3( width/2, height, -thickness)
    var Df := Vector3(-width/2, height, -thickness)

    # Door front
    st.add_vertex(A); st.add_vertex(B); st.add_vertex(C)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(D)
    
    # Door back
    st.add_vertex(Df); st.add_vertex(Cf); st.add_vertex(Bf)
    st.add_vertex(Df); st.add_vertex(Bf); st.add_vertex(Af)

    # Door sides
    st.add_vertex(A); st.add_vertex(Af); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Af); st.add_vertex(Df)
    
    st.add_vertex(D); st.add_vertex(Df); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Df); st.add_vertex(Cf)
    
    st.add_vertex(C); st.add_vertex(Cf); st.add_vertex(B)
    st.add_vertex(B); st.add_vertex(Cf); st.add_vertex(Bf)
    
    st.add_vertex(B); st.add_vertex(Bf); st.add_vertex(A)
    st.add_vertex(A); st.add_vertex(Bf); st.add_vertex(Af)

    st.generate_normals()
    _door_mesh = st.commit()
    return _door_mesh

func _create_trim_mesh() -> ArrayMesh:
    # Simple decorative trim/cornice mesh
    if _trim_mesh != null:
        return _trim_mesh

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Simple cornice profile (1m long segment)
    var A := Vector3(-0.5, 0.0, 0.0)
    var B := Vector3( 0.5, 0.0, 0.0)
    var C := Vector3( 0.5, 0.1, 0.0)
    var D := Vector3( 0.45, 0.15, 0.0)
    var E := Vector3(-0.45, 0.15, 0.0)
    var F := Vector3(-0.5, 0.1, 0.0)
    
    var depth = 0.1
    var Af := Vector3(-0.5, 0.0, -depth)
    var Bf := Vector3( 0.5, 0.0, -depth)
    var Cf := Vector3( 0.5, 0.1, -depth)
    var Df := Vector3( 0.45, 0.15, -depth)
    var Ef := Vector3(-0.45, 0.15, -depth)
    var Ff := Vector3(-0.5, 0.1, -depth)

    # Front profile
    st.add_vertex(A); st.add_vertex(B); st.add_vertex(C)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(D)
    st.add_vertex(A); st.add_vertex(D); st.add_vertex(E)
    st.add_vertex(A); st.add_vertex(E); st.add_vertex(F)

    # Back profile
    st.add_vertex(Ff); st.add_vertex(Ef); st.add_vertex(Df)
    st.add_vertex(Ff); st.add_vertex(Df); st.add_vertex(Cf)
    st.add_vertex(Ff); st.add_vertex(Cf); st.add_vertex(Bf)
    st.add_vertex(Ff); st.add_vertex(Bf); st.add_vertex(Af)

    # Connect front to back
    st.add_vertex(A); st.add_vertex(Af); st.add_vertex(B)
    st.add_vertex(B); st.add_vertex(Af); st.add_vertex(Bf)
    
    st.add_vertex(B); st.add_vertex(Bf); st.add_vertex(C)
    st.add_vertex(C); st.add_vertex(Bf); st.add_vertex(Cf)
    
    st.add_vertex(C); st.add_vertex(Cf); st.add_vertex(D)
    st.add_vertex(D); st.add_vertex(Cf); st.add_vertex(Df)
    
    st.add_vertex(D); st.add_vertex(Df); st.add_vertex(E)
    st.add_vertex(E); st.add_vertex(Df); st.add_vertex(Ef)
    
    st.add_vertex(E); st.add_vertex(Ef); st.add_vertex(F)
    st.add_vertex(F); st.add_vertex(Ef); st.add_vertex(Ff)
    
    st.add_vertex(F); st.add_vertex(Ff); st.add_vertex(A)
    st.add_vertex(A); st.add_vertex(Ff); st.add_vertex(Af)

    st.generate_normals()
    _trim_mesh = st.commit()
    return _trim_mesh

func _create_damage_mesh() -> ArrayMesh:
    # Simple damage decal mesh (bullet holes, cracks)
    if _damage_mesh != null:
        return _damage_mesh

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Create a simple quad for damage decals
    var size = 0.5
    var A := Vector3(-size/2, -size/2, 0.0)
    var B := Vector3( size/2, -size/2, 0.0)
    var C := Vector3( size/2,  size/2, 0.0)
    var D := Vector3(-size/2,  size/2, 0.0)

    st.add_vertex(A); st.add_vertex(B); st.add_vertex(C)
    st.add_vertex(A); st.add_vertex(C); st.add_vertex(D)

    st.generate_normals()
    _damage_mesh = st.commit()
    return _damage_mesh

func _create_window_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.7, 0.8, 0.9, 0.8)  # Light blue tinted glass
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.roughness = 0.1
    return mat

func _create_door_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.albedo_color = Color(0.3, 0.2, 0.1)  # Dark wood
    mat.roughness = 0.8
    mat.metallic = 0.05
    return mat

func _create_trim_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.albedo_color = Color(0.8, 0.75, 0.7)  # Light stone/stucco
    mat.roughness = 0.6
    return mat

func _create_weathering_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.roughness = 1.0
    return mat


func _ensure_building_kits() -> void:
    """Build BuildingKit dictionaries for each settlement style.

    A BuildingKit organizes all building-related resources for a specific architectural style:
    - External meshes (from asset library)
    - Procedural variants (generated buildings)
    - Materials with textures
    - Detail meshes (future: chimneys, balconies, etc)
    """
    if not _building_kits.is_empty():
        return  # Already built

    _ensure_prop_mesh_cache()

    # Get procedural roof meshes
    var gable: ArrayMesh = _get_gable_roof_mesh()
    var hip: ArrayMesh = _get_hip_roof_mesh()

    # Load external assets if available
    var euro_external: Array[Mesh] = []
    var industrial_external: Array[Mesh] = []
    if _assets != null and _assets.enabled():
        euro_external = _assets.get_mesh_variants("euro_buildings")
        industrial_external = _assets.get_mesh_variants("industrial_buildings")

    # Build kit for each style
    var styles: Array[String] = ["hamlet", "town", "city", "industrial", "coastal"]

    for style in styles:
        var kit: Dictionary = {
            "style": style,
            "external_meshes": [],
            "procedural_variants": [],
            "wall_material": null,
            "roof_material": null,
            "detail_meshes": []
        }

        # Load appropriate external meshes
        if style in ["hamlet", "town", "city"]:
            # European/suburban buildings for residential areas
            for i in range(euro_external.size()):
                kit["external_meshes"].append({
                    "name": "ext_euro_%d" % i,
                    "mesh": euro_external[i],
                    "weight": 1.0
                })

        if style in ["city", "industrial"]:
            # Industrial buildings for urban/industrial areas
            var industrial_weight: float = 1.2 if style == "city" else 1.5
            for i in range(industrial_external.size()):
                kit["external_meshes"].append({
                    "name": "ext_industrial_%d" % i,
                    "mesh": industrial_external[i],
                    "weight": industrial_weight
                })

        # Add procedural variants (silhouettes)
        var variants: Array = []

        # ===== NEW SILHOUETTE VARIETY =====
        # L-shaped buildings
        variants.append({"name": "house_L_gable", "footprint": "L", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.20, "sz_mul": 1.20, "sy_mul": 1.00, "chimney_prob": 0.25, "weight": 1.8, "has_trim": true, "has_windows": true, "has_doors": true})
        variants.append({"name": "house_L_hip", "footprint": "L", "wall_mesh": _mesh_unit_box, "roof_mesh": hip, "roof_kind": "hip", "sx_mul": 1.15, "sz_mul": 1.15, "sy_mul": 1.00, "chimney_prob": 0.20, "weight": 1.5, "has_trim": true, "has_windows": true, "has_doors": true})

        # T-shaped buildings
        variants.append({"name": "house_T_gable", "footprint": "T", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.30, "sz_mul": 1.10, "sy_mul": 1.00, "chimney_prob": 0.30, "weight": 1.2, "has_trim": true, "has_windows": true, "has_doors": true})

        # U-shaped buildings
        variants.append({"name": "house_U_gable", "footprint": "U", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.40, "sz_mul": 1.30, "sy_mul": 1.00, "chimney_prob": 0.35, "weight": 0.8, "has_trim": true, "has_windows": true, "has_doors": true})

        # Step-back buildings (multi-story with setbacks)
        variants.append({"name": "apartment_stepback", "footprint": "rect", "step_back": true, "step_floors": 2, "wall_mesh": _mesh_unit_box, "roof_mesh": _mesh_unit_flat, "roof_kind": "flat", "sx_mul": 1.20, "sz_mul": 1.20, "sy_mul": 2.20, "chimney_prob": 0.05, "weight": 1.8, "has_trim": true, "has_windows": true, "has_doors": true})

        # ===== NEW ROOF FAMILIES =====
        # Mansard roof (French style)
        var mansard: ArrayMesh = _get_mansard_roof_mesh()
        variants.append({"name": "house_mansard", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": mansard, "roof_kind": "mansard", "sx_mul": 1.10, "sz_mul": 1.10, "sy_mul": 1.20, "chimney_prob": 0.40, "weight": 1.6, "has_trim": true, "has_windows": true, "has_doors": true})

        # Gambrel roof (barn style)
        var gambrel: ArrayMesh = _get_gambrel_roof_mesh()
        variants.append({"name": "barn_gambrel", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": gambrel, "roof_kind": "gambrel", "sx_mul": 1.40, "sz_mul": 1.20, "sy_mul": 0.90, "chimney_prob": 0.10, "weight": 1.4, "has_trim": false, "has_windows": true, "has_doors": true})

        # ===== ORIGINAL VARIANTS (enhanced with details) =====
        variants.append({"name": "house_gable", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.00, "sz_mul": 1.00, "sy_mul": 1.00, "chimney_prob": 0.35, "weight": 2.1, "has_trim": true, "has_windows": true, "has_doors": true})
        variants.append({"name": "house_gable_wide", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.35, "sz_mul": 0.95, "sy_mul": 1.00, "chimney_prob": 0.30, "weight": 1.4, "has_trim": true, "has_windows": true, "has_doors": true})
        variants.append({"name": "house_gable_narrow", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 0.80, "sz_mul": 1.25, "sy_mul": 1.05, "chimney_prob": 0.40, "weight": 1.2, "has_trim": true, "has_windows": true, "has_doors": true})
        variants.append({"name": "house_hip", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": hip, "roof_kind": "hip", "sx_mul": 1.05, "sz_mul": 1.05, "sy_mul": 1.00, "chimney_prob": 0.22, "weight": 1.7, "has_trim": true, "has_windows": true, "has_doors": true})
        variants.append({"name": "villa_hip", "footprint": "rect", "wall_mesh": _mesh_unit_box, "roof_mesh": hip, "roof_kind": "hip", "sx_mul": 1.45, "sz_mul": 1.25, "sy_mul": 0.95, "chimney_prob": 0.18, "weight": 0.55 if style == "hamlet" else 0.85, "has_trim": true, "has_windows": true, "has_doors": true})

        # Rowhouses for urban styles
        if style != "hamlet":
            variants.append({"name": "rowhouse_short", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.20, "sz_mul": 0.70, "sy_mul": 1.10, "chimney_prob": 0.18, "weight": 1.0})
            variants.append({"name": "rowhouse_long", "wall_mesh": _mesh_unit_box, "roof_mesh": gable, "roof_kind": "gable", "sx_mul": 1.85, "sz_mul": 0.65, "sy_mul": 1.15, "chimney_prob": 0.14, "weight": 0.8})

        # Apartments for cities
        if style in ["city", "town"]:
            var apt_weight: float = 1.35 if style == "city" else 0.55
            var tall_weight: float = 0.85 if style == "city" else 0.15
            variants.append({"name": "apartment_mid", "wall_mesh": _mesh_unit_box, "roof_mesh": _mesh_unit_flat, "roof_kind": "flat", "sx_mul": 1.10, "sz_mul": 1.10, "sy_mul": 1.55, "chimney_prob": 0.06, "weight": apt_weight})
            variants.append({"name": "apartment_tall", "wall_mesh": _mesh_unit_box, "roof_mesh": _mesh_unit_flat, "roof_kind": "flat", "sx_mul": 1.05, "sz_mul": 1.05, "sy_mul": 2.15, "chimney_prob": 0.02, "weight": tall_weight})

        # Industrial/warehouses
        if style != "hamlet":
            var ind_weight: float = 0.70
            var warehouse_weight: float = 0.55 if style == "city" else 0.35
            variants.append({"name": "industry_block", "wall_mesh": _mesh_unit_box, "roof_mesh": _mesh_unit_flat, "roof_kind": "flat", "sx_mul": 1.65, "sz_mul": 1.25, "sy_mul": 0.95, "chimney_prob": 0.00, "weight": ind_weight})
            variants.append({"name": "warehouse_long", "wall_mesh": _mesh_unit_box, "roof_mesh": _mesh_unit_flat, "roof_kind": "shed", "sx_mul": 2.05, "sz_mul": 0.95, "sy_mul": 0.85, "chimney_prob": 0.00, "weight": warehouse_weight})

        # Landmarks (towers, churches) - only for detailed LOD
        if style != "hamlet":
            variants.append({"name": "tower_round", "wall_mesh": _mesh_unit_cyl, "roof_mesh": _mesh_unit_cone, "roof_kind": "cone", "force_square": true, "sx_mul": 0.70, "sz_mul": 0.70, "sy_mul": 1.85, "chimney_prob": 0.0, "weight": 0.35})
            variants.append({"name": "church", "wall_mesh": _mesh_unit_cyl, "roof_mesh": _mesh_unit_cone, "roof_kind": "cone", "force_square": true, "sx_mul": 0.95, "sz_mul": 0.95, "sy_mul": 2.35, "chimney_prob": 0.0, "weight": 0.22})

        kit["procedural_variants"] = variants

        # Create materials with textures
        var wall_mat := StandardMaterial3D.new()
        wall_mat.vertex_color_use_as_albedo = true
        wall_mat.albedo_color = Color(1, 1, 1)
        wall_mat.roughness = 0.92
        wall_mat.metallic = 0.0

        # Load textures based on style
        if _assets != null and _assets.enabled():
            var texture_key: String = "building_atlas_euro"
            if style == "industrial":
                texture_key = "building_atlas_industrial"

            var textures: Dictionary = _assets.get_texture_set(texture_key)
            if textures.size() > 0:
                if textures.has("albedo"):
                    wall_mat.albedo_texture = textures["albedo"]
                if textures.has("normal"):
                    wall_mat.normal_enabled = true
                    wall_mat.normal_texture = textures["normal"]
                if textures.has("roughness"):
                    wall_mat.roughness_texture = textures["roughness"]
                if textures.has("metallic") and style == "industrial":
                    wall_mat.metallic = 0.05
                    wall_mat.metallic_texture = textures["metallic"]

        kit["wall_material"] = wall_mat

        # Roof material with texture support
        var roof_mat := StandardMaterial3D.new()
        roof_mat.vertex_color_use_as_albedo = true
        roof_mat.albedo_color = Color(1, 1, 1)
        roof_mat.roughness = 0.85
        roof_mat.metallic = 0.0

        # Load roof textures based on style
        if _assets != null and _assets.enabled():
            var roof_texture_key: String = "roof_tiles"
            if style == "industrial":
                roof_texture_key = "roof_metal"

            var roof_textures: Dictionary = _assets.get_texture_set(roof_texture_key)
            if roof_textures.size() > 0:
                if roof_textures.has("albedo"):
                    roof_mat.albedo_texture = roof_textures["albedo"]
                if roof_textures.has("normal"):
                    roof_mat.normal_enabled = true
                    roof_mat.normal_texture = roof_textures["normal"]
                if roof_textures.has("roughness"):
                    roof_mat.roughness_texture = roof_textures["roughness"]

        kit["roof_material"] = roof_mat

        # Add architectural detail materials
        kit["window_material"] = _create_window_material()
        kit["door_material"] = _create_door_material()
        kit["trim_material"] = _create_trim_material()
        kit["damage_material"] = _create_weathering_material()

        # Add detail meshes
        kit["window_mesh"] = _create_window_mesh()
        kit["door_mesh"] = _create_door_mesh()
        kit["trim_mesh"] = _create_trim_mesh()
        kit["damage_mesh"] = _create_damage_mesh()

        # Set damage probability based on style (WW2 era appropriate)
        var damage_prob: float = 0.1
        if style == "hamlet":
            damage_prob = 0.1
        elif style == "town":
            damage_prob = 0.2
        elif style == "city":
            damage_prob = 0.3
        elif style == "industrial":
            damage_prob = 0.5
        elif style == "coastal":
            damage_prob = 0.4
        
        kit["damage_probability"] = damage_prob

        _building_kits[style] = kit


func _mm_batch(parent: Node3D, name: String, mesh: Mesh, mat: Material, xforms: Array, cols: Array) -> MultiMeshInstance3D:
    if xforms.is_empty() or mesh == null:
        return null

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = mesh

    var use_cols: bool = (cols.size() == xforms.size() and cols.size() > 0)
    mm.use_colors = use_cols
    mm.instance_count = xforms.size()
    for i in range(mm.instance_count):
        mm.set_instance_transform(i, xforms[i] as Transform3D)
        if use_cols:
            mm.set_instance_color(i, cols[i] as Color)

    var mi := MultiMeshInstance3D.new()
    mi.name = name
    mi.multimesh = mm
    if mat != null:
        mi.material_override = mat
    parent.add_child(mi)
    return mi


func _pick_subset(rng: RandomNumberGenerator, indices: Array, want: int) -> Array:
    if indices.is_empty():
        return []
    var out: Array = []
    var pool := indices.duplicate()
    want = clampi(want, 1, pool.size())
    for _i in range(want):
        var j: int = rng.randi_range(0, pool.size() - 1)
        out.append(pool[j])
        pool.remove_at(j)
    return out


func _occ_key(px: float, pz: float, cell: float) -> int:
    # 2D hash key for occupancy grids. Uses 64-bit int packing.
    var c: float = maxf(0.001, cell)
    var ix: int = int(floor(px / c))
    var iz: int = int(floor(pz / c))
    return (ix << 32) ^ (iz & 0xFFFFFFFF)


func _weighted_pick(rng: RandomNumberGenerator, variants: Array) -> int:
    var total: float = 0.0
    for v in variants:
        total += float((v as Dictionary).get("weight", 1.0))
    var t: float = rng.randf() * maxf(0.0001, total)
    var acc: float = 0.0
    for i in range(variants.size()):
        acc += float((variants[i] as Dictionary).get("weight", 1.0))
        if t <= acc:
            return i
    return variants.size() - 1


func _get_settlement_variants(style: String, lod_level: int) -> Array:
    """Get building variants for a settlement style using BuildingKit system.

    Returns Array[Dictionary] with building definitions (both external and procedural).
    """
    # Handle far LOD first (simple proxy)
    if lod_level >= 2:
        _ensure_prop_mesh_cache()
        return [
            {"name": "proxy", "kind": "proc", "wall_mesh": _mesh_unit_box, "roof_mesh": null, "roof_kind": "none", "sx_mul": 1.0, "sz_mul": 1.0, "sy_mul": 1.0, "chimney_prob": 0.0, "weight": 1.0}
        ]

    # Ensure building kits are initialized
    _ensure_building_kits()

    # Get the appropriate kit for this style
    var kit: Dictionary = _building_kits.get(style, {})
    if kit.is_empty():
        # Fallback to "town" kit if style not found
        kit = _building_kits.get("town", {})

    if kit.is_empty():
        # Absolute fallback - empty array
        return []

    var pool: Array = []

    # Add external meshes from the kit
    var external_meshes: Array = kit.get("external_meshes", [])
    for ext in external_meshes:
        var entry: Dictionary = (ext as Dictionary).duplicate()
        entry["kind"] = "ext"
        pool.append(entry)

    # Add procedural variants from the kit
    var proc_variants: Array = kit.get("procedural_variants", [])
    for proc in proc_variants:
        var entry: Dictionary = (proc as Dictionary).duplicate()
        entry["kind"] = "proc"
        pool.append(entry)

    # LOD trimming: remove chimneys for mid-range LOD
    if lod_level >= 1:
        for v in pool:
            (v as Dictionary)["chimney_prob"] = 0.0

    return pool


func _emit_settlement_buildings(parent: Node3D, buildings: Array, center: Vector3, style: String, lod_level: int, base_col: Color) -> void:
    if buildings.is_empty():
        return

    _ensure_prop_mesh_cache()

    var rng := RandomNumberGenerator.new()
    rng.seed = int(Game.settings.get("world_seed", 0)) + int(absf(center.x + center.z) * 0.25) + lod_level * 997

    # Get materials from BuildingKit
    _ensure_building_kits()
    var kit: Dictionary = _building_kits.get(style, _building_kits.get("town", {}))

    var wall_mat: Material = kit.get("wall_material", null)
    var roof_mat: Material = kit.get("roof_material", null)

    # Fallback materials if kit doesn't have them - enhanced with better PBR
    if wall_mat == null:
        wall_mat = StandardMaterial3D.new()
        (wall_mat as StandardMaterial3D).vertex_color_use_as_albedo = true
        (wall_mat as StandardMaterial3D).albedo_color = Color(0.9, 0.85, 0.8)  # Warm off-white
        (wall_mat as StandardMaterial3D).roughness = 0.92
        (wall_mat as StandardMaterial3D).metallic = 0.0
        (wall_mat as StandardMaterial3D).normal_enabled = false

    if roof_mat == null:
        roof_mat = StandardMaterial3D.new()
        (roof_mat as StandardMaterial3D).vertex_color_use_as_albedo = true
        (roof_mat as StandardMaterial3D).albedo_color = Color(0.7, 0.6, 0.5)  # Brownish roof color
        (roof_mat as StandardMaterial3D).roughness = 0.86
        (roof_mat as StandardMaterial3D).metallic = 0.0
        (roof_mat as StandardMaterial3D).normal_enabled = false

    # Chimney material (simple)
    var chimney_mat := StandardMaterial3D.new()
    chimney_mat.vertex_color_use_as_albedo = true
    chimney_mat.roughness = 0.95
    chimney_mat.metallic = 0.0

    # Palettes
    var wall_palette := [
        Color(0.86, 0.84, 0.78),
        Color(0.88, 0.84, 0.66),
        Color(0.78, 0.84, 0.88),
        Color(0.80, 0.78, 0.74),
        Color(0.66, 0.68, 0.70),
        Color(0.74, 0.78, 0.72)
    ]
    var roof_palette := [
        Color(0.42, 0.18, 0.12),
        Color(0.30, 0.16, 0.10),
        Color(0.24, 0.20, 0.18),
        Color(0.34, 0.22, 0.18)
    ]
    var stone_palette := [
        Color(0.62, 0.64, 0.66),
        Color(0.56, 0.58, 0.60),
        Color(0.68, 0.66, 0.62)
    ]

    var pool: Array = _get_settlement_variants(style, lod_level)

    var want: int = int(Game.settings.get("settlement_variants_near", 12))
    if lod_level == 1:
        want = int(Game.settings.get("settlement_variants_mid", 6))
    elif lod_level == 2:
        want = int(Game.settings.get("settlement_variants_far", 2))
    want = clampi(want, 1, max(1, pool.size()))

    var idxs: Array = []
    for i in range(pool.size()):
        idxs.append(i)
    var subset_idxs: Array = _pick_subset(rng, idxs, want)
    var variants: Array = []
    for ii in subset_idxs:
        variants.append(pool[int(ii)])

    # Buckets: per-variant transforms & colors
    var wall_xf := []
    var wall_col := []
    var roof_xf := []
    var roof_col := []
    var chim_xf := []
    var chim_col := []

    # Store as variant_i -> arrays
    var bucket: Dictionary = {}
    for i in range(variants.size()):
        bucket[i] = {
            "wxf": [], "wcol": [],
            "rxf": [], "rcol": [],
            "cxf": [], "ccol": []
        }

    for b in buildings:
        if not (b is Dictionary):
            continue
        var bd := b as Dictionary

        var x: float = float(bd.get("x", center.x))
        var z: float = float(bd.get("z", center.z))
        var y: float = float(bd.get("y", Game.sea_level))
        var sx: float = float(bd.get("sx", 12.0))
        var sz: float = float(bd.get("sz", 12.0))
        var sy: float = float(bd.get("sy", 10.0))
        var rot: float = float(bd.get("rot", 0.0))

        var vi: int = _weighted_pick(rng, variants)
        var v := variants[vi] as Dictionary

        if String(v.get("kind", "proc")) == "ext":
            # External mesh: keep transforms conservative.
            var mesh: Mesh = v.get("mesh", null)
            if mesh == null:
                continue
            var s: float = clamp((sx + sz) * 0.035, 0.55, 1.65)
            var bb := Basis.IDENTITY
            bb = bb.rotated(Vector3.UP, rot)
            bb = bb.scaled(Vector3(s, s, s))
            (bucket[vi]["wxf"] as Array).append(Transform3D(bb, Vector3(x, y + s * 0.5, z)))
            # No per-instance colors for external (use embedded materials)
            (bucket[vi]["wcol"] as Array).append(Color(1, 1, 1, 1))
            continue

        # Check if we should use parametric building system
        if _enable_parametric_buildings and rng.randf() < 0.3:  # 30% parametric
            _add_parametric_building(parent, x, y, z, sx, sz, sy, rot, style, lod_level, rng)
            continue

        # Procedural
        var sx_mul: float = float(v.get("sx_mul", 1.0))
        var sz_mul: float = float(v.get("sz_mul", 1.0))
        var sy_mul: float = float(v.get("sy_mul", 1.0))
        var force_square: bool = bool(v.get("force_square", false))

        var sx2: float = sx * sx_mul
        var sz2: float = sz * sz_mul
        var sy2: float = sy * sy_mul
        if force_square:
            var s2: float = min(sx2, sz2)
            sx2 = s2
            sz2 = s2

        var wall_mesh: Mesh = v.get("wall_mesh", _mesh_unit_box)
        var roof_mesh: Mesh = v.get("roof_mesh", null)
        var roof_kind: String = String(v.get("roof_kind", "none"))

        # Wall transform
        var wb := Basis.IDENTITY
        wb = wb.rotated(Vector3.UP, rot)
        wb = wb.scaled(Vector3(sx2, sy2, sz2))
        (bucket[vi]["wxf"] as Array).append(Transform3D(wb, Vector3(x, y + sy2 * 0.5, z)))

        var wp: Array = wall_palette
        if wall_mesh == _mesh_unit_cyl:
            wp = stone_palette
        var wcol: Color = _palette_pick(rng, wp)
        wcol = wcol.lerp(base_col, 0.25)
        wcol.r += rng.randf_range(-0.05, 0.05)
        wcol.g += rng.randf_range(-0.05, 0.05)
        wcol.b += rng.randf_range(-0.05, 0.05)
        (bucket[vi]["wcol"] as Array).append(wcol.clamp())

        # Roof
        if roof_mesh != null:
            var rcol: Color = _palette_pick(rng, roof_palette)
            rcol.r += rng.randf_range(-0.04, 0.04)
            rcol.g += rng.randf_range(-0.03, 0.03)
            rcol.b += rng.randf_range(-0.03, 0.03)
            rcol = rcol.clamp()

            if roof_kind == "flat":
                var flat_h: float = clamp(min(sx2, sz2) * rng.randf_range(0.08, 0.14), 1.8, 5.2)
                var rb := Basis.IDENTITY
                rb = rb.rotated(Vector3.UP, rot)
                rb = rb.scaled(Vector3(sx2 * 1.03, flat_h, sz2 * 1.03))
                (bucket[vi]["rxf"] as Array).append(Transform3D(rb, Vector3(x, y + sy2 + flat_h * 0.5, z)))
                (bucket[vi]["rcol"] as Array).append(rcol)
            elif roof_kind == "shed":
                # Simple single-slope roof (good for warehouses).
                var shed_h: float = clamp(min(sx2, sz2) * rng.randf_range(0.10, 0.18), 2.2, 6.5)
                var rbS := Basis.IDENTITY
                rbS = rbS.rotated(Vector3.UP, rot)
                rbS = rbS.rotated(Vector3.BACK, rng.randf_range(0.18, 0.32))
                rbS = rbS.scaled(Vector3(sx2 * 1.05, shed_h, sz2 * 1.05))
                (bucket[vi]["rxf"] as Array).append(Transform3D(rbS, Vector3(x, y + sy2 + shed_h * 0.5, z)))
                (bucket[vi]["rcol"] as Array).append(rcol)
            elif roof_kind == "cone":
                var cone_h: float = clamp(min(sx2, sz2) * rng.randf_range(0.40, 0.75), 4.0, 16.0)
                var rb3 := Basis.IDENTITY
                rb3 = rb3.rotated(Vector3.UP, rot)
                rb3 = rb3.scaled(Vector3(sx2 * 0.95, cone_h, sz2 * 0.95))
                (bucket[vi]["rxf"] as Array).append(Transform3D(rb3, Vector3(x, y + sy2 + cone_h * 0.5, z)))
                (bucket[vi]["rcol"] as Array).append(rcol)
            else:
                # gable / hip share ArrayMesh base-at-0, apex-at-0.5 convention
                var roof_h: float = clamp(min(sx2, sz2) * rng.randf_range(0.18, 0.34), 2.8, 11.5)
                var rb2 := Basis.IDENTITY
                rb2 = rb2.rotated(Vector3.UP, rot)
                rb2 = rb2.scaled(Vector3(sx2 * 1.08, roof_h * 2.0, sz2 * 1.08))
                (bucket[vi]["rxf"] as Array).append(Transform3D(rb2, Vector3(x, y + sy2, z)))
                (bucket[vi]["rcol"] as Array).append(rcol)

        # Chimneys removed for Test 1 - eliminating grid pattern white squares
        # var ch_p: float = float(v.get("chimney_prob", 0.0))
        # if lod_level == 0 and ch_p > 0.0 and rng.randf() < ch_p:
        #     var cx: float = x + rng.randf_range(-sx2 * 0.25, sx2 * 0.25)
        #     var cz: float = z + rng.randf_range(-sz2 * 0.25, sz2 * 0.25)
        #     var ch_h: float = clamp(sy2 * 0.18, 2.0, 6.5)
        #     var cb := Basis.IDENTITY
        #     cb = cb.rotated(Vector3.UP, rot)
        #     cb = cb.scaled(Vector3(0.9, ch_h, 0.9))
        #     (bucket[vi]["cxf"] as Array).append(Transform3D(cb, Vector3(cx, y + sy2 + ch_h * 0.5, cz)))
        #     var ccol: Color = Color(0.20, 0.18, 0.17).lerp(wcol, 0.15)
        #     (bucket[vi]["ccol"] as Array).append(ccol)

    # Emit MultiMeshes per chosen variant
    for i in range(variants.size()):
        var v := variants[i] as Dictionary
        var kind: String = String(v.get("kind", "proc"))
        var name: String = String(v.get("name", "v"))
        var b: Dictionary = bucket[i]

        if kind == "ext":
            # TEST 2: External mesh system completely disabled
            # This eliminates white squares from external asset processing
            continue
        
        var wall_mesh: Mesh = v.get("wall_mesh", _mesh_unit_box)
        _mm_batch(parent, "BldWalls_%s" % name, wall_mesh, wall_mat, b["wxf"], b["wcol"])

        var roof_mesh: Mesh = v.get("roof_mesh", null)
        if roof_mesh != null:
            _mm_batch(parent, "BldRoof_%s" % name, roof_mesh, roof_mat, b["rxf"], b["rcol"])

        if lod_level == 0:
            _mm_batch(parent, "BldChim_%s" % name, _mesh_chimney, chimney_mat, b["cxf"], b["ccol"])
            
            # Add architectural details if building has them
            _emit_building_details(parent, v, b, kit, rng, lod_level)


func _emit_building_details(parent: Node3D, variant: Dictionary, bucket: Dictionary, kit: Dictionary, rng: RandomNumberGenerator, lod_level: int) -> void:
    """Emit windows, doors, trim, and damage for a building variant."""
    
    var name: String = String(variant.get("name", "v"))
    var has_windows: bool = bool(variant.get("has_windows", false))
    var has_doors: bool = bool(variant.get("has_doors", false))
    var has_trim: bool = bool(variant.get("has_trim", false))
    
    # Only emit details for near LOD (level 0)
    if lod_level != 0:
        return
    
    # Get detail meshes and materials from kit
    var window_mesh: Mesh = kit.get("window_mesh", null)
    var door_mesh: Mesh = kit.get("door_mesh", null)
    var trim_mesh: Mesh = kit.get("trim_mesh", null)
    var damage_mesh: Mesh = kit.get("damage_mesh", null)
    
    var window_mat: Material = kit.get("window_material", null)
    var door_mat: Material = kit.get("door_material", null)
    var trim_mat: Material = kit.get("trim_material", null)
    var damage_mat: Material = kit.get("damage_material", null)
    
    var wall_xforms: Array = bucket["wxf"] as Array
    var wall_colors: Array = bucket["wcol"] as Array
    
    if wall_xforms.is_empty():
        return
    
    # Emit windows
    if window_mesh != null and window_mat != null:
        var window_xforms := []
        var window_colors := []
        for wall_xform in wall_xforms:
            # Add windows to this wall (simplified - add 2-3 windows per wall)
            var window_count := 2
            for i in range(window_count):
                var window_xform := Transform3D(wall_xform)
                window_xform.origin.x += (float(i) - 0.5) * 2.0
                window_xform.origin.y += 1.5
                window_xforms.append(window_xform)
                window_colors.append(Color.WHITE)

        if window_xforms.size() > 0:
            _mm_batch(parent, "BldWin_%s" % name, window_mesh, window_mat, window_xforms, window_colors)

    # Emit doors
    if door_mesh != null and door_mat != null:
        var door_xforms := []
        var door_colors := []
        for wall_xform in wall_xforms:
            # Add one door to first wall
            if door_xforms.is_empty():
                door_xforms.append(wall_xform)
                door_colors.append(Color.WHITE)
                break

        if door_xforms.size() > 0:
            _mm_batch(parent, "BldDoor_%s" % name, door_mesh, door_mat, door_xforms, door_colors)

    # Emit trim
    if trim_mesh != null and trim_mat != null:
        var trim_xforms := []
        var trim_colors := []
        for wall_xform in wall_xforms:
            var trim_xform := Transform3D(wall_xform)
            trim_xform.origin.y += 3.0  # At top of building
            trim_xforms.append(trim_xform)
            trim_colors.append(Color.WHITE)

        if trim_xforms.size() > 0:
            _mm_batch(parent, "BldTrim_%s" % name, trim_mesh, trim_mat, trim_xforms, trim_colors)

    # Emit damage/weathering (WW2 era appropriate)
    var damage_prob: float = float(kit.get("damage_probability", 0.0))
    if damage_prob > 0.0 and damage_mesh != null and damage_mat != null and rng.randf() < damage_prob:
        var damage_xforms := []
        var damage_colors := []
        
        for i in range(wall_xforms.size()):
            if rng.randf() < 0.3:  # 30% chance per building to have damage
                var wall_xform := wall_xforms[i] as Transform3D
                
                # Add multiple damage decals
                var damage_count: int = rng.randi_range(1, 4)
                for d in range(damage_count):
                    var damage_xform: Transform3D = _calculate_damage_position(wall_xform, rng)
                    damage_xforms.append(damage_xform)
                    damage_colors.append(Color(1, 1, 1, 0.8))
        
        if damage_xforms.size() > 0:
            _mm_batch(parent, "BldDmg_%s" % name, damage_mesh, damage_mat, damage_xforms, damage_colors)


func _calculate_window_position(wall_xform: Transform3D, side: String, window_index: int, floor: int, 
                               window_spacing: float, window_width: float, window_height: float, 
                               window_depth: float, building_width: float, building_height: float) -> Transform3D:
    """Calculate transform for a window on a building wall."""
    
    var basis: Basis = wall_xform.basis
    var origin: Vector3 = wall_xform.origin
    
    # Calculate window position based on side
    var window_x: float = 0.0
    var window_y: float = -building_height * 0.5 + 1.0 + float(floor) * 3.0 + window_height * 0.5
    var window_z: float = 0.0
    
    if side == "front":
        window_x = -building_width * 0.5 + window_width * 0.5 + float(window_index) * window_spacing
        window_z = -building_width * 0.5 - window_depth * 0.5
    elif side == "back":
        window_x = building_width * 0.5 - window_width * 0.5 - float(window_index) * window_spacing
        window_z = building_width * 0.5 + window_depth * 0.5
    elif side == "left":
        window_x = -building_width * 0.5 - window_depth * 0.5
        window_z = -building_width * 0.5 + window_width * 0.5 + float(window_index) * window_spacing
    elif side == "right":
        window_x = building_width * 0.5 + window_depth * 0.5
        window_z = building_width * 0.5 - window_width * 0.5 - float(window_index) * window_spacing
    
    # Create window basis (facing outward)
    var window_basis: Basis = Basis.IDENTITY
    window_basis = window_basis.scaled(Vector3(window_width, window_height, window_depth))
    
    # Combine with wall transform
    var window_pos: Vector3 = origin + basis.x * window_x + basis.y * window_y + basis.z * window_z
    return Transform3D(window_basis, window_pos)


func _calculate_door_position(wall_xform: Transform3D, door_width: float, door_height: float, 
                             door_depth: float, building_width: float, building_height: float) -> Transform3D:
    """Calculate transform for a door on a building wall."""
    
    var basis: Basis = wall_xform.basis
    var origin: Vector3 = wall_xform.origin
    
    # Position door at center of front face, slightly above ground
    var door_x: float = 0.0
    var door_y: float = -building_height * 0.5 + door_height * 0.5 + 0.1
    var door_z: float = -building_width * 0.5 - door_depth * 0.5
    
    # Create door basis
    var door_basis: Basis = Basis.IDENTITY
    door_basis = door_basis.scaled(Vector3(door_width, door_height, door_depth))
    
    # Combine with wall transform
    var door_pos: Vector3 = origin + basis.x * door_x + basis.y * door_y + basis.z * door_z
    return Transform3D(door_basis, door_pos)


func _calculate_trim_position(wall_xform: Transform3D, segment: int, total_segments: int, 
                             building_width: float, building_depth: float, building_height: float) -> Transform3D:
    """Calculate transform for a trim segment around a building."""
    
    var basis: Basis = wall_xform.basis
    var origin: Vector3 = wall_xform.origin
    
    # Calculate position around the perimeter
    var perimeter: float = (building_width + building_depth) * 2
    var segment_length: float = perimeter / float(total_segments)
    var position: float = float(segment) * segment_length
    
    var x: float = 0.0
    var y: float = building_height * 0.5 - 0.05  # Just below roof
    var z: float = 0.0
    
    # Position along perimeter
    if position < building_width:  # Front
        x = -building_width * 0.5 + position + segment_length * 0.5
        z = -building_width * 0.5
    elif position < building_width + building_depth:  # Right
        var pos_along: float = position - building_width
        x = building_width * 0.5
        z = -building_width * 0.5 + pos_along + segment_length * 0.5
    elif position < 2 * building_width + building_depth:  # Back
        var pos_along: float = position - building_width - building_depth
        x = building_width * 0.5 - pos_along - segment_length * 0.5
        z = building_width * 0.5
    else:  # Left
        var pos_along: float = position - 2 * building_width - building_depth
        x = -building_width * 0.5
        z = building_width * 0.5 - pos_along - segment_length * 0.5
    
    # Create trim basis (1m segment, rotated to follow wall)
    var trim_basis: Basis = Basis.IDENTITY
    
    # Rotate trim to follow wall direction
    if position < building_width:  # Front - along X
        trim_basis = trim_basis.rotated(Vector3.UP, 0.0)
    elif position < building_width + building_depth:  # Right - along Z
        trim_basis = trim_basis.rotated(Vector3.UP, PI * 0.5)
    elif position < 2 * building_width + building_depth:  # Back - along -X
        trim_basis = trim_basis.rotated(Vector3.UP, PI)
    else:  # Left - along -Z
        trim_basis = trim_basis.rotated(Vector3.UP, PI * 1.5)
    
    trim_basis = trim_basis.scaled(Vector3(1.0, 0.2, 0.1))  # 1m long, 20cm tall, 10cm deep
    
    # Combine with wall transform
    var trim_pos: Vector3 = origin + basis.x * x + basis.y * y + basis.z * z
    return Transform3D(trim_basis, trim_pos)


func _calculate_damage_position(wall_xform: Transform3D, rng: RandomNumberGenerator) -> Transform3D:
    """Calculate random position for damage decal on a wall."""
    
    var basis: Basis = wall_xform.basis
    var origin: Vector3 = wall_xform.origin
    var scale: Vector3 = wall_xform.basis.get_scale()
    
    var building_width: float = scale.x
    var building_height: float = scale.y
    
    # Random position on wall
    var x: float = rng.randf_range(-building_width * 0.4, building_width * 0.4)
    var y: float = rng.randf_range(-building_height * 0.4, building_height * 0.3)
    var z: float = -building_width * 0.5 - 0.01  # Slightly in front of wall
    
    # Random rotation
    var rot_y: float = rng.randf_range(-0.2, 0.2)
    var damage_basis: Basis = Basis.IDENTITY
    damage_basis = damage_basis.rotated(Vector3.UP, rot_y)
    
    # Random scale variation
    var damage_scale: float = rng.randf_range(0.8, 1.5)
    damage_basis = damage_basis.scaled(Vector3(damage_scale, damage_scale, 1.0))
    
    # Combine with wall transform
    var damage_pos: Vector3 = origin + basis.x * x + basis.y * y + basis.z * z
    return Transform3D(damage_basis, damage_pos)


func _emit_settlement_roads(parent: Node3D, roads: Array, style: String) -> void:
    # Cheap visible street network: a single combined mesh per settlement LOD.
    if roads.is_empty():
        return

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for r in roads:
        if not (r is Dictionary):
            continue
        var rd := r as Dictionary
        var a2: Vector2 = rd.get("a", Vector2.ZERO)
        var b2: Vector2 = rd.get("b", Vector2.ZERO)
        var w: float = float(rd.get("w", 8.0))

        var dir: Vector2 = (b2 - a2)
        var len: float = dir.length()
        if len < 0.1:
            continue
        dir /= len
        var n: Vector2 = Vector2(-dir.y, dir.x)

        # Build a simple quad strip (two triangles).
        var p0 := Vector3(a2.x + n.x * w, 0.0, a2.y + n.y * w)
        var p1 := Vector3(a2.x - n.x * w, 0.0, a2.y - n.y * w)
        var p2 := Vector3(b2.x - n.x * w, 0.0, b2.y - n.y * w)
        var p3 := Vector3(b2.x + n.x * w, 0.0, b2.y + n.y * w)

        # Small lift to avoid Z-fighting with terrain.
        p0.y = _ground_height(p0.x, p0.z) + 0.06
        p1.y = _ground_height(p1.x, p1.z) + 0.06
        p2.y = _ground_height(p2.x, p2.z) + 0.06
        p3.y = _ground_height(p3.x, p3.z) + 0.06

        st.set_normal(Vector3.UP)
        st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
        st.add_vertex(p2); st.add_vertex(p3); st.add_vertex(p0)

    var mesh := st.commit()
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.name = "SettlementRoads"

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.09, 0.09, 0.10)
    mat.roughness = 0.95
    mat.metallic = 0.0

    # Slight style variations.
    if style == "city":
        mat.albedo_color = Color(0.10, 0.10, 0.11)
    elif style == "hamlet":
        mat.albedo_color = Color(0.11, 0.10, 0.09)

    mi.material_override = mat
    parent.add_child(mi)


func _settlement_build_roads(center: Vector3, style: String, radius: float, rng: RandomNumberGenerator) -> Array:
    # Returns Array[Dictionary] with {a:Vector2, b:Vector2, w:float} in XZ plane.
    var roads: Array = []

    var ang: float = rng.randf_range(0.0, TAU)
    var ux := Vector2(cos(ang), sin(ang))
    var uz := Vector2(-ux.y, ux.x)

    if style == "city":
        var extent: float = radius * 0.95
        var block: float = clamp(radius * 0.11, 55.0, 95.0)
        var lanes: float = 10.0

        # A coarse rotated grid, plus two stronger avenues.
        for k in range(-4, 5):
            var off: Vector2 = uz * (float(k) * block)
            var a := Vector2(center.x, center.z) + off - ux * extent
            var b := Vector2(center.x, center.z) + off + ux * extent
            roads.append({"a": a, "b": b, "w": lanes})

        for k2 in range(-4, 5):
            var off2: Vector2 = ux * (float(k2) * block)
            var a2 := Vector2(center.x, center.z) + off2 - uz * extent
            var b2 := Vector2(center.x, center.z) + off2 + uz * extent
            roads.append({"a": a2, "b": b2, "w": lanes})

        # Main avenues (wider).
        roads.append({"a": Vector2(center.x, center.z) - ux * extent, "b": Vector2(center.x, center.z) + ux * extent, "w": 14.0})
        roads.append({"a": Vector2(center.x, center.z) - uz * extent, "b": Vector2(center.x, center.z) + uz * extent, "w": 14.0})

    elif style == "town":
        var extent2: float = radius * 1.05
        var w2: float = 9.0
        roads.append({"a": Vector2(center.x, center.z) - ux * extent2, "b": Vector2(center.x, center.z) + ux * extent2, "w": w2})
        roads.append({"a": Vector2(center.x, center.z) - uz * (extent2 * 0.75), "b": Vector2(center.x, center.z) + uz * (extent2 * 0.75), "w": w2 * 0.92})

        # A few diagonals.
        if rng.randf() < 0.6:
            var d := (ux + uz).normalized()
            roads.append({"a": Vector2(center.x, center.z) - d * (extent2 * 0.8), "b": Vector2(center.x, center.z) + d * (extent2 * 0.8), "w": 7.5})

    else:
        var extent3: float = radius * 0.95
        roads.append({"a": Vector2(center.x, center.z) - ux * extent3, "b": Vector2(center.x, center.z) + ux * extent3, "w": 6.5})

        if rng.randf() < 0.45:
            roads.append({"a": Vector2(center.x, center.z) - uz * (extent3 * 0.55), "b": Vector2(center.x, center.z) + uz * (extent3 * 0.55), "w": 5.8})

    return roads


func _settlement_fill_buildings_along_roads(buildings: Array, roads: Array, center: Vector3, style: String, count: int, radius: float, hmin: float, hmax: float, rng: RandomNumberGenerator) -> void:
    # Places buildings along both sides of the road network. Writes dictionaries into `buildings`.
    if roads.is_empty() or count <= 0:
        return

    var spacing: float = 22.0
    var setback: float = 16.0
    var lot_w_min: float = 10.0
    var lot_w_max: float = 22.0
    var lot_d_min: float = 10.0
    var lot_d_max: float = 24.0  # Fixed syntax

    if style == "city":
        spacing = 30.0
        setback = 18.0
        lot_w_min = 10.0
        lot_w_max = 28.0
        lot_d_min = 10.0
        lot_d_max = 28.0
    elif style == "hamlet":
        spacing = 16.0
        setback = 12.0
        lot_w_min = 10.0
        lot_w_max = 18.0
        lot_d_min = 10.0
        lot_d_max = 18.0

    # Occupancy hash to avoid overlaps.
    var occ: Dictionary = {}
    var occ_cell: float = 14.0 if style != "city" else 18.0

    # Keep a plaza/open core in city/town.
    var plaza_r: float = 0.0
    if style == "city":
        plaza_r = clamp(radius * 0.12, 85.0, 165.0)
    elif style == "town":
        plaza_r = clamp(radius * 0.10, 55.0, 120.0)

    # Iterate roads; offset placements per-road so patterns don’t line up.
    for r in roads:
        if buildings.size() >= count:
            break
        var a2: Vector2 = (r as Dictionary).get("a", Vector2.ZERO)
        var b2: Vector2 = (r as Dictionary).get("b", Vector2.ZERO)
        var w: float = float((r as Dictionary).get("w", 8.0))
        var dir: Vector2 = (b2 - a2)
        var len: float = dir.length()
        if len < 10.0:
            continue
        dir /= len
        var n: Vector2 = Vector2(-dir.y, dir.x)

        var t0: float = rng.randf_range(0.0, spacing)
        var t: float = t0
        while t < len and buildings.size() < count:
            # Alternate sides; add a few on each pass.
            for side in [-1, 1]:
                if buildings.size() >= count:
                    break
                var off: float = (setback + w) * float(side) + rng.randf_range(-3.0, 3.0)
                var p2: Vector2 = a2 + dir * t + n * off

                # Bound inside settlement circle.
                var rel: Vector2 = p2 - Vector2(center.x, center.z)
                if rel.length() > radius * 0.98:
                    continue
                if plaza_r > 0.0 and rel.length() < plaza_r:
                    continue

                var x: float = p2.x + rng.randf_range(-2.0, 2.0)
                var z: float = p2.y + rng.randf_range(-2.0, 2.0)
                var y: float = _ground_height(x, z)
                if y < Game.sea_level + 1.5:
                    continue
                if _slope_at(x, z) > (0.92 if style == "city" else 0.78):
                    continue

                var k: int = _occ_key(x, z, occ_cell)
                if occ.has(k):
                    continue

                var sx: float = rng.randf_range(lot_w_min, lot_w_max)
                var sz: float = rng.randf_range(lot_d_min, lot_d_max)
                var sy: float = rng.randf_range(hmin, hmax)

                # Slightly taller near core.
                var core: float = 1.0 - clamp(rel.length() / maxf(1.0, radius), 0.0, 1.0)
                core = pow(core, 1.4)
                if style == "city":
                    sy *= lerp(0.85, 1.35, core)
                else:
                    sy *= lerp(0.80, 1.15, core)

                var rot: float = atan2(dir.y, dir.x)
                # Face toward road.
                rot += (PI * 0.5) if side == -1 else (-PI * 0.5)
                rot += rng.randf_range(-0.08, 0.08)

                buildings.append({"x": x, "z": z, "y": y, "sx": sx, "sz": sz, "sy": sy, "rot": rot})
                occ[k] = true

            t += spacing


func _build_settlement(parent: Node3D, center: Vector3, count: int, radius: float, hmin: float, hmax: float, base_col: Color) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = int(Game.settings.get("world_seed", 0)) + int(absf(center.x + center.z) * 0.25)

    var style: String = "hamlet"
    if count >= 800:
        style = "city"
    elif count >= 180:
        style = "town"

    # Layout: road-aligned lots first (so towns read like towns), then fill any remaining with scatter.
    var buildings: Array = []
    var roads: Array = _settlement_build_roads(center, style, radius, rng)
    _settlement_fill_buildings_along_roads(buildings, roads, center, style, count, radius, hmin, hmax, rng)

    # If we didn't hit our target count (e.g., hilly coast), scatter-fill the remainder.
    if buildings.size() < count:
        var cell: float = 24.0
        if style == "city":
            cell = 34.0
        elif style == "town":
            cell = 26.0
        else:
            cell = 18.0

        var tries: int = 0
        var max_tries: int = count * 8
        while buildings.size() < count and tries < max_tries:
            tries += 1
            var ang: float = rng.randf_range(0.0, TAU)
            var rr: float = radius * sqrt(rng.randf())
            # Keep the very center a bit more open in towns/cities.
            if style != "hamlet" and rr < radius * 0.08 and rng.randf() < 0.85:
                continue

            var lx: float = cos(ang) * rr
            var lz: float = sin(ang) * rr
            if style != "hamlet":
                lx = round(lx / cell) * cell + rng.randf_range(-cell * 0.22, cell * 0.22)
                lz = round(lz / cell) * cell + rng.randf_range(-cell * 0.22, cell * 0.22)

            var x: float = center.x + lx
            var z: float = center.z + lz
            var y: float = _ground_height(x, z)
            if y < Game.sea_level + 1.5:
                continue
            if _slope_at(x, z) > (0.92 if style == "city" else 0.78):
                continue

            # Basic de-overlap (cheap): keep away from the last few.
            var ok: bool = true
            for j in range(max(0, buildings.size() - 22), buildings.size()):
                var bdj := buildings[j] as Dictionary
                var dx: float = x - float(bdj.get("x", x))
                var dz: float = z - float(bdj.get("z", z))
                if dx * dx + dz * dz < 14.0 * 14.0:
                    ok = false
                    break
            if not ok:
                continue

            var core: float = 1.0 - clamp(rr / maxf(1.0, radius), 0.0, 1.0)
            core = pow(core, 1.6)

            var sx: float = rng.randf_range(9.0, 22.0)
            var sz: float = rng.randf_range(9.0, 22.0)
            if style == "city":
                sx = rng.randf_range(10.0, 26.0)
                sz = rng.randf_range(10.0, 26.0)
            elif style == "hamlet":
                sx = rng.randf_range(10.0, 18.0)
                sz = rng.randf_range(10.0, 18.0)

            var sy: float = rng.randf_range(hmin, hmax)
            if style != "city":
                sy *= lerp(0.75, 1.10, core)
            else:
                sy *= lerp(0.70, 1.35, core)

            var rot: float = rng.randf_range(0.0, TAU)
            if style != "hamlet":
                var q: float = PI * 0.5
                rot = round(rot / q) * q + rng.randf_range(-0.10, 0.10)

            buildings.append({"x": x, "z": z, "y": y, "sx": sx, "sz": sz, "sy": sy, "rot": rot})

    # LOD nodes
    var lod_root := Node3D.new()
    lod_root.name = "Settlement_%s" % style
    parent.add_child(lod_root)

    var lod0 := Node3D.new(); lod0.name = "LOD0"; lod_root.add_child(lod0)
    var lod1 := Node3D.new(); lod1.name = "LOD1"; lod_root.add_child(lod1)
    var lod2 := Node3D.new(); lod2.name = "LOD2"; lod_root.add_child(lod2)

    # Roads: visible in near+mid rings (far ring skips for speed).
    _emit_settlement_roads(lod0, roads, style)
    _emit_settlement_roads(lod1, roads, style)

    _emit_settlement_buildings(lod0, buildings, center, style, 0, base_col)
    _emit_settlement_buildings(lod1, buildings, center, style, 1, base_col)
    _emit_settlement_buildings(lod2, buildings, center, style, 2, base_col)

    lod0.visible = true
    lod1.visible = false
    lod2.visible = false

    _prop_lod_groups.append({"center": center, "lod": -1, "lod0": lod0, "lod1": lod1, "lod2": lod2})

    return {"center": center, "radius": radius, "lod_root": lod_root}

func _build_fields(parent: Node3D, rng: RandomNumberGenerator, count: int) -> void:
    # Farm fields as color-varied plane patches (MultiMesh).
    if count <= 0:
        return

    var mesh := PlaneMesh.new()
    mesh.size = Vector2(1.0, 1.0)

    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.albedo_color = Color(1, 1, 1)
    mat.roughness = 1.0

    var mmi := MultiMeshInstance3D.new()
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.mesh = mesh
    mm.instance_count = count
    mmi.multimesh = mm
    mmi.material_override = mat
    parent.add_child(mmi)

    var half: float = _terrain_size * 0.5

    for i in range(count):
        var x: float = rng.randf_range(-half * 0.82, half * 0.82)
        var z: float = rng.randf_range(-half * 0.82, half * 0.82)
        var y: float = _ground_height(x, z)

        if y < Game.sea_level + 1.0:
            mm.set_instance_transform(i, _hide_xform)
            mm.set_instance_color(i, Color(0, 0, 0, 0))
            continue

        if Vector2(x, z).length() < 520.0:
            mm.set_instance_transform(i, _hide_xform)
            mm.set_instance_color(i, Color(0, 0, 0, 0))
            continue

        if _slope_at(x, z) > 0.55:
            mm.set_instance_transform(i, _hide_xform)
            mm.set_instance_color(i, Color(0, 0, 0, 0))
            continue

        # Avoid settlements core.
        if _too_close_to_settlements(Vector3(x, y, z), 260.0):
            mm.set_instance_transform(i, _hide_xform)
            mm.set_instance_color(i, Color(0, 0, 0, 0))
            continue

        var sx: float = rng.randf_range(240.0, 700.0)
        var sz: float = rng.randf_range(240.0, 700.0)

        var basis := Basis()
        basis = basis.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
        basis = basis.scaled(Vector3(sx, 1.0, sz))

        var t := Transform3D(basis, Vector3(x, y + 0.06, z))
        mm.set_instance_transform(i, t)

        # Wheat/grass/tilled mixes.
        var c := Color(
            0.20 + rng.randf() * 0.18,
            0.24 + rng.randf() * 0.32,
            0.12 + rng.randf() * 0.14,
            1.0
        )
        if rng.randf() < 0.35:
            c = Color(0.30 + rng.randf() * 0.20, 0.24 + rng.randf() * 0.10, 0.12 + rng.randf() * 0.08, 1.0)
        mm.set_instance_color(i, c)


func _build_ponds(parent: Node3D, count: int, rng: RandomNumberGenerator) -> void:
    if count <= 0:
        return

    var water_mat := StandardMaterial3D.new()
    water_mat.albedo_color = Color(0.05, 0.12, 0.17, 0.75)
    water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    water_mat.roughness = 0.15
    water_mat.metallic = 0.0

    for _i in range(count):
        var x: float = rng.randf_range(-_terrain_size * 0.45, _terrain_size * 0.45)
        var z: float = rng.randf_range(-_terrain_size * 0.45, _terrain_size * 0.45)
        var y: float = _ground_height(x, z)

        if y < Game.sea_level + 2.0:
            continue
        if Vector2(x, z).length() < 520.0:
            continue
        if _slope_at(x, z) > 0.55:
            continue

        if y > 120.0 and rng.randf() < 0.65:
            continue

        var r: float = rng.randf_range(55.0, 160.0)

        var pond := MeshInstance3D.new()
        var mesh := CylinderMesh.new()
        mesh.top_radius = r
        mesh.bottom_radius = r
        mesh.height = 0.15
        pond.mesh = mesh
        pond.material_override = water_mat
        pond.position = Vector3(x, y + 0.05, z)
        pond.rotation_degrees = Vector3(90.0, 0.0, 0.0)
        parent.add_child(pond)


func _build_farm_barns(parent: Node3D, count: int, rng: RandomNumberGenerator) -> void:
    if count <= 0:
        return

    var wall_mat := StandardMaterial3D.new()
    wall_mat.albedo_color = Color(0.45, 0.18, 0.16)
    wall_mat.roughness = 0.95
    wall_mat.metallic = 0.0

    var roof_mat := StandardMaterial3D.new()
    roof_mat.albedo_color = Color(0.18, 0.10, 0.10)
    roof_mat.roughness = 0.90
    roof_mat.metallic = 0.02

    var half: float = _terrain_size * 0.5

    for _i in range(count):
        var x: float = rng.randf_range(-half * 0.70, half * 0.70)
        var z: float = rng.randf_range(-half * 0.70, half * 0.70)
        var y: float = _ground_height(x, z)

        if y < Game.sea_level + 2.0:
            continue
        if Vector2(x, z).length() < 520.0:
            continue
        if _slope_at(x, z) > 0.55:
            continue
        if _too_close_to_settlements(Vector3(x, y, z), 220.0):
            continue

        var barn := Node3D.new()
        barn.position = Vector3(x, y + 0.05, z)
        barn.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
        parent.add_child(barn)

        var body := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(rng.randf_range(22.0, 42.0), rng.randf_range(10.0, 18.0), rng.randf_range(26.0, 55.0))
        body.mesh = bm
        body.material_override = wall_mat
        body.position = Vector3(0.0, bm.size.y * 0.5, 0.0)
        barn.add_child(body)

        var roof := MeshInstance3D.new()
        var rm := BoxMesh.new()
        rm.size = Vector3(bm.size.x * 1.08, bm.size.y * 0.55, bm.size.z * 1.05)
        roof.mesh = rm
        roof.material_override = roof_mat
        roof.position = Vector3(0.0, bm.size.y + rm.size.y * 0.35, 0.0)
        roof.rotation_degrees = Vector3(0.0, 0.0, 12.0)
        barn.add_child(roof)


func _build_industry(parent: Node3D, count: int, rng: RandomNumberGenerator) -> void:
    if count <= 0:
        return

    var root := Node3D.new()
    root.name = "Industry"
    parent.add_child(root)

    # Load industrial textures if available
    var use_textures: bool = false
    var industrial_textures: Dictionary = {}
    if _assets != null and _assets.enabled():
        industrial_textures = _assets.get_texture_set("building_atlas_industrial")
        use_textures = industrial_textures.size() > 0

    var fac_mat := StandardMaterial3D.new()
    fac_mat.albedo_color = Color(0.22, 0.22, 0.23)
    fac_mat.roughness = 0.95
    fac_mat.metallic = 0.05  # Slight metallic for industrial feel

    # Apply industrial textures
    if use_textures:
        if industrial_textures.has("albedo"):
            fac_mat.albedo_texture = industrial_textures["albedo"]
        if industrial_textures.has("normal"):
            fac_mat.normal_enabled = true
            fac_mat.normal_texture = industrial_textures["normal"]
        if industrial_textures.has("roughness"):
            fac_mat.roughness_texture = industrial_textures["roughness"]
        if industrial_textures.has("metallic"):
            fac_mat.metallic_texture = industrial_textures["metallic"]

    var stack_mat := StandardMaterial3D.new()
    stack_mat.albedo_color = Color(0.18, 0.18, 0.19)
    stack_mat.roughness = 0.98
    stack_mat.metallic = 0.1

    var half: float = _terrain_size * 0.5

    for _i in range(count):
        var p: Vector3 = _find_land_point(rng, Game.sea_level + 3.0, 0.55, true)
        if Vector2(p.x, p.z).length() < 1200.0:
            continue

        var site := Node3D.new()
        site.position = Vector3(p.x, p.y + 0.05, p.z)
        site.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
        root.add_child(site)

        var n_buildings: int = rng.randi_range(2, 5)
        for _b in range(n_buildings):
            var b := MeshInstance3D.new()
            var bm := BoxMesh.new()
            bm.size = Vector3(rng.randf_range(55.0, 140.0), rng.randf_range(18.0, 55.0), rng.randf_range(50.0, 150.0))
            b.mesh = bm
            b.material_override = fac_mat
            b.position = Vector3(rng.randf_range(-80.0, 80.0), bm.size.y * 0.5, rng.randf_range(-80.0, 80.0))
            site.add_child(b)

        var n_stacks: int = rng.randi_range(1, 3)
        for _s in range(n_stacks):
            var st := MeshInstance3D.new()
            var cm := CylinderMesh.new()
            cm.top_radius = rng.randf_range(2.6, 4.8)
            cm.bottom_radius = cm.top_radius
            cm.height = rng.randf_range(55.0, 120.0)
            st.mesh = cm
            st.material_override = stack_mat
            st.position = Vector3(rng.randf_range(-70.0, 70.0), cm.height * 0.5, rng.randf_range(-70.0, 70.0))
            site.add_child(st)


func _build_boats(parent: Node3D, rng: RandomNumberGenerator) -> void:
    # Small boats at coast + a few at river mouths.
    var root := Node3D.new()
    root.name = "Boats"
    parent.add_child(root)

    var boat_mat := StandardMaterial3D.new()
    boat_mat.albedo_color = Color(0.18, 0.18, 0.20)
    boat_mat.roughness = 0.85

    var n: int = 12
    for i in range(n):
        var ang: float = rng.randf_range(0.0, TAU)
        var dist: float = rng.randf_range(_terrain_size * 0.58, _terrain_size * 0.92)
        var x: float = cos(ang) * dist
        var z: float = sin(ang) * dist

        # Put boats in water.
        var y: float = Game.sea_level + 0.22

        var boat := Node3D.new()
        boat.position = Vector3(x, y, z)
        boat.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
        root.add_child(boat)

        var hull := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(rng.randf_range(18.0, 32.0), 3.0, rng.randf_range(6.0, 10.0))
        hull.mesh = bm
        hull.material_override = boat_mat
        hull.position = Vector3(0.0, 1.0, 0.0)
        boat.add_child(hull)

        var cabin := MeshInstance3D.new()
        var cb := BoxMesh.new()
        cb.size = Vector3(bm.size.x * 0.35, 4.0, bm.size.z * 0.70)
        cabin.mesh = cb
        cabin.material_override = boat_mat
        cabin.position = Vector3(-bm.size.x * 0.10, 4.0, 0.0)
        boat.add_child(cabin)


func _build_moskva_cruiser(parent: Node3D) -> void:
    print("=== MOSKVA CRUISER: Starting build function ===")

    # Load the GLB model
    print("MOSKVA: Loading GLB from res://assets/models/moskva.glb")
    var scene = load("res://assets/models/moskva.glb")
    print("MOSKVA: Load result: ", scene)

    if not scene:
        push_error("MOSKVA ERROR: Failed to load moskva.glb")
        return

    print("MOSKVA: Instantiating scene...")
    var cruiser = scene.instantiate()
    print("MOSKVA: Cruiser instance: ", cruiser)
    cruiser.name = "MoskvaCruiser"

    # Scale to 6x (60% of the 10x that worked)
    cruiser.scale = Vector3(6, 6, 6)
    print("MOSKVA: Scaled to 6x")

    # Calculate ocean position (northeast quadrant, 200m further offshore)
    var angle = deg_to_rad(45)  # Northeast direction
    var distance = Game.settings.get("terrain_size", 8000) * 0.75 + 200.0
    var x = cos(angle) * distance
    var z = sin(angle) * distance
    var y = Game.sea_level + 50

    print("MOSKVA: Position calculated: (%.1f, %.1f, %.1f)" % [x, y, z])

    cruiser.position = Vector3(x, y, z)
    cruiser.rotation_degrees.y = 90  # Face east

    # Set metadata for collision system
    print("MOSKVA: Setting metadata (boat_type=freighter)...")
    cruiser.set_meta("boat_type", "freighter")  # Heavy boat type
    cruiser.set_meta("mesh_size", Vector3(840, 180, 120))  # 6x scaled cruiser dimensions
    cruiser.set_meta("is_moskva", true)  # Enable special fire/smoke effects

    # Add damage component (following pattern from boat_generator.gd:530-533)
    print("MOSKVA: Creating BoatDamageableObject...")
    var boat_damageable = BoatDamageableObject.new()
    boat_damageable.name = "BoatDamageable"
    boat_damageable.boat_type = "freighter"  # Maritime_Heavy: 120-180 HP
    cruiser.add_child(boat_damageable)
    print("MOSKVA: BoatDamageable added")

    # Add to scene tree
    print("MOSKVA: Adding cruiser to parent...")
    parent.add_child(cruiser)
    print("MOSKVA: Cruiser added to scene tree")

    # Register collision (must happen after add_child)
    print("MOSKVA: Registering collision...")
    CollisionManager.add_collision_to_object(cruiser, "boat")
    print("MOSKVA: Collision registered")

    print("✓✓✓ MOSKVA CRUISER COMPLETE: Placed at (%.1f, %.1f, %.1f) ✓✓✓" % [x, y, z])


func _build_red_square(parent: Node3D) -> void:
    print("=== RED SQUARE: Starting build function ===")

    # Load the GLB model
    print("RED_SQUARE: Loading GLB from res://assets/models/red_square.glb")
    var scene = load("res://assets/models/red_square.glb")
    print("RED_SQUARE: Load result: ", scene)

    if not scene:
        push_error("RED_SQUARE ERROR: Failed to load red_square.glb")
        return

    print("RED_SQUARE: Instantiating scene...")
    var red_square = scene.instantiate()
    print("RED_SQUARE: Instance: ", red_square)
    red_square.name = "RedSquareBuilding"

    # Scale to 1.25x (25% of original 5.0x - 75% smaller)
    red_square.scale = Vector3(1.25, 1.25, 1.25)
    print("RED_SQUARE: Scaled to 1.25x (25% of original 5.0x)")

    # Add to scene tree FIRST so we can calculate AABB
    print("RED_SQUARE: Adding to parent temporarily for AABB calculation...")
    parent.add_child(red_square)

    # Convert GLB materials to StandardMaterial3D for damage system compatibility
    _convert_glb_materials_to_standard(red_square)

    # CRITICAL: Red Square GLB has no materials, so we must manually color it red
    _apply_red_color_to_red_square(red_square)

    # Calculate actual bounding box after scaling (search recursively)
    var aabb = AABB()
    var found_mesh = false

    # Use queue-based search to find all MeshInstance3D nodes recursively
    var queue: Array = [red_square]
    while queue.size() > 0:
        var node = queue.pop_front()

        if node is MeshInstance3D:
            var mesh_inst = node as MeshInstance3D
            if mesh_inst.mesh:
                var mesh_aabb = mesh_inst.get_aabb()
                if found_mesh:
                    aabb = aabb.merge(mesh_aabb)
                else:
                    aabb = mesh_aabb
                    found_mesh = true
                print("RED_SQUARE: Found mesh '%s' with AABB: %s" % [mesh_inst.name, mesh_aabb])

        # Add children to queue
        for child in node.get_children():
            queue.append(child)

    # Check if we found any meshes
    if not found_mesh:
        push_error("RED_SQUARE: No meshes found in GLB! Using fallback size.")
        aabb.size = Vector3(100, 100, 100)  # Fallback size

    # Account for the building's scale in the AABB
    var scaled_size = aabb.size * red_square.scale
    print("RED_SQUARE: Total AABB before scale: %s" % aabb)
    print("RED_SQUARE: Scaled dimensions: %s" % scaled_size)

    # Place in ocean at sea level in Southwest corner (opposite of original NE position)
    var angle = deg_to_rad(225)  # Southwest direction (opposite corner)
    var distance = Game.settings.get("terrain_size", 8000) * 0.75
    var x = cos(angle) * distance
    var z = sin(angle) * distance
    var y = Game.sea_level  # Exactly at sea level to check anchor point

    print("RED_SQUARE: Placed in Southwest corner at sea level: (%.1f, %.1f, %.1f)" % [x, y, z])
    red_square.position = Vector3(x, y, z)
    red_square.rotation_degrees.y = 0  # Face north

    # Set metadata for damage system
    print("RED_SQUARE: Setting metadata...")
    red_square.set_meta("building_type", "red_square")
    red_square.set_meta("mesh_size", scaled_size)

    # Add damage component
    print("RED_SQUARE: Creating BuildingDamageableObject...")
    var building_damageable = BuildingDamageableObject.new()
    building_damageable.name = "BuildingDamageable"
    building_damageable.building_type = "red_square"  # Maps to Industrial set
    red_square.add_child(building_damageable)
    print("RED_SQUARE: BuildingDamageable added")

    # Create MANUAL collision box with exact dimensions
    print("RED_SQUARE: Creating manual collision body...")
    var collision_body = StaticBody3D.new()
    collision_body.name = "RedSquareCollision"
    collision_body.collision_layer = 1
    collision_body.collision_mask = 1

    # Link back to building for damage
    collision_body.set_meta("damage_target", red_square)

    var collision_shape = CollisionShape3D.new()
    var box_shape = BoxShape3D.new()
    # Use UNSCALED size since collision body will inherit parent's scale
    box_shape.size = aabb.size
    collision_shape.shape = box_shape

    collision_body.add_child(collision_shape)

    # Position collision at AABB center in LOCAL space
    # Make collision a CHILD of red_square so transforms are hierarchical
    collision_body.position = aabb.get_center()  # Local space offset
    collision_body.rotation = Vector3.ZERO  # No rotation needed (inherits from parent)

    red_square.add_child(collision_body)

    # Store reference for later removal
    red_square.set_meta("manual_collision_body", collision_body)

    print("RED_SQUARE: AABB center (local): %s" % aabb.get_center())
    print("RED_SQUARE: Collision local position: %s" % collision_body.position)
    print("RED_SQUARE: Collision box size (unscaled): %s" % box_shape.size)
    print("RED_SQUARE: Collision box size (with parent scale): %s" % (box_shape.size * red_square.scale))

    print("RED_SQUARE: Collision box created with size: %s" % box_shape.size)
    print("RED_SQUARE: Collision position: %s" % collision_body.global_position)

    print("✓✓✓ RED SQUARE COMPLETE: Placed at (%.1f, %.1f, %.1f) ✓✓✓" % [x, y, z])
    print("    Building scale: %s" % red_square.scale)
    print("    Collision size: %s" % box_shape.size)
    print("    Is in scene: %s" % red_square.is_inside_tree())
    print("    Collision in scene: %s" % collision_body.is_inside_tree())

    # Track red square position for tree collision avoidance
    if _world_builder:
        var ctx = _world_builder.get_context()
        if ctx and ctx.has_data("building_positions"):
            var building_positions: Array = ctx.get_data("building_positions")
            # Calculate radius from bounding box (use largest horizontal dimension)
            var building_radius: float = max(scaled_size.x, scaled_size.z) / 2.0
            building_positions.append({
                "position": red_square.global_position,
                "radius": building_radius
            })
            ctx.set_data("building_positions", building_positions)
            print("🏗️ RED SQUARE: Added to building positions for tree avoidance (radius: %.1fm)" % building_radius)


func _get_beach_shack_variant_pool(lod_level: int) -> Array:
    _ensure_prop_mesh_cache()

    var pool: Array = []

    # External meshes (optional)
    if _assets != null and _assets.enabled():
        var ext: Array = _assets.get_mesh_variants("beach_shacks")
        for i in range(ext.size()):
            var m: Mesh = ext[i] as Mesh
            pool.append({
                "name": "ext_shack_%d" % i,
                "kind": "ext",
                "mesh": m,
                "weight": 1.0
            })

    if lod_level >= 2:
        # Far proxy
        pool.append({
            "name": "proxy",
            "kind": "proc",
            "wall_mesh": _mesh_unit_box,
            "roof_kind": "none",
            "roof_mesh": null,
            "sx_mul": 1.0,
            "sz_mul": 1.0,
            "sy_mul": 1.0,
            "roof_h_mul": 0.0,
            "weight": 1.0
        })
        return pool

    # Procedural silhouettes: gable hut, hip hut, A-frame, flat shed.
    pool.append({
        "name": "hut_gable",
        "kind": "proc",
        "wall_mesh": _mesh_unit_box,
        "roof_kind": "gable",
        "roof_mesh": _get_gable_roof_mesh(),
        "sx_mul": 1.0,
        "sz_mul": 1.0,
        "sy_mul": 1.0,
        "roof_h_mul": 0.50,
        "weight": 2.2
    })
    pool.append({
        "name": "hut_hip",
        "kind": "proc",
        "wall_mesh": _mesh_unit_box,
        "roof_kind": "hip",
        "roof_mesh": _get_hip_roof_mesh(),
        "sx_mul": 1.0,
        "sz_mul": 1.0,
        "sy_mul": 1.0,
        "roof_h_mul": 0.45,
        "weight": 1.5
    })
    pool.append({
        "name": "a_frame",
        "kind": "proc",
        "wall_mesh": _mesh_unit_box,
        "roof_kind": "gable",
        "roof_mesh": _get_gable_roof_mesh(),
        "sx_mul": 0.90,
        "sz_mul": 0.90,
        "sy_mul": 0.70,
        "roof_h_mul": 0.85,
        "weight": 1.0
    })
    pool.append({
        "name": "shed_flat",
        "kind": "proc",
        "wall_mesh": _mesh_unit_box,
        "roof_kind": "flat",
        "roof_mesh": _mesh_unit_flat,
        "sx_mul": 1.05,
        "sz_mul": 1.05,
        "sy_mul": 0.90,
        "roof_h_mul": 0.0,
        "weight": 0.9
    })

    return pool


func _select_subset(rng: RandomNumberGenerator, pool: Array, want: int) -> Array:
    # Deterministically pick up to `want` unique items from `pool`, using `rng`.
    # If want >= pool.size(), returns a shallow copy of the pool.
    if want <= 0 or pool.is_empty():
        return []
    if want >= pool.size():
        return pool.duplicate()

    var idxs: Array = []
    idxs.resize(pool.size())
    for i in range(pool.size()):
        idxs[i] = i

    # Fisher-Yates shuffle with provided RNG for determinism.
    for i in range(idxs.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)
        var tmp = idxs[i]
        idxs[i] = idxs[j]
        idxs[j] = tmp

    var out: Array = []
    out.resize(want)
    for k in range(want):
        out[k] = pool[idxs[k]]
    return out


func _emit_beach_shacks_lod(parent: Node3D, shacks: Array, seed: int, lod_level: int) -> void:
    if shacks.is_empty():
        return

    var rng := RandomNumberGenerator.new()
    rng.seed = seed + 331 * lod_level

    var body_mat := StandardMaterial3D.new()
    body_mat.vertex_color_use_as_albedo = true
    body_mat.albedo_color = Color(1, 1, 1)
    body_mat.roughness = 0.96

    var roof_mat := StandardMaterial3D.new()
    roof_mat.vertex_color_use_as_albedo = true
    roof_mat.albedo_color = Color(1, 1, 1)
    roof_mat.roughness = 0.92

    var body_palette := [
        Color(0.44, 0.34, 0.24),
        Color(0.56, 0.46, 0.32),
        Color(0.62, 0.60, 0.52),
        Color(0.42, 0.40, 0.38),
        Color(0.74, 0.74, 0.70)
    ]
    var roof_palette := [
        Color(0.36, 0.30, 0.18),
        Color(0.46, 0.38, 0.22),
        Color(0.26, 0.22, 0.18),
        Color(0.40, 0.34, 0.24)
    ]

    var pool: Array = _get_beach_shack_variant_pool(lod_level)
    if pool.is_empty():
        return

    var want: int = int(Game.settings.get("beach_shack_variants_near", 5))
    if lod_level == 1:
        want = int(Game.settings.get("beach_shack_variants_mid", 2))
    elif lod_level >= 2:
        want = 1

    var subset: Array = _select_subset(rng, pool, want)

    var buckets := {}
    for v in subset:
        var key: String = (v as Dictionary).get("name", "v")
        buckets[key] = {
            "variant": v,
            "walls": {"x": [], "c": []},
            "roofs": {"x": [], "c": []}
        }

    for s in shacks:
        if not (s is Dictionary):
            continue
        var d: Dictionary = s as Dictionary
        var x: float = float(d.get("x", 0.0))
        var y: float = float(d.get("y", 0.0))
        var z: float = float(d.get("z", 0.0))
        var sx: float = float(d.get("sx", 10.0))
        var sz: float = float(d.get("sz", 8.0))
        var sy: float = float(d.get("sy", 6.0))
        var rot: float = float(d.get("rot", 0.0))

        # Weighted pick within subset
        var variants: Array = subset
        var vi: int = _weighted_pick(rng, variants)
        var v: Dictionary = variants[vi] as Dictionary
        var key: String = v.get("name", "v")
        if not buckets.has(key):
            continue

        if String(v.get("kind", "proc")) == "ext":
            # External meshes: treat as monolithic.
            var m: Mesh = v.get("mesh", null)
            if m == null:
                continue
            var bx := Basis.IDENTITY
            bx = bx.rotated(Vector3.UP, rot)
            var uni: float = clamp((sx + sz) * 0.055, 0.55, 1.35)
            bx = bx.scaled(Vector3.ONE * uni)
            (buckets[key]["walls"]["x"] as Array).append(Transform3D(bx, Vector3(x, y, z)))
            continue

        var sxm: float = sx * float(v.get("sx_mul", 1.0))
        var szm: float = sz * float(v.get("sz_mul", 1.0))
        var sym: float = sy * float(v.get("sy_mul", 1.0))

        var bw := Basis.IDENTITY
        bw = bw.rotated(Vector3.UP, rot)
        bw = bw.scaled(Vector3(sxm, sym, szm))
        (buckets[key]["walls"]["x"] as Array).append(Transform3D(bw, Vector3(x, y + sym * 0.5, z)))

        var wc: Color = _palette_pick(rng, body_palette)
        wc.r += rng.randf_range(-0.05, 0.05)
        wc.g += rng.randf_range(-0.04, 0.04)
        wc.b += rng.randf_range(-0.04, 0.04)
        (buckets[key]["walls"]["c"] as Array).append(wc.clamp())

        var rk: String = String(v.get("roof_kind", "gable"))
        if rk == "none":
            continue

        if rk == "flat":
            var flat_h: float = clamp(min(sxm, szm) * 0.10, 0.8, 2.0)
            var rb := Basis.IDENTITY
            rb = rb.rotated(Vector3.UP, rot)
            rb = rb.scaled(Vector3(sxm * 1.02, flat_h, szm * 1.02))
            (buckets[key]["roofs"]["x"] as Array).append(Transform3D(rb, Vector3(x, y + sym + flat_h * 0.5, z)))
        else:
            var roof_h: float = clamp(min(sxm, szm) * float(v.get("roof_h_mul", 0.5)), 2.6, 6.8)
            var rb2 := Basis.IDENTITY
            rb2 = rb2.rotated(Vector3.UP, rot)
            rb2 = rb2.scaled(Vector3(sxm * 1.10, roof_h * 2.0, szm * 1.12))
            (buckets[key]["roofs"]["x"] as Array).append(Transform3D(rb2, Vector3(x, y + sym, z)))

        var rc: Color = _palette_pick(rng, roof_palette)
        rc.r += rng.randf_range(-0.04, 0.04)
        rc.g += rng.randf_range(-0.03, 0.03)
        rc.b += rng.randf_range(-0.03, 0.03)
        (buckets[key]["roofs"]["c"] as Array).append(rc.clamp())

    # Build MultiMeshes per variant
    for k in buckets.keys():
        var b: Dictionary = buckets[k] as Dictionary
        var v: Dictionary = b.get("variant", {})
        var kind: String = String(v.get("kind", "proc"))
        if kind == "ext":
            var mx: Array = b["walls"]["x"] as Array
            var m: Mesh = v.get("mesh", null)
            if m != null:
                _mm_batch(parent, "Shack_%s" % String(k), m, null, mx, [])
            continue

        var wmesh: Mesh = v.get("wall_mesh", _mesh_unit_box)
        var rmesh: Mesh = v.get("roof_mesh", null)
        _mm_batch(parent, "ShackW_%s" % String(k), wmesh, body_mat, b["walls"]["x"], b["walls"]["c"])
        _mm_batch(parent, "ShackR_%s" % String(k), rmesh, roof_mat, b["roofs"]["x"], b["roofs"]["c"])


func _build_beach_shacks(parent: Node3D, rng: RandomNumberGenerator, count: int) -> void:
    if count <= 0:
        return

    var root := Node3D.new()
    root.name = "BeachShacks"
    parent.add_child(root)

    var half: float = _terrain_size * 0.5
    var chunk_size: float = float(int(Game.settings.get("terrain_chunk_size", 1024))) * 1.25

    var chunks := {}

    var placed: int = 0
    var attempts: int = 0
    var max_attempts: int = count * 40

    while placed < count and attempts < max_attempts:
        attempts += 1

        # Bias toward the coast ring.
        var ang: float = rng.randf_range(0.0, TAU)
        var dist: float = rng.randf_range(_terrain_size * 0.48, _terrain_size * 0.92)
        var x: float = cos(ang) * dist + rng.randf_range(-320.0, 320.0)
        var z: float = sin(ang) * dist + rng.randf_range(-320.0, 320.0)

        if x < -half or x > half or z < -half or z > half:
            continue
        if Vector2(x, z).length() < 650.0:
            continue

        var y: float = _ground_height(x, z)

        # Close to sea level and near water, but not in it.
        if y < Game.sea_level + 1.35 or y > Game.sea_level + 26.0:
            continue
        if not _is_near_coast(x, z, 170.0):
            continue
        if _slope_at(x, z) > 0.68:
            continue
        if _too_close_to_settlements(Vector3(x, y, z), 180.0) and rng.randf() < 0.65:
            continue

        var sx: float = rng.randf_range(8.0, 16.0)
        var sz: float = rng.randf_range(6.0, 13.0)
        var sy: float = rng.randf_range(4.2, 8.5)
        var rot: float = rng.randf_range(0.0, TAU)

        var cx: int = int(floor(x / chunk_size))
        var cz: int = int(floor(z / chunk_size))
        var key: String = "%d,%d" % [cx, cz]
        if not chunks.has(key):
            var ccx: float = (float(cx) + 0.5) * chunk_size
            var ccz: float = (float(cz) + 0.5) * chunk_size
            var cy: float = _ground_height(ccx, ccz)
            chunks[key] = {
                "center": Vector3(ccx, cy, ccz),
                "items": []
            }

        (chunks[key]["items"] as Array).append({
            "x": x,
            "y": y,
            "z": z,
            "sx": sx,
            "sz": sz,
            "sy": sy,
            "rot": rot
        })

        placed += 1

    # Build per-chunk LOD groups.
    for key in chunks.keys():
        var cd: Dictionary = chunks[key] as Dictionary
        var center: Vector3 = cd.get("center", Vector3.ZERO)
        var items: Array = cd.get("items", [])
        if items.is_empty():
            continue

        var chunk_root := Node3D.new()
        chunk_root.name = "ShacksChunk_%s" % String(key)
        root.add_child(chunk_root)

        var lod0 := Node3D.new()
        lod0.name = "LOD0"
        chunk_root.add_child(lod0)

        var lod1 := Node3D.new()
        lod1.name = "LOD1"
        chunk_root.add_child(lod1)

        var lod2 := Node3D.new()
        lod2.name = "LOD2"
        chunk_root.add_child(lod2)

        lod0.visible = true
        lod1.visible = false
        lod2.visible = false

        var seed: int = int(Game.settings.get("world_seed", 0)) + int(absf(center.x + center.z) * 0.35) + 31007
        _emit_beach_shacks_lod(lod0, items, seed, 0)
        _emit_beach_shacks_lod(lod1, items, seed, 1)
        _emit_beach_shacks_lod(lod2, items, seed, 2)

        _prop_lod_groups.append({
            "center": center,
            "lod0": lod0,
            "lod1": lod1,
            "lod2": lod2,
            "current": -1
        })


func _build_ww2_props(parent: Node3D, rng: RandomNumberGenerator) -> void:
    var root := Node3D.new()
    root.name = "WW2Props"
    parent.add_child(root)

    # Simple control tower / radio mast near runway
    var runway_y: float = _ground_height(0.0, 0.0) + 0.05

    var tower := Node3D.new()
    tower.name = "ControlTower"
    tower.position = Vector3(58.0, runway_y, -30.0)
    root.add_child(tower)

    var base := MeshInstance3D.new()
    var bm := CylinderMesh.new()
    bm.top_radius = 7.0
    bm.bottom_radius = 7.5
    bm.height = 18.0
    base.mesh = bm
    base.position = Vector3(0.0, bm.height * 0.5, 0.0)
    var cmat := StandardMaterial3D.new()
    cmat.albedo_color = Color(0.55, 0.54, 0.52)
    cmat.roughness = 0.95
    base.material_override = cmat
    tower.add_child(base)

    var cab := MeshInstance3D.new()
    var cb := BoxMesh.new()
    cb.size = Vector3(18.0, 6.0, 14.0)
    cab.mesh = cb
    cab.position = Vector3(0.0, bm.height + cb.size.y * 0.5, 0.0)
    var gmat := StandardMaterial3D.new()
    gmat.albedo_color = Color(0.26, 0.30, 0.22) # olive drab
    gmat.roughness = 0.92
    cab.material_override = gmat
    tower.add_child(cab)

    var mast := MeshInstance3D.new()
    var mm := CylinderMesh.new()
    mm.top_radius = 0.25
    mm.bottom_radius = 0.35
    mm.height = 34.0
    mast.mesh = mm
    mast.position = Vector3(0.0, bm.height + cb.size.y + mm.height * 0.5, 0.0)
    var mmat := StandardMaterial3D.new()
    mmat.albedo_color = Color(0.16, 0.16, 0.16)
    mmat.roughness = 0.85
    mast.material_override = mmat
    tower.add_child(mast)

    # A few AA nests on higher ground near the coast ring
    var aa_mat := StandardMaterial3D.new()
    aa_mat.albedo_color = Color(0.18, 0.18, 0.18)
    aa_mat.roughness = 0.90

    for _i in range(6):
        # Find a coastal high point
        var p: Vector3 = _find_land_point(rng, Game.sea_level + 55.0, 0.80, true)
        if Vector2(p.x, p.z).length() < 900.0:
            continue

        var nest := Node3D.new()
        nest.position = Vector3(p.x, p.y + 0.05, p.z)
        nest.rotation_degrees = Vector3(0.0, rng.randf_range(0.0, 360.0), 0.0)
        root.add_child(nest)

        # Concrete ring
        var ring := MeshInstance3D.new()
        var rb2 := CylinderMesh.new()
        rb2.top_radius = 22.0
        rb2.bottom_radius = 22.0
        rb2.height = 3.0
        ring.mesh = rb2
        ring.material_override = cmat
        ring.position = Vector3(0.0, rb2.height * 0.5, 0.0)
        nest.add_child(ring)

        # Simple gun silhouette
        var gun := Node3D.new()
        gun.position = Vector3(0.0, rb2.height, 0.0)
        nest.add_child(gun)

        var base2 := MeshInstance3D.new()
        var b2 := CylinderMesh.new()
        b2.top_radius = 3.0
        b2.bottom_radius = 3.6
        b2.height = 2.4
        base2.mesh = b2
        base2.material_override = aa_mat
        base2.position = Vector3(0.0, b2.height * 0.5, 0.0)
        gun.add_child(base2)

        for s in [-1, 1]:
            var barrel := MeshInstance3D.new()
            var cy := CylinderMesh.new()
            cy.top_radius = 0.35
            cy.bottom_radius = 0.35
            cy.height = 8.0
            barrel.mesh = cy
            barrel.material_override = aa_mat
            barrel.position = Vector3(float(s) * 0.9, 2.2, -3.0)
            barrel.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
            gun.add_child(barrel)


func _build_forest_external(root: Node3D, rng: RandomNumberGenerator, tree_target: int, patch_count: int, tree_variants: Array[Mesh]) -> void:
    # Build forest using external tree meshes with biome-appropriate selection
    var patch_centers: Array[Vector2] = []
    for _p in range(patch_count):
        var c3: Vector3 = _find_land_point(rng, Game.sea_level + 8.0, 0.70, false)
        patch_centers.append(Vector2(c3.x, c3.z))

    # Create a MultiMesh for each tree variant (efficient batching)
    var multimeshes: Array[MultiMesh] = []
    var transforms_per_mesh: Array[Array] = []

    for i in range(min(tree_variants.size(), 12)):  # Limit to 12 variants for performance
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.mesh = tree_variants[i]
        multimeshes.append(mm)
        transforms_per_mesh.append([])

    var half: float = _terrain_size * 0.5
    var runway_excl: float = 420.0

    var placed: int = 0
    var attempts: int = 0
    var max_attempts: int = tree_target * 4

    while placed < tree_target and attempts < max_attempts:
        attempts += 1

        var pc: Vector2 = patch_centers[rng.randi_range(0, patch_centers.size() - 1)]
        var x: float = pc.x + float(rng.randfn(0.0, 980.0))
        var z: float = pc.y + float(rng.randfn(0.0, 980.0))

        if x < -half or x > half or z < -half or z > half:
            continue

        if Vector2(x, z).length() < runway_excl:
            continue

        var y: float = _ground_height(x, z)
        if y < Game.sea_level + 2.0:
            continue

        if _slope_at(x, z) > 0.90:
            continue

        if _too_close_to_settlements(Vector3(x, y, z), 260.0):
            continue

        var rot: float = rng.randf_range(0.0, TAU)
        var scale: float = rng.randf_range(0.65, 1.35)

        # Biome-based tree selection (simple altitude-based for now)
        var variant_idx: int
        if y > 80.0:
            # High altitude: prefer conifers (first third of variants)
            variant_idx = rng.randi_range(0, max(0, multimeshes.size() / 3 - 1))
        elif abs(x) < half * 0.3 and abs(z) < half * 0.3:
            # Central area: mix of all types
            variant_idx = rng.randi_range(0, multimeshes.size() - 1)
        else:
            # Mid/low altitude: broadleaf and mixed
            variant_idx = rng.randi_range(multimeshes.size() / 3, multimeshes.size() - 1)

        variant_idx = clampi(variant_idx, 0, multimeshes.size() - 1)

        var basis := Basis.IDENTITY
        basis = basis.rotated(Vector3.UP, rot)
        basis = basis.scaled(Vector3(scale, scale, scale))

        var pos := Vector3(x, y, z)
        transforms_per_mesh[variant_idx].append(Transform3D(basis, pos))

        placed += 1

    # Create MultiMeshInstance3D for each variant
    for i in range(multimeshes.size()):
        if transforms_per_mesh[i].size() == 0:
            continue

        multimeshes[i].instance_count = transforms_per_mesh[i].size()
        for j in range(transforms_per_mesh[i].size()):
            multimeshes[i].set_instance_transform(j, transforms_per_mesh[i][j])

        var mmi := MultiMeshInstance3D.new()
        mmi.multimesh = multimeshes[i]
        mmi.name = "Trees_%d" % i
        root.add_child(mmi)


func _build_forest_batched() -> void:
    # Massive forests using MultiMesh batching (fast + lots of trees).
    var root := Node3D.new()
    root.name = "Forest"
    _world_root.add_child(root)

    var seed: int = int(Game.settings.get("world_seed", 0))
    var rng := RandomNumberGenerator.new()
    rng.seed = seed + 6000

    var tree_target: int = int(Game.settings.get("tree_count", 8000))
    var patch_count: int = int(Game.settings.get("forest_patches", 26))

    # Check for external tree assets
    var use_external_trees: bool = false
    var external_tree_variants: Array[Mesh] = []
    if _assets != null and _assets.enabled():
        # Mix all tree types (conifer, broadleaf, palm) for variety
        var conifers: Array[Mesh] = _assets.get_mesh_variants("trees_conifer")
        var broadleaf: Array[Mesh] = _assets.get_mesh_variants("trees_broadleaf")
        var palms: Array[Mesh] = _assets.get_mesh_variants("trees_palm")

        # Combine all available tree types
        external_tree_variants.append_array(conifers)
        external_tree_variants.append_array(broadleaf)
        external_tree_variants.append_array(palms)

        if external_tree_variants.size() > 0:
            use_external_trees = true

    # If using external trees, create MultiMesh instances for each variant
    if use_external_trees:
        _build_forest_external(root, rng, tree_target, patch_count, external_tree_variants)
        return

    var patch_centers: Array[Vector2] = []
    for _p in range(patch_count):
        var c3: Vector3 = _find_land_point(rng, Game.sea_level + 8.0, 0.70, false)
        patch_centers.append(Vector2(c3.x, c3.z))

    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.12
    trunk_mesh.bottom_radius = 0.16
    trunk_mesh.height = 1.6

    var leaf_cone_mesh := CylinderMesh.new()
    leaf_cone_mesh.top_radius = 0.05
    leaf_cone_mesh.bottom_radius = 0.95
    leaf_cone_mesh.height = 2.2

    var leaf_sphere_mesh := SphereMesh.new()
    leaf_sphere_mesh.radius = 1.0

    var trunk_mat := StandardMaterial3D.new()
    trunk_mat.vertex_color_use_as_albedo = true
    trunk_mat.albedo_color = Color(1, 1, 1)
    trunk_mat.roughness = 1.0

    var leaf_mat := StandardMaterial3D.new()
    leaf_mat.vertex_color_use_as_albedo = true
    leaf_mat.albedo_color = Color(1, 1, 1)
    leaf_mat.roughness = 1.0

    var trunks := MultiMesh.new()
    trunks.transform_format = MultiMesh.TRANSFORM_3D
    trunks.use_colors = true
    trunks.mesh = trunk_mesh

    var leaves_a := MultiMesh.new()
    leaves_a.transform_format = MultiMesh.TRANSFORM_3D
    leaves_a.use_colors = true
    leaves_a.mesh = leaf_cone_mesh

    var leaves_b := MultiMesh.new()
    leaves_b.transform_format = MultiMesh.TRANSFORM_3D
    leaves_b.use_colors = true
    leaves_b.mesh = leaf_sphere_mesh

    # Pre-allocate transform arrays (we fill and then assign instance_count).
    var trunk_x: Array[Transform3D] = []
    var trunk_c: Array[Color] = []

    var leaf_a_x: Array[Transform3D] = []
    var leaf_a_c: Array[Color] = []

    var leaf_b_x: Array[Transform3D] = []
    var leaf_b_c: Array[Color] = []

    var half: float = _terrain_size * 0.5
    var runway_excl: float = 420.0

    var placed: int = 0
    var attempts: int = 0
    var max_attempts: int = tree_target * 4

    while placed < tree_target and attempts < max_attempts:
        attempts += 1

        var pc: Vector2 = patch_centers[rng.randi_range(0, patch_centers.size() - 1)]
        var x: float = pc.x + float(rng.randfn(0.0, 980.0))
        var z: float = pc.y + float(rng.randfn(0.0, 980.0))

        if x < -half or x > half or z < -half or z > half:
            continue

        if Vector2(x, z).length() < runway_excl:
            continue

        var y: float = _ground_height(x, z)
        if y < Game.sea_level + 2.0:
            continue

        if _slope_at(x, z) > 0.90:
            continue

        if _too_close_to_settlements(Vector3(x, y, z), 260.0):
            continue

        var rot: float = rng.randf_range(0.0, TAU)
        var scale: float = rng.randf_range(0.85, 1.75)

        var trunk_h: float = rng.randf_range(1.15, 1.95) * scale
        var trunk_sy: float = trunk_h / 1.6

        var trunk_basis := Basis.IDENTITY
        trunk_basis = trunk_basis.rotated(Vector3.UP, rot)
        trunk_basis = trunk_basis.scaled(Vector3(scale, trunk_sy, scale))

        var trunk_pos := Vector3(x, y + (trunk_h * 0.5), z)
        trunk_x.append(Transform3D(trunk_basis, trunk_pos))
        trunk_c.append(Color(0.17 + rng.randf() * 0.05, 0.12 + rng.randf() * 0.04, 0.08 + rng.randf() * 0.04, 1.0))

        # Leaves variant
        if rng.randf() < 0.62:
            var leaf_h: float = rng.randf_range(1.6, 2.8) * scale
            var leaf_sy: float = leaf_h / 2.2

            var lb := Basis.IDENTITY
            lb = lb.rotated(Vector3.UP, rot)
            lb = lb.scaled(Vector3(scale * 0.95, leaf_sy, scale * 0.95))

            var lp := Vector3(x, y + trunk_h + (leaf_h * 0.42), z)
            leaf_a_x.append(Transform3D(lb, lp))

            var g := 0.20 + rng.randf() * 0.22
            leaf_a_c.append(Color(0.10 + rng.randf() * 0.08, g, 0.10 + rng.randf() * 0.08, 1.0))
        else:
            var r: float = rng.randf_range(0.75, 1.45) * scale

            var lb2 := Basis.IDENTITY
            lb2 = lb2.rotated(Vector3.UP, rot)
            lb2 = lb2.scaled(Vector3(r, r, r))

            var lp2 := Vector3(x, y + trunk_h + r * 0.80, z)
            leaf_b_x.append(Transform3D(lb2, lp2))

            var g2 := 0.18 + rng.randf() * 0.24
            leaf_b_c.append(Color(0.10 + rng.randf() * 0.08, g2, 0.10 + rng.randf() * 0.08, 1.0))

        placed += 1

    trunks.instance_count = trunk_x.size()
    for i in range(trunk_x.size()):
        trunks.set_instance_transform(i, trunk_x[i])
        trunks.set_instance_color(i, trunk_c[i])

    leaves_a.instance_count = leaf_a_x.size()
    for i in range(leaf_a_x.size()):
        leaves_a.set_instance_transform(i, leaf_a_x[i])
        leaves_a.set_instance_color(i, leaf_a_c[i])

    leaves_b.instance_count = leaf_b_x.size()
    for i in range(leaf_b_x.size()):
        leaves_b.set_instance_transform(i, leaf_b_x[i])
        leaves_b.set_instance_color(i, leaf_b_c[i])

    var trunks_i := MultiMeshInstance3D.new()
    trunks_i.multimesh = trunks
    trunks_i.material_override = trunk_mat
    root.add_child(trunks_i)

    var leaves_ai := MultiMeshInstance3D.new()
    leaves_ai.multimesh = leaves_a
    leaves_ai.material_override = leaf_mat
    root.add_child(leaves_ai)

    var leaves_bi := MultiMeshInstance3D.new()
    leaves_bi.multimesh = leaves_b
    leaves_bi.material_override = leaf_mat
    root.add_child(leaves_bi)


func _setup_player() -> void:
    _player = RigidBody3D.new()
    _player.set_script(PlayerPlaneScript)
    _player.name = "Player"
    _player.plane_defs = plane_defs
    _player.weapon_defs = weapon_defs

    _player.position = _runway_spawn
    add_child(_player)
    
    # Add player to group for weapon detection
    _player.add_to_group("player")

    Game.player = _player

    var camrig = get_node_or_null("CameraRig")
    if camrig and camrig.has_method("set_target"):
        camrig.set_target(_player)


func _setup_hud() -> void:
    _hud = HUDScript.new()
    add_child(_hud)


func _spawn_wave(wave: int) -> void:
    _spawn_timer = 0.0
    _wave_size = int(2 + wave * 0.55 * float(Game.settings.get("difficulty", 1.0)))
    for i in range(_wave_size):
        _spawn_enemy(i, _wave_size)

    await get_tree().create_timer(0.2).timeout
    if _player and _player.has_method("_cycle_target"):
        _player._cycle_target()


func _spawn_enemy(i: int, n: int) -> void:
    if _player == null or not is_instance_valid(_player):
        printerr("ERROR: Attempting to spawn enemy but player is null or invalid!")
        return

    # Validate player position to catch coordinate issues
    var player_pos = _player.global_position
    if player_pos.x > 10000 or player_pos.x < -10000 or player_pos.z > 10000 or player_pos.z < -10000:
        printerr("WARNING: Player position is unusually far from origin: ", player_pos)
        # Reset to runway spawn if player is too far
        player_pos = _runway_spawn

    var e := RigidBody3D.new()
    e.set_script(EnemyPlaneScript)
    e.name = "Enemy_%d" % i
    e.plane_defs = plane_defs
    e.weapon_defs = weapon_defs

    # Spawn in front of player, spread laterally + vertically.
    var fwd: Vector3 = Vector3(0, 0, -1)
    if _player.has_method("get_forward"):
        fwd = _player.get_forward()
    var right: Vector3 = _player.global_transform.basis.x.normalized()
    var up: Vector3 = Vector3.UP

    var base_range: float = 1200.0 + randf() * 800.0  # Increased from 400-700 to 800-1400 units
#    var base_range: float = 800.0 + randf() * 600.0  # Increased from 400-700 to 800-1400 units
#    var base_range: float = 3200.0 + randf() * 2400.0  # Increased 4x: 3200-5600 units
    var center: float = (float(n) - 1.0) * 0.5
    var lateral: float = (float(i) - center) * 120.0 + randf_range(-40.0, 40.0)  # Reduced spread
    var vertical: float = randf_range(-50.0, 100.0)  # Reduced vertical spread

    var pos: Vector3 = player_pos + fwd * base_range + right * lateral + up * vertical

    # Validate enemy spawn position to prevent extremely far spawns
    if pos.x > 10000 or pos.x < -10000 or pos.z > 10000 or pos.z < -10000:
        printerr("WARNING: Calculated enemy spawn position is unusually far from origin: ", pos)
        # Fallback to spawn near player but in front
        pos = player_pos + fwd * 500.0

    e.position = pos

    add_child(e)
    e.look_at(player_pos, Vector3.UP)  # Use validated player position
    e.rotate_object_local(Vector3.FORWARD, randf_range(-0.5, 0.5))

    if e.has_method("set_player"):
        e.set_player(_player)

    GameEvents.enemy_spawned.emit(e)

    print("DEBUG: Spawned enemy ", e.name, " at position: ", pos, " relative to player at: ", player_pos)

func _init_parametric_system() -> void:
    # Initialize parametric building system
    if _parametric_system == null:
        _parametric_system = BuildingParametricSystem.new()
        _parametric_materials = {}

func _add_parametric_building(parent: Node3D, x: float, y: float, z: float,
                               sx: float, sz: float, sy: float, rot: float,
                               style: String, lod_level: int, rng: RandomNumberGenerator) -> void:
    """Generate and add a parametric building to the scene."""

    # Initialize parametric system if needed
    if _parametric_system == null:
        _init_parametric_system()

    # Skip parametric buildings for mid/far LOD for performance
    if lod_level > 0:
        return

    # Determine building type based on settlement style
    var building_type = "residential"
    if "commercial" in style.to_lower() or "art_deco" in style.to_lower():
        building_type = "commercial"
    elif "industrial" in style.to_lower() or "warehouse" in style.to_lower():
        building_type = "industrial"

    # Map settlement style to parametric style
    var parametric_style = "ww2_european"
    if "art_deco" in style.to_lower():
        parametric_style = "american_art_deco"
    elif "industrial" in style.to_lower():
        parametric_style = "industrial_modern"

    # Calculate floors based on height
    var floors = max(1, int(sy / 4.0))

    # Quality level based on LOD (0=near, 1=mid, 2=far)
    var quality_level = 2 - lod_level

    # Generate parametric building
    var mesh = _parametric_system.create_parametric_building(
        building_type,
        parametric_style,
        sx,
        sz,
        sy,
        floors,
        quality_level
    )

    if mesh == null:
        return

    # Create MeshInstance3D and add to scene
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    # Position and rotate building
    mi.position = Vector3(x, y, z)
    mi.rotation.y = rot

    # Add to parent
    parent.add_child(mi)

func _on_enemy_destroyed(_enemy: Node) -> void:
    GameEvents.add_score(150)


func _on_player_destroyed() -> void:
    var overlay := CanvasLayer.new()
    var c := ColorRect.new()
    c.color = Color(0, 0, 0, 0.55)
    c.anchor_right = 1
    c.anchor_bottom = 1
    overlay.add_child(c)

    var label := Label.new()
    label.text = "YOU GOT SPLASHED\n\nPress Enter to Restart"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.anchor_left = 0
    label.anchor_top = 0
    label.anchor_right = 1
    label.anchor_bottom = 1
    # Use font from font manager if available
    var font = FontManagerScript.get_hud_font()
    if font != null:
        label.set("theme_override_fonts/font", font)
    label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    overlay.add_child(label)

    add_child(overlay)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

    await get_tree().create_timer(0.2).timeout
    while true:
        await get_tree().process_frame
        if Input.is_action_just_pressed("ui_accept"):
            get_tree().reload_current_scene()
            return


func _convert_glb_materials_to_standard(node: Node) -> void:
    """Recursively convert all GLB materials to StandardMaterial3D for damage system."""
    if node is MeshInstance3D:
        var mesh_inst = node as MeshInstance3D
        if mesh_inst.mesh:
            for i in range(mesh_inst.mesh.get_surface_count()):
                var original_mat = mesh_inst.mesh.surface_get_material(i)
                if original_mat and original_mat is BaseMaterial3D:
                    var base_mat = original_mat as BaseMaterial3D
                    # Create StandardMaterial3D copy with ALL properties
                    var std_mat = StandardMaterial3D.new()

                    # Copy albedo (color AND texture)
                    std_mat.albedo_color = base_mat.albedo_color
                    std_mat.albedo_texture = base_mat.albedo_texture

                    # Copy metallic
                    std_mat.metallic = base_mat.metallic
                    std_mat.metallic_specular = base_mat.metallic_specular
                    std_mat.metallic_texture = base_mat.metallic_texture

                    # Copy roughness
                    std_mat.roughness = base_mat.roughness
                    std_mat.roughness_texture = base_mat.roughness_texture

                    # Copy normal map
                    std_mat.normal_enabled = base_mat.normal_enabled
                    std_mat.normal_texture = base_mat.normal_texture

                    # Copy emission
                    std_mat.emission_enabled = base_mat.emission_enabled
                    std_mat.emission = base_mat.emission
                    std_mat.emission_energy_multiplier = base_mat.emission_energy_multiplier
                    std_mat.emission_texture = base_mat.emission_texture

                    # Copy other important properties
                    std_mat.transparency = base_mat.transparency
                    std_mat.cull_mode = base_mat.cull_mode
                    std_mat.shading_mode = base_mat.shading_mode

                    # Apply the standard material
                    mesh_inst.mesh.surface_set_material(i, std_mat)
                    print("RED_SQUARE: Converted surface %d material to StandardMaterial3D (color: %s, has_texture: %s)" % [i, base_mat.albedo_color, base_mat.albedo_texture != null])

    # Recurse to children
    for child in node.get_children():
        _convert_glb_materials_to_standard(child)


func _apply_red_color_to_red_square(node: Node) -> void:
    """Manually apply red color to Red Square model (GLB has no materials)."""
    if node is MeshInstance3D:
        var mesh_inst = node as MeshInstance3D
        if mesh_inst.mesh:
            # Create red material for each surface
            for i in range(mesh_inst.mesh.get_surface_count()):
                var red_mat = StandardMaterial3D.new()
                red_mat.albedo_color = Color(0.7, 0.1, 0.1)  # Deep red color
                red_mat.roughness = 0.8  # Slightly rough brick texture
                red_mat.metallic = 0.0   # Not metallic
                mesh_inst.mesh.surface_set_material(i, red_mat)
                print("RED_SQUARE: Applied red material to surface %d of %s" % [i, mesh_inst.name])

    # Recurse to children
    for child in node.get_children():
        _apply_red_color_to_red_square(child)


func _spawn_rising_ukrainian_flag(center_pos: Vector3) -> void:
    """Spawn a Ukrainian flag that rises from the ground at Red Square's center when it's destroyed."""
    print("🇺🇦 RED SQUARE DESTROYED! Spawning rising Ukrainian flag at: %s" % center_pos)

    # SUPER TALL POLE - Rising from the ground
    var final_pole_height = 160.0  # Super tall for dramatic effect
    var pole_base_radius = 2.0  # 2x thicker
    var pole_top_radius = 1.0   # 2x thicker
    var pole_segments = 16

    # Create pole mesh
    var pole_mesh = _create_flag_pole_mesh(final_pole_height, pole_base_radius, pole_top_radius, pole_segments)

    var pole_instance = MeshInstance3D.new()
    pole_instance.name = "UkrainianFlagPole_Victory"
    pole_instance.mesh = pole_mesh

    # Pole material - bright metallic gold/silver
    var pole_mat = StandardMaterial3D.new()
    pole_mat.albedo_color = Color(0.9, 0.9, 0.95)  # Bright silver
    pole_mat.metallic = 0.95
    pole_mat.roughness = 0.1
    pole_mat.emission_enabled = true
    pole_mat.emission = Color(0.8, 0.8, 1.0)  # Slight glow
    pole_mat.emission_energy_multiplier = 0.3
    pole_mesh.surface_set_material(0, pole_mat)

    # Add pole to world root (self is the Main node/world root)
    add_child(pole_instance)

    # Position at Red Square center, at sea level
    pole_instance.global_position = Vector3(center_pos.x, Game.sea_level, center_pos.z)

    # GOLD BALL ON TOP - Like traditional flagpoles
    var ball_radius = 1.5
    var ball_mesh = SphereMesh.new()
    ball_mesh.radius = ball_radius
    ball_mesh.height = ball_radius * 2.0
    ball_mesh.radial_segments = 16
    ball_mesh.rings = 16

    var ball_instance = MeshInstance3D.new()
    ball_instance.name = "FlagpoleGoldBall"
    ball_instance.mesh = ball_mesh

    # Gold material for ball
    var ball_mat = StandardMaterial3D.new()
    ball_mat.albedo_color = Color(1.0, 0.84, 0.0)  # Bright gold
    ball_mat.metallic = 1.0
    ball_mat.roughness = 0.2
    ball_mat.emission_enabled = true
    ball_mat.emission = Color(1.0, 0.9, 0.4)  # Golden glow
    ball_mat.emission_energy_multiplier = 0.5
    ball_mesh.surface_set_material(0, ball_mat)

    add_child(ball_instance)

    # Position ball at top of pole
    ball_instance.global_position = Vector3(center_pos.x, Game.sea_level + final_pole_height, center_pos.z)

    # FLAG GEOMETRY - HUGE dramatic flag (4x larger on each side)
    var flag_width = 45.0 
    var flag_height = 30.0

    var flag_mesh = _create_flag_mesh(flag_width, flag_height)

    var flag_instance = MeshInstance3D.new()
    flag_instance.name = "UkrainianFlag_Victory"
    flag_instance.mesh = flag_mesh

    # Flag material with Ukrainian flag texture
    var flag_mat = StandardMaterial3D.new()
    flag_mat.albedo_texture = load("res://assets/ukraine_flag.png")
    flag_mat.albedo_color = Color(1.0, 1.0, 1.0)
    flag_mat.roughness = 0.4
    flag_mat.metallic = 0.0
    flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
    flag_mat.emission_enabled = true
    flag_mat.emission = Color(0.3, 0.3, 0.5)  # Slight glow
    flag_mat.emission_energy_multiplier = 0.2
    flag_mesh.surface_set_material(0, flag_mat)

    # Add flag to world root
    add_child(flag_instance)

    # Position flag so its TOP aligns with TOP of pole
    # Flag bottom should be at: pole_top - flag_height
    var flag_bottom_y = final_pole_height - flag_height
    flag_instance.global_position = Vector3(center_pos.x + flag_width * 0.5, Game.sea_level, center_pos.z)

    print("🇺🇦 Flag pole, gold ball, and HUGE flag created at: %s" % pole_instance.global_position)
    print("🇺🇦 Flag size: %.1f × %.1f, Pole: %.1f tall, Ball radius: %.1f" % [flag_width, flag_height, final_pole_height, ball_radius])

    # ANIMATION: Rising from the ground
    # Start with pole, ball, and flag scaled down to 0 height, then grow upward
    pole_instance.scale = Vector3(1.0, 0.01, 1.0)  # Start nearly flat
    ball_instance.scale = Vector3(0.01, 0.01, 0.01)  # Start tiny
    flag_instance.scale = Vector3(1.0, 0.01, 1.0)

    # Create rising animation
    var rise_duration = 4.0  # 4 seconds to rise
    var tween = create_tween()
    tween.set_parallel(true)  # All animations happen simultaneously

    # Pole rises
    tween.tween_property(pole_instance, "scale", Vector3(1.0, 1.0, 1.0), rise_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

    # Gold ball grows and rises with pole
    tween.tween_property(ball_instance, "scale", Vector3(1.0, 1.0, 1.0), rise_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

    # Flag rises with pole, top edge aligned with pole top
    tween.tween_property(flag_instance, "scale", Vector3(1.0, 1.0, 1.0), rise_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(flag_instance, "global_position:y", Game.sea_level + flag_bottom_y, rise_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

    # Add a gentle wave/flutter animation after rising
    tween.chain().tween_callback(func(): _add_flag_flutter_animation(flag_instance))

    print("🇺🇦 Ukrainian flag rising animation started! Duration: %.1fs, Final height: %.1fm" % [rise_duration, final_pole_height])


func _add_flag_flutter_animation(flag_node: Node3D) -> void:
    """Add a gentle waving animation to the flag."""
    if not is_instance_valid(flag_node):
        return

    # Gentle rotation animation to simulate wind
    var flutter_tween = create_tween()
    flutter_tween.set_loops()  # Loop forever
    flutter_tween.tween_property(flag_node, "rotation:z", deg_to_rad(5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    flutter_tween.tween_property(flag_node, "rotation:z", deg_to_rad(-5), 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _create_flag_pole_mesh(height: float, base_radius: float, top_radius: float, segments: int) -> ArrayMesh:
    """Create a tapered cylindrical pole mesh using SurfaceTool."""
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Create cylinder with taper (like lighthouse pattern)
    var angle_step = TAU / segments

    # Bottom circle vertices
    for i in range(segments):
        var angle = i * angle_step
        var x = cos(angle) * base_radius
        var z = sin(angle) * base_radius
        st.set_normal(Vector3(x, 0, z).normalized())
        st.add_vertex(Vector3(x, 0, z))

    # Top circle vertices
    for i in range(segments):
        var angle = i * angle_step
        var x = cos(angle) * top_radius
        var z = sin(angle) * top_radius
        st.set_normal(Vector3(x, 0, z).normalized())
        st.add_vertex(Vector3(x, height, z))

    # Side faces (quads as two triangles)
    for i in range(segments):
        var next_i = (i + 1) % segments
        var bottom_i = i
        var bottom_next = next_i
        var top_i = segments + i
        var top_next = segments + next_i

        # Triangle 1
        st.add_index(bottom_i)
        st.add_index(top_i)
        st.add_index(bottom_next)

        # Triangle 2
        st.add_index(bottom_next)
        st.add_index(top_i)
        st.add_index(top_next)

    st.generate_normals()
    return st.commit()


func _create_flag_mesh(width: float, height: float) -> ArrayMesh:
    """Create a rectangular flag mesh (simple quad)."""
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    # Flag quad vertices (vertical plane facing +X)
    # Bottom-left
    st.set_normal(Vector3(0, 0, 1))
    st.set_uv(Vector2(0, 1))
    st.add_vertex(Vector3(0, 0, 0))

    # Bottom-right
    st.set_normal(Vector3(0, 0, 1))
    st.set_uv(Vector2(1, 1))
    st.add_vertex(Vector3(width, 0, 0))

    # Top-right
    st.set_normal(Vector3(0, 0, 1))
    st.set_uv(Vector2(1, 0))
    st.add_vertex(Vector3(width, height, 0))

    # Top-left
    st.set_normal(Vector3(0, 0, 1))
    st.set_uv(Vector2(0, 0))
    st.add_vertex(Vector3(0, height, 0))

    # Two triangles to form quad
    # Triangle 1 (bottom-left, bottom-right, top-right)
    st.add_index(0)
    st.add_index(1)
    st.add_index(2)

    # Triangle 2 (bottom-left, top-right, top-left)
    st.add_index(0)
    st.add_index(2)
    st.add_index(3)

    return st.commit()
