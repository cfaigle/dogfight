@tool
class_name BuildingStyleDefs
extends Resource

@export var building_styles: Array[BuildingStyle] = []

func ensure_defaults() -> void:
    if building_styles.is_empty():
        building_styles = _create_default_styles()

func get_style(style_id: String) -> BuildingStyle:
    ensure_defaults()
    for s in building_styles:
        if s != null and s.id == style_id:
            return s
    return null

func get_all() -> Array[BuildingStyle]:
    ensure_defaults()
    return building_styles

static func _c8(r: int, g: int, b: int, a: int = 255) -> Color:
    return Color8(r, g, b, a)

func _create_default_styles() -> Array[BuildingStyle]:
    var styles: Array[BuildingStyle] = []

    # --- Medieval / early ---
    styles.append(_make("medieval_hut", "Medieval Hut", "european", "medieval", {
        "roof_color": _c8(88, 60, 44),
        "wall_color": _c8(72, 52, 38),
        "door_color": _c8(46, 34, 26),
        "window_count": 1,
    }))
    styles.append(_make("timber_cabin", "Timber Frame Cabin", "european", "medieval", {
        "roof_color": _c8(96, 64, 44),
        "wall_color": _c8(104, 80, 60),
        "window_count": 2,
    }))
    styles.append(_make("stone_cottage", "Stone Cottage", "european", "medieval", {
        "roof_color": _c8(120, 120, 120),
        "wall_color": _c8(190, 190, 190),
        "door_count": 1,
    }))
    styles.append(_make("blacksmith", "Blacksmith Workshop", "european", "medieval", {
        "roof_color": _c8(64, 64, 64),
        "wall_color": _c8(128, 128, 128),
        "has_chimney": true,
    }))
    styles.append(_make("windmill", "Windmill", "european", "medieval", {
        "roof_color": _c8(235, 235, 235),
        "wall_color": _c8(204, 186, 168),
        "has_blades": true,
    }))
    styles.append(_make("radio_tower", "Radio Tower", "industrial", "modern", {
        "roof_color": _c8(128, 128, 128),
        "wall_color": _c8(100, 100, 100),
        "has_antennas": true,
    }))

    # --- Rural / regional (used in era 1 selection) ---
    styles.append(_make("fjord_house", "Fjord House", "traditional", "scandinavian", {
        "roof_color": _c8(68, 68, 72),
        "wall_color": _c8(204, 186, 168),
        "boat_house": true,
    }))
    styles.append(_make("white_stucco_house", "White Stucco House", "traditional", "mediterranean", {
        "roof_color": _c8(236, 236, 236),
        "wall_color": _c8(210, 196, 180),
        "orange_tiles": true,
    }))
    styles.append(_make("stone_farmhouse", "Stone Farmhouse", "traditional", "mediterranean", {
        "roof_color": _c8(110, 110, 110),
        "wall_color": _c8(104, 80, 60),
        "has_terraced_garden": true,
    }))

    # --- Scandinavian/Nordic (for hamlets) ---
    styles.append(_make("log_chalet", "Log Chalet", "scandinavian", "medieval", {
        "roof_color": _c8(68, 48, 32),
        "wall_color": _c8(92, 64, 44),
        "window_count": 2,
        "wood_type": "log",
    }))
    styles.append(_make("viking_longhouse", "Viking Longhouse", "scandinavian", "medieval", {
        "roof_color": _c8(72, 96, 64),
        "wall_color": _c8(120, 96, 72),
        "long_shape": true,
        "sod_roof": true,
    }))
    styles.append(_make("sauna_building", "Sauna Building", "scandinavian", "medieval", {
        "roof_color": _c8(120, 80, 48),
        "wall_color": _c8(140, 108, 84),
        "window_count": 1,
        "small_size": true,
        "has_stove_pipe": true,
    }))

    # --- Medieval Variants ---
    styles.append(_make("castle_keep", "Castle Keep", "european", "medieval", {
        "roof_color": _c8(80, 80, 80),
        "wall_color": _c8(60, 60, 60),
        "stone_type": "granite",
        "has_turrets": true,
        "fortified": true,
    }))
    styles.append(_make("market_stall", "Market Stall", "european", "medieval", {
        "roof_color": _c8(140, 100, 60),
        "wall_color": _c8(180, 140, 100),
        "small_size": true,
        "commercial": true,
        "canvas_awning": true,
    }))
    styles.append(_make("monastery", "Monastery", "european", "medieval", {
        "roof_color": _c8(100, 100, 100),
        "wall_color": _c8(160, 160, 160),
        "religious": true,
        "stone_type": "sandstone",
        "has_bell_tower": true,
    }))

    # --- Industrial ---
    styles.append(_make("victorian_mansion", "Victorian Mansion", "european", "industrial", {
        "roof_color": _c8(24, 56, 40),
        "wall_color": _c8(104, 80, 60),
        "window_count": 8,
        "has_tower": true,
    }))
    styles.append(_make("factory_building", "Factory Building", "european", "industrial", {
        "roof_color": _c8(72, 72, 72),
        "wall_color": _c8(128, 128, 128),
        "window_count": 10,
    }))
    styles.append(_make("train_station", "Train Station", "european", "industrial", {
        "roof_color": _c8(72, 72, 72),
        "wall_color": _c8(104, 80, 60),
        "has_platform": true,
    }))

    # --- Regional/Industrial Expansion ---
    styles.append(_make("lighthouse", "Lighthouse", "coastal", "industrial", {
        "roof_color": _c8(200, 200, 200),
        "wall_color": _c8(220, 220, 220),
        "tall_shape": true,
        "cylindrical": true,
        "coastal": true,
        "has_light": true,
    }))
    styles.append(_make("warehouse", "Warehouse", "industrial", "industrial", {
        "roof_color": _c8(80, 80, 80),
        "wall_color": _c8(120, 120, 120),
        "large_size": true,
        "industrial": true,
        "loading_dock": true,
    }))
    styles.append(_make("power_station", "Power Station", "industrial", "modern", {
        "roof_color": _c8(60, 60, 60),
        "wall_color": _c8(100, 100, 100),
        "industrial": true,
        "has_towers": true,
        "utility": true,
    }))
    styles.append(_make("gas_station", "Gas Station", "north_american", "modern", {
        "roof_color": _c8(160, 160, 160),
        "wall_color": _c8(200, 200, 200),
        "small_size": true,
        "commercial": true,
        "has_canopy": true,
        "automotive": true,
    }))

    # --- Bonus Styles ---
    styles.append(_make("barn", "Barn", "rural", "traditional", {
        "roof_color": _c8(120, 80, 40),
        "wall_color": _c8(180, 140, 100),
        "large_size": true,
        "agricultural": true,
        "barn_doors": true,
        "loft": true,
    }))
    styles.append(_make("church", "Church", "european", "medieval", {
        "roof_color": _c8(80, 80, 80),
        "wall_color": _c8(160, 160, 160),
        "religious": true,
        "has_steeple": true,
        "stone_type": "limestone",
    }))
    styles.append(_make("school", "School", "north_american", "modern", {
        "roof_color": _c8(120, 120, 120),
        "wall_color": _c8(200, 200, 200),
        "medium_size": true,
        "educational": true,
        "has_playground": true,
        "window_count": 8,
    }))

    # --- Modern ---
    styles.append(_make("trailer_park", "Trailer Park", "north_american", "modern", {
        "roof_color": _c8(120, 120, 120),
        "wall_color": _c8(180, 180, 186),
        "window_count": 3,
    }))
    styles.append(_make("modular_home", "Modular Home", "north_american", "modern", {
        "roof_color": _c8(110, 110, 118),
        "wall_color": _c8(200, 200, 206),
        "window_count": 4,
    }))

    return styles

func _make(style_id: String, display_name: String, culture: String, era: String, props: Dictionary) -> BuildingStyle:
    var s := BuildingStyle.new()
    s.id = style_id
    s.display_name = display_name
    s.culture = culture
    s.era = era
    s.properties = props
    return s