extends Node

# NOTE:
# This script is autoloaded as a singleton `Game` (see project.godot).
# Don't declare class variables that shadow the autoload instance.

# Global runtime + settings store.
# Autoloaded as `Game`.

const SETTINGS_PATH = "user://dogfight_settings.cfg"

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
    "fog_density": 0.00015,
    "fog_sun_scatter": 0.08,
    "random_terrain": true,
    "sim_aero": true,
    "stall_deg": 15.0,
    "aoa_lift_slope": 5.2,
    "cd0": 0.03,
    "induced_drag_k": 0.08,
    "world_seed": -1,
    
    # World generation knobs (1/4 size for faster iteration)
    "terrain_size": 4000.0,
    "terrain_res": 128,  # Changed CTF - 128 was default - I was using 1024
    "terrain_amp": 300.0,
    "terrain_chunk_cells": 8,
    "terrain_lod_enabled": true,
    "terrain_lod0_radius": 3250.0,  # Halved for smaller world
    "terrain_lod1_radius": 8000.0,  # Halved for smaller world
    "terrain_lod_update": 0.25,
    "landmark_count": 0,
    # Prop/render variety knobs
    "use_external_assets": false,  # Restored external assets for enhanced buildings
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
    # FOREST CONTROLS - Granular Tree Generation Parameters
    # Forest Patches (Primary Tree System)
    "forest_patch_count": 30,                   # Number of forest patches
    "forest_patch_trees_per_patch": 80,          # Target trees per patch (max if they fit)
    "forest_patch_radius_min": 180.0,            # Minimum patch radius (meters)
    "forest_patch_radius_max": 520.0,            # Maximum patch radius (meters)
    "forest_patch_placement_attempts": 50,       # Placement attempts before giving up per patch
    "forest_patch_placement_buffer": 250.0,      # Distance from settlements

    # Random Filler Trees (Scattered between features)
    "random_tree_count": 1000,                   # Individual scattered trees (filler)
    "random_tree_clearance_buffer": 50.0,        # Distance from all features
    "random_tree_slope_limit": 55.0,             # Maximum slope allowed
    "random_tree_placement_attempts": 10,         # Attempts per tree before skipping

    # Settlement Urban Trees
    "settlement_tree_count_per_building": 0.2,    # Average trees per building (subtle)
    "urban_tree_buffer_distance": 80.0,          # Min distance from buildings
    "park_tree_density": 6,                      # Trees per park area unit
    "roadside_tree_spacing": 70.0,               # Spacing along roads

    # Biome-Specific Tree Distribution (for future asset variety)
    "forest_biome_tree_types": {
        "forest": {"conifer": 0.7, "broadleaf": 0.3, "palm": 0.0},
        "grassland": {"conifer": 0.1, "broadleaf": 0.8, "palm": 0.0},
        "wetland": {"conifer": 0.2, "broadleaf": 0.6, "palm": 0.0},
        "farm": {"conifer": 0.1, "broadleaf": 0.7, "palm": 0.0},
        "beach": {"conifer": 0.0, "broadleaf": 0.1, "palm": 0.9},
        "desert": {"conifer": 0.0, "broadleaf": 0.1, "palm": 0.0},
        "rock": {"conifer": 0.1, "broadleaf": 0.0, "palm": 0.0},
        "snow": {"conifer": 0.9, "broadleaf": 0.1, "palm": 0.0},
        "tundra": {"conifer": 0.6, "broadleaf": 0.2, "palm": 0.0},
        "ocean": {"conifer": 0.0, "broadleaf": 0.0, "palm": 0.0}
    },

    # Tree Rendering (No In-Game Adjustment)
    "use_external_tree_assets": true,            # Load external tree models
    "tree_lod_distance": 200.0,                  # Distance for LOD switching
    "tree_max_instances_per_mesh": 8000,         # Performance limit per MultiMesh
    "tree_debug_metrics": true,                  # Show tree generation metrics

    # Destructible Trees (Combat-Enabled Trees with Collision/Damage)
    "destructible_tree_count": 2000,             # Number of damageable trees (was 500)
    "destructible_tree_area_radius": 2000.0,     # Radius for destructible tree placement (was 1000.0)

    # Legacy Parameters (Removed - replaced above)
    # "tree_count": 10,                          # REPLACED by forest_patch_trees_per_patch
    # "forest_patches": 10,                      # REPLACED by forest_patch_count
    "river_count": 700,
    "river_source_min": 50.0,
    "town_count": 200,
    "hamlet_count": 800,
    "city_buildings": 1000,
    "field_patches": 400,
    "farm_sites": 400,
    "industry_sites": 200,
    "pond_count": 100,
    "beach_shacks": 200,
    "peaceful_mode": false,
    "enable_target_lock": true,

    # Visual Effects Toggles (for debugging GPU load)
    "enable_muzzle_flash": true,        # Muzzle flash particles (300 particles/shot @ 2 guns)
    "enable_impact_sparks": false,       # Impact spark explosions (2,400 particles/hit)
    # CHANGED - CTF - this cause GPU freeze but did work until then:
    "enable_smoke_trails": false,        # Smoke trails on hits (320 particles/hit - HEAVY!)
    "enable_bullet_hit_effects": true,  # Material-specific debris (sparks/wood/dust/leaves)
    "enable_hit_sounds": true,          # Audio players for impact sounds
    "enable_missile_effects": true,     # Missile explosion effects (smoke/debris/sparks)
    "enable_moskva_fire": true,         # Moskva cruiser fire effects (~100 particles when damaged)
    "enable_moskva_smoke": true,        # Moskva cruiser smoke effects (~90 particles when damaged)

    # Particle Budget System (prevents GPU freeze from accumulation)
    "max_active_muzzle_flashes": 30,      # Max muzzle flash nodes at once
    "max_active_impact_effects": 30,      # Max impact effect nodes at once
    "max_total_particle_budget": 2000,     # Max total particles across all systems
    "enable_particle_budget": true,        # Master toggle for budget system
    "particle_budget_priority": "newest",  # "newest" or "oldest" (which to keep when over budget)
    "particle_quality": "low",          # "low", "medium", "high", "ultra"

    # CTF - Lakes are currently disabled - they are cool but currently broken
    # CTF - They make giant disks and do not carve right but do populate etc
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

## Apply particle quality preset
func apply_particle_quality_preset(quality: String) -> void:
    match quality:
        "low":
            settings["max_active_muzzle_flashes"] = 150
            settings["max_active_impact_effects"] = 50
            settings["max_total_particle_budget"] = 4000
            settings["enable_muzzle_flash"] = true
            settings["enable_impact_sparks"] = false
            settings["enable_smoke_trails"] = false
            settings["enable_bullet_hit_effects"] = true
        "medium":
            settings["max_active_muzzle_flashes"] = 300
            settings["max_active_impact_effects"] = 100
            settings["max_total_particle_budget"] = 8000
            settings["enable_muzzle_flash"] = true
            settings["enable_impact_sparks"] = false
            settings["enable_smoke_trails"] = false
            settings["enable_bullet_hit_effects"] = true
        "high":
            settings["max_active_muzzle_flashes"] = 600
            settings["max_active_impact_effects"] = 200
            settings["max_total_particle_budget"] = 15000
            settings["enable_muzzle_flash"] = true
            settings["enable_impact_sparks"] = true
            settings["enable_smoke_trails"] = false
            settings["enable_bullet_hit_effects"] = true
        "ultra":
            settings["max_active_muzzle_flashes"] = 1000
            settings["max_active_impact_effects"] = 400
            settings["max_total_particle_budget"] = 25000
            settings["enable_muzzle_flash"] = true
            settings["enable_impact_sparks"] = true
            settings["enable_smoke_trails"] = true
            settings["enable_bullet_hit_effects"] = true

    save_settings()