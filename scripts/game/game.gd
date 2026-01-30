extends Node

# NOTE:
# This script is autoloaded as a singleton `Game` (see project.godot).
# Don't declare class variables that shadow the autoload instance.

# Global runtime + settings store.
# Autoloaded as `Game`.

const SETTINGS_PATH = "user://neon_dogfight_settings.cfg"

var rng = RandomNumberGenerator.new()

var settings = {
    "mouse_look": true,
    "invert_y": false,
    "mouse_sens": 0.0038,
    "mouse_flight": true,
    "mouse_flight_sens": 0.0040,
    "ctrl_mode": 0,
    "mouse_capture_on_start": false,
    "mouse_stick_radius_frac": 0.35,
    "mouse_recenter":8.0,
    "mouse_smooth": 14.0,
    "mouse_radius_frac": 0.35,
    "mouse_stick_smooth": 14.0,
    "speed_scale": 0.72,
    "turn_scale": 0.72,
    "aim_smoothing": 16.0,
    "auto_level_strength": 1.35,
    "bank_yaw_assist": 0.65,
    "turn_assist": 0.85,
    "min_speed_assist": true,
    "camera_distance": 9.5,
    "camera_height": 2.7,
    "camera_lag": 10.5,
    "fov_base": 72.0,
    "fov_boost": 14.0,
    "shake_gun": 0.08,
    "shake_hit": 0.35,
    "gun_convergence": 420.0,
    "difficulty": 1.0, # 0.6..1.6
    "use_gamepad": true,
    "show_debug": true,
    "fog_density": 0.00025,
    "fog_sun_scatter": 0.18,
    "random_terrain": true,
    "sim_aero": true,
    "stall_deg": 15.0,
    "aoa_lift_slope": 5.2,
    "cd0": 0.03,
    "induced_drag_k": 0.08,
    "world_seed": -1,
    
    # World generation knobs (1/4 size for faster iteration)
    "terrain_size": 6000.0,  # Was 8000-12000, now 6000 for testing
    "terrain_res": 1024,
    "terrain_amp": 300.0,
    "terrain_chunk_cells": 8,
    "terrain_lod_enabled": true,
    "terrain_lod0_radius": 3250.0,  # Halved for smaller world
    "terrain_lod1_radius": 8000.0,  # Halved for smaller world
    "terrain_lod_update": 0.25,
    # Prop/render variety knobs
    "use_external_assets": true,  # Restored external assets for enhanced buildings
    "prop_lod_enabled": true,
    "prop_lod0_radius": 5500.0,
    "prop_lod1_radius": 14000.0,
    "prop_lod_update": 0.35,
    "settlement_variants_near": 12,
    "settlement_variants_mid": 6,
    "settlement_variants_far": 2,
    "beach_shack_variants_near": 4,
    "beach_shack_variants_mid": 2,
    "sea_level": 0.0,
    "tree_count": 100000,
    "forest_patches": 6000,
    "river_count": 700,
    "river_source_min": 50.0,
    "town_count": 100,
    "hamlet_count": 400,
    "city_buildings": 30000,
    "field_patches": 22000,
    "farm_sites": 9000,
    "industry_sites": 800,
    "pond_count": 1000,
    "beach_shacks": 22000,
    "peaceful_mode": false,
    
    # Lake scene parameters
    "lake_scene_percentage": 1.0,  # 100% default, adjustable 0.0-1.0
    "lake_type_weights": {"basic": 0.3, "recreational": 0.3, "fishing": 0.25, "harbor": 0.15},
    "boat_density_per_lake": 0.4,      # Average boats per lake
    "buoy_density_per_radius": 2.0,    # Buoys per 100 units of radius
    "dock_probability": 0.5,           # 50% chance of docks per lake
    "shore_feature_probability": 0.7,  # 70% chance of shore features
    "max_boats_per_lake": 56,
    "max_buoys_per_lake": 20,
    "max_docks_per_lake": 20,
    "lake_scene_lod_distance": 500.0,
    "lake_scene_max_detail_distance": 200.0,
}

var main_camera: Camera3D
var camera_rig: Node
var player: Node
var sea_level: float = 0.0
var ground_height_callable: Callable = Callable()

var is_paused = false

func _ready() -> void:
    rng.randomize()
    load_settings()

func load_settings() -> void:
    var cfg = ConfigFile.new()
    var err = cfg.load(SETTINGS_PATH)
    if err != OK:
        return
    for k in settings.keys():
        if cfg.has_section_key("settings", k):
            settings[k] = cfg.get_value("settings", k)

func save_settings() -> void:
    var cfg = ConfigFile.new()
    for k in settings.keys():
        cfg.set_value("settings", k, settings[k])
    cfg.save(SETTINGS_PATH)

func set_paused(p: bool) -> void:
    is_paused = p
    get_tree().paused = p
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else (Input.MOUSE_MODE_CAPTURED if bool(settings.get("mouse_capture_on_start", false)) else Input.MOUSE_MODE_VISIBLE)

func toggle_pause() -> void:
    set_paused(not is_paused)

func add_camera_shake(amount: float) -> void:
    if camera_rig and camera_rig.has_method("add_shake"):
        camera_rig.add_shake(amount)