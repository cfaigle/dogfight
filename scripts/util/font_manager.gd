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
	# Try to load custom fonts, fall back to system defaults if not available
	var custom_font_path = "res://assets/fonts/custom_font.tres"
	
	# For 3D labels
	if ResourceLoader.exists(custom_font_path):
		label_font = load(custom_font_path) as Font
	else:
		# Use fallback font if custom font doesn't exist
		label_font = ThemeDB.fallback_font
	
	# For UI elements, we'll use the default theme font but could load custom ones
	default_font = ThemeDB.fallback_font
	ui_font = ThemeDB.fallback_font
	hud_font = ThemeDB.fallback_font

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