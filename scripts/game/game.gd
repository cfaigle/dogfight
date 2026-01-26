extends Node

# NOTE:
# This script is autoloaded as the singleton `Game` (see project.godot).
# Don't declare `class_name Game` here, otherwise the class name would shadow
# the autoload instance and break calls like `Game.toggle_pause()`.

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
    "mouse_recenter": 8.0,
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
    "fog_density": 0.00045,
    "fog_sun_scatter": 0.28,
    "random_terrain": true,
    "sim_aero": true,
    "stall_deg": 15.0,
    "aoa_lift_slope": 5.2,
    "cd0": 0.03,
    "induced_drag_k": 0.08,
    "world_seed": -1,

    # World generation knobs
    "terrain_size": 8000.0,
    "terrain_res": 1024,
    "terrain_amp": 300.0,
    "terrain_chunk_cells": 32,
    "terrain_lod_enabled": true,
    "terrain_lod0_radius": 6500.0,
    "terrain_lod1_radius": 16000.0,
    "terrain_lod_update": 0.25,
    # Prop/render variety knobs
    "use_external_assets": false,
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
    "tree_count": 80000,
    "forest_patches": 260,
    "river_count": 70,
    "river_source_min": 50.0,
    "town_count": 50,
    "hamlet_count": 140,
    "city_buildings": 12000,
    "field_patches": 220,
    "farm_sites": 900,
    "industry_sites": 80,
    "pond_count": 100,
    "beach_shacks": 2200,
    "peaceful_mode": true
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