class_name FontManager
extends Resource

## Centralized font management system for the game

# Font resources
static var default_font: Font = null
static var ui_font: Font = null
static var hud_font: Font = null
static var label_font: Font = null

# Initialize fonts
static func initialize_fonts():
    load_fonts()

static func load_fonts():
    print("🔤 FontManager: Starting font loading process...")
    # Try to load custom fonts, fall back to system defaults if not available
    var special_elite_font_path = "res://assets/fonts/Special_Elite/SpecialElite-Regular.ttf"

    # For 3D labels
    if ResourceLoader.exists(special_elite_font_path):
        label_font = load(special_elite_font_path) as Font
        print("🔤 FontManager: Loaded Special Elite font for labels from ", special_elite_font_path)
    else:
        # Use fallback font if custom font doesn't exist
        label_font = ThemeDB.fallback_font
        print("🔤 FontManager: Using fallback font for labels (Special Elite font not found at ", special_elite_font_path, ")")

    # For UI elements, we'll use the Special Elite font as well
    default_font = label_font
    ui_font = label_font
    hud_font = label_font

    print("🔤 FontManager: All fonts loaded successfully")
    print("   - label_font: ", label_font)
    print("   - default_font: ", default_font)
    print("   - ui_font: ", ui_font)
    print("   - hud_font: ", hud_font)

# Public methods to get fonts
static func get_default_font() -> Font:
    if default_font == null:
        load_fonts()
    return default_font

static func get_ui_font() -> Font:
    if ui_font == null:
        load_fonts()
    return ui_font

static func get_hud_font() -> Font:
    if hud_font == null:
        load_fonts()
    return hud_font

static func get_label_font() -> Font:
    if label_font == null:
        load_fonts()
    return label_font