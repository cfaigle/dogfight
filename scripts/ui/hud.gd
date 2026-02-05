extends CanvasLayer

# HUD is created by code (Main.gd). It is self-contained and doesn't rely on global script classes.
const FontManagerScript = preload("res://scripts/util/font_manager.gd")

var _root: Control
var _lbl_speed: Label
var _lbl_alt: Label
var _lbl_blank_1: Label
var _lbl_blank_2: Label
var _lbl_score: Label
var _lbl_wave: Label
var _lbl_hp: Label
var _lbl_target: Label
var _lbl_target_dist: Label
# var _lbl_dbg: Label

var _ctrl_panel: MarginContainer
var _ctrl_label: Label
var _ctrl_stick: StickIndicator

var _status_panel: PanelContainer
var _blank_label: Label
var _status_flight: Label
var _status_texture: Label
var _status_peaceful: Label

#var _help_panel: ColorRect
var _help_panel: PanelContainer
#var _help_label: Label
var _show_help: bool = true
var _help_t: float = 12.0
var _radar_radius: float = 120.0

var _intro_panel: ColorRect
var _intro_t := 7.5

var _target_ref: WeakRef = null
var _hit_t := 0.0

func _ready() -> void:
    _root = Control.new()
    _root.name = "Root"
    _root.anchor_left = 0; _root.anchor_top = 0
    _root.anchor_right = 1; _root.anchor_bottom = 1
    add_child(_root)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE

    # Help panel (bottom-left): Instructions
    _help_panel = PanelContainer.new()    
    _apply_png_panel(_help_panel, "res://assets/dogfight1940_paperclip_page_no_background.png", 0, 0, true)
    _help_panel.name = "HelpPanel"
    _help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Anchor the panel's rect to the parent's bottom-right corner (no stretching)
    _help_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    
    # Force the desired size
    _help_panel.custom_minimum_size = Vector2(1200, 1600)
    _help_panel.size = Vector2(1200, 1600) # (optional but helps if contents fight sizing)
    
    # With anchors pinned (left=right=1, top=bottom=1),
    # offsets become "position relative to that corner".
    # Negative left/top moves the rect left/up by that amount.
    # Right/bottom are the padding from the edge.
    _help_panel.offset_right = -1
    _help_panel.offset_bottom = -1
    _help_panel.offset_left = _help_panel.offset_right - 1200
    _help_panel.offset_top = _help_panel.offset_bottom - 1600
    
    # Make it expand left/up (nice if content changes)
    _help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _help_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
    
    _root.add_child(_help_panel)
    
    var help_panel_margin_container:=MarginContainer.new();
    help_panel_margin_container.add_theme_constant_override("margin_top", 80)
    help_panel_margin_container.add_theme_constant_override("margin_left", 60)
    _help_panel.add_child(help_panel_margin_container)
    
    var help_box := VBoxContainer.new()
    help_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    help_panel_margin_container.add_child(help_box)
    # Use font from font manager if available
    var font = FontManagerScript.get_hud_font()
    
    # Populate the help box from helper method:
    _populate_help_box(help_box, font)

    # Create background panel for upper left displays
    var upper_left_panel = PanelContainer.new()
    _apply_png_panel(upper_left_panel, "res://assets/dogfight1940_status_no_background.png", 24, 12, true)
    upper_left_panel.name = "UpperLeftPanel"
    upper_left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    upper_left_panel.anchor_left = 0.0
    upper_left_panel.anchor_right = 0.0
    upper_left_panel.anchor_top = 0.0
    upper_left_panel.anchor_bottom = 0.0
    upper_left_panel.offset_left = 10.0
    upper_left_panel.offset_right = 10.0 + 380.0
    upper_left_panel.offset_top = 10.0
    upper_left_panel.offset_bottom = 10.0 + 380.0
    _root.add_child(upper_left_panel)

    var ul_container := VBoxContainer.new()
    ul_container.set_alignment(BoxContainer.ALIGNMENT_BEGIN)
    ul_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    upper_left_panel.add_child(ul_container)

    _lbl_blank_1 = _mk_label_bigger(Vector2(0, 0),  "")
    _lbl_blank_2 = _mk_label_bigger(Vector2(0, 0),  "")
    _lbl_score = _mk_label_bigger(Vector2(0, 0),  "     SCORE:  000")
    _lbl_hp    = _mk_label_bigger(Vector2(0, 0),  "   HEALTH:  000")
    _lbl_speed = _mk_label_bigger(Vector2(0, 0),  "     SPEED:  000")
    _lbl_alt   = _mk_label_bigger(Vector2(0, 0),  "          ALT:  000")
    _lbl_wave  = _mk_label_bigger(Vector2(0, 0),  "       WAVE:  000")
    _lbl_target = _mk_label_bigger(Vector2(0, 0), "   TARGET:     ")
    _lbl_target_dist = _mk_label_bigger(Vector2(0, 0), "       DIST:  000")
    # Add all labels to the container
    ul_container.add_child(_lbl_blank_1)
#    ul_container.add_child(_lbl_blank_2)
    ul_container.add_child(_lbl_score)
    ul_container.add_child(_lbl_hp)
    ul_container.add_child(_lbl_speed)
    ul_container.add_child(_lbl_alt)
    ul_container.add_child(_lbl_wave)
    ul_container.add_child(_lbl_target)
    ul_container.add_child(_lbl_target_dist)
#    ul_container.add_child(_lbl_dbg)

    var ret := Reticle.new()
    ret.name = "Reticle"
    _root.add_child(ret)
    ret.anchor_left = 0; ret.anchor_top = 0
    ret.anchor_right = 1; ret.anchor_bottom = 1
    ret.position = Vector2.ZERO
    ret.mouse_filter = Control.MOUSE_FILTER_IGNORE

    _build_intro_panel()

    # Status panel (upper-right): flight/control mode + texture mode (F7)
    _status_panel = PanelContainer.new()
    _apply_png_panel(_status_panel, "res://assets/dogfight1940_orders_no_background.png", 0, 0, true)
    _status_panel.name = "StatusPanel"
    _status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_panel.anchor_left = 0.0
    _status_panel.anchor_right = 0.0
    _status_panel.anchor_top = 0.0
    _status_panel.anchor_bottom = 0.0
    _status_panel.offset_left = 2900.0
    _status_panel.offset_right = 2900.0 + 510.0
    _status_panel.offset_top = 10.0
    _status_panel.offset_bottom = 220
    _root.add_child(_status_panel)

    var sb := VBoxContainer.new()
    sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_panel.add_child(sb)

    _blank_label = Label.new()
    _blank_label.text = " "
    _blank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Use font from font manager if available
    if font != null:
        _blank_label.set("theme_override_fonts/font", font)
    _blank_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    _blank_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    _blank_label.add_theme_constant_override("shadow_offset_x", 2)
    _blank_label.add_theme_constant_override("shadow_offset_y", 2)
    _blank_label.add_theme_font_size_override("font_size", 42)
    sb.add_child(_blank_label)

    _status_flight = Label.new()
    _status_flight.text = "    FLIGHT MODE:"
    _status_flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Use font from font manager if available
    if font != null:
        _status_flight.set("theme_override_fonts/font", font)
    _status_flight.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    _status_flight.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    _status_flight.add_theme_constant_override("shadow_offset_x", 2)
    _status_flight.add_theme_constant_override("shadow_offset_y", 2)
    _status_flight.add_theme_font_size_override("font_size", 42)
    sb.add_child(_status_flight)

    _status_texture = Label.new()
    _status_texture.text = "    COMBAT MODE:"
    _status_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Use font from font manager if available
    if font != null:
        _status_texture.set("theme_override_fonts/font", font)
    _status_texture.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    _status_texture.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    _status_texture.add_theme_constant_override("shadow_offset_x", 2)
    _status_texture.add_theme_constant_override("shadow_offset_y", 2)
    _status_texture.add_theme_font_size_override("font_size", 42)
    sb.add_child(_status_texture)

    _status_peaceful = Label.new()
    _status_peaceful.text = "    TARGET LOCK:"
    _status_peaceful.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Use font from font manager if available
    if font != null:
        _status_peaceful.set("theme_override_fonts/font", font)
    _status_peaceful.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    _status_peaceful.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    _status_peaceful.add_theme_constant_override("shadow_offset_x", 2)
    _status_peaceful.add_theme_constant_override("shadow_offset_y", 2)
    _status_peaceful.add_theme_font_size_override("font_size", 42)
    sb.add_child(_status_peaceful)


    # Control mode + stick indicator (trackpad-friendly)
    _ctrl_panel = MarginContainer.new()
    _ctrl_panel.name = "ControlIndicator"
    _ctrl_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ctrl_panel.anchor_left = 0.0
    _ctrl_panel.anchor_right = 0.0
    _ctrl_panel.anchor_top = 1.0
    _ctrl_panel.anchor_bottom = 1.0
    _ctrl_panel.offset_left = 16.0
    _ctrl_panel.offset_right = 16.0 + 180.0
    _ctrl_panel.offset_top = -16.0 - 140.0
    _ctrl_panel.offset_bottom = -16.0
    _root.add_child(_ctrl_panel)

    var vb := HBoxContainer.new()
    vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ctrl_panel.add_child(vb)

    _ctrl_stick = StickIndicator.new()
    _ctrl_stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ctrl_stick.custom_minimum_size = Vector2(96, 96)
    vb.add_child(_ctrl_stick)

    GameEvents.score_changed.connect(_on_score_changed)
    GameEvents.wave_changed.connect(_on_wave_changed)
    GameEvents.target_changed.connect(_on_target_changed)
    GameEvents.player_health_changed.connect(_on_player_health_changed)
    GameEvents.hit_confirmed.connect(_on_hit_confirmed)

func _build_intro_panel() -> void:
    print('INTRO: BUILDING PANEL')
    _intro_panel = ColorRect.new()
    _intro_panel.color = Color(0, 0, 0, 0)  # Fully transparent
    _intro_panel.anchor_left = 0.5
    _intro_panel.anchor_right = 0.5
    _intro_panel.anchor_top = 1.0
    _intro_panel.anchor_bottom = 1.0
    _intro_panel.offset_left = -400  # Panel width
    _intro_panel.offset_right = 400  # Panel width (800px total)
    _intro_panel.offset_top = -605   # Height for logo + text (adjusted to reach bottom)
    _intro_panel.offset_bottom = -5  # Align to bottom of screen
    _intro_panel.pivot_offset = Vector2(400, 303)  # Center pivot (adjusted for new height)
    _root.add_child(_intro_panel)

    # Create a VBoxContainer to arrange logo and text vertically
    var vbox := VBoxContainer.new()
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    vbox.anchor_left = 0
    vbox.anchor_top = 0
    vbox.anchor_right = 1
    vbox.anchor_bottom = 1
    vbox.offset_left = 0
    vbox.offset_top = 20  # Top margin
    vbox.offset_right = 0
    vbox.offset_bottom = -10  # Bottom margin (closer to bottom edge)
    vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _intro_panel.add_child(vbox)
    print('INTRO: BOX ADDED TO INTRO')
    # Load the logo texture
    var logo_img = load("res://assets/dogfight1940_label2_no_background.png") as Texture2D
    print('INTRO: LOGO LOADED')
    if logo_img != null:
        print('INTRO: LOGO NOT NULL')
        # Add the logo texture
        var logo_texture := TextureRect.new()
        logo_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Scale texture to fit control size
        logo_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        logo_texture.texture = logo_img
        logo_texture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        logo_texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        # Set size to match texture's 3:2 aspect ratio (750x500)
#        logo_texture.custom_minimum_size = Vector2(750, 500)
        logo_texture.custom_minimum_size = Vector2(718, 300)
        vbox.add_child(logo_texture)
        print('INTRO: LOGO TEXTURE ADDED')
    else:
        print('INTRO: LOGO WAS NULL')
        # Fallback if image doesn't load - create a label with text
        var fallback_label = Label.new()
        fallback_label.text = "MISSING LOGO: dogfight1940_title.png"
        fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        fallback_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        vbox.add_child(fallback_label)
        print('INTRO: LOGO FALLBACK ADDED')

    # Add the FaigleLabs text
    var title := Label.new()
    title.text = "FaigleLabs"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    title.custom_minimum_size = Vector2(0, 45)  # Ensure minimum height for font_size=32

    # Use font from font manager if available (same as status panel)
    var font = FontManagerScript.get_hud_font()
    if font != null:
        title.set("theme_override_fonts/font", font)
    title.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    title.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    title.add_theme_constant_override("shadow_offset_x", 2)
    title.add_theme_constant_override("shadow_offset_y", 2)
    title.add_theme_font_size_override("font_size", 40)
    vbox.add_child(title)
    print('INTRO: TITLE ADDED')

# Example: build the help text labels inside help_box
func _populate_help_box(help_box: Control, font: Font) -> void:
    var help_lines: Array[String] = [
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "Flight Controls",
        "- Mouse Movement - Pitch and Roll",
        "- W/S - Throttle Up/Down",
        "- Q/E - Yaw left/right",
        "- A/D - Roll left/right",
        "",
        "Combat Controls",
        "- Left Mouse Click / Space - Fire guns",
        "- Right Mouse Click / Up Arrow - Fire missiles",
        "- Shift - Lock target",
        "- Left Arrow - Cycle to next target",
        "",
        "System Controls",
        "- ESC / P - Pause game",
        "- H - Toggle help display",
        "",
        "Function Keys (Debug/Developer)",
        "- F2 - New world (regenerate with seed)",
        "- F3 - Regenerate world (same seed)",
        "- F4 - Toggle combat/peaceful mode",
        "- F6 - Cycle control mode (alternate flight modes)",
        "- F7 - Toggle textures (external/internal assets)",
        "- F8 - Toggle building labels",
        "- F9 - Toggle target lock on/off",
        "- C - Recenter stick (when mouse is captured)",
        "",
        "Additional Controls",
        "- Shift - Afterburner",
    ]

    # (Optional) Clear existing labels first
    for child in help_box.get_children():
        child.queue_free()

    for line in help_lines:
        # Blank line -> add a spacer
        if line.strip_edges() == "":
            var spacer := Control.new()
            spacer.custom_minimum_size = Vector2(0, 10) # vertical gap
            spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
            help_box.add_child(spacer)
            continue

        var lbl := Label.new()
        lbl.text = line
        lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

        # Theme styling (same as your snippet)
        if font != null:
            lbl.set("theme_override_fonts/font", font)
        lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
        lbl.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
        lbl.add_theme_constant_override("shadow_offset_x", 2)
        lbl.add_theme_constant_override("shadow_offset_y", 2)

        # Simple formatting: headers bigger, bullet lines smaller
        var is_header := not line.begins_with("-")
        lbl.add_theme_font_size_override("font_size", 56 if is_header else 42)

        help_box.add_child(lbl)

func _on_score_changed(s: int) -> void:
    _lbl_score.text = "     SCORE:  %03d" % s
    
func _on_wave_changed(w: int) -> void:
    _lbl_wave.text = "         WAVE:  %03d" % w

func _on_target_changed(tgt: Node) -> void:
    var t: Node3D = tgt as Node3D
    _target_ref = weakref(t) if t != null else null

func _on_player_health_changed(hp: float, mx: float) -> void:
#    _lbl_hp.text = "  HEALTH %d/%d" % [int(hp), int(mx)]
    _lbl_hp.text = "   HEALTH:  %03d" % int(hp)

func _on_hit_confirmed(_strength: float) -> void:
    _hit_t = 0.18

func _process(dt: float) -> void:
    if _show_help:
        _help_t = maxf(_help_t - dt, 0.0)
        if _help_t <= 0.0:
            _show_help = false
    if _help_panel:
        _help_panel.visible = _show_help
    var p = Game.player
    if p and p.has_method("get_speed") and p.has_method("get_altitude"):
        _lbl_speed.text = "     SPEED:  %03d" % int(p.get_speed())
        _lbl_alt.text = "          ALT:  %03d" % int(p.get_altitude())
#        if _lbl_dbg:
#            var show_dbg := bool(Game.settings.get("show_debug", false))
#            if show_dbg and p.has_method("get_flight_debug_text"):
#                _lbl_dbg.visible = true
#                _lbl_dbg.text = p.get_flight_debug_text()
#            else:
#                _lbl_dbg.visible = false

    # Status panel update
    if _status_panel and _status_flight and _status_texture and _status_peaceful:
        var flight_mode := "—"
        if p and p.has_method("get_control_mode_name"):
            flight_mode = str(p.get_control_mode_name())
        _status_flight.text = "    FLIGHT MODE:   %s" % flight_mode

        var peaceful: bool = bool(Game.settings.get("peaceful_mode", false))
        _status_texture.text = "    COMBAT MODE:   %s" % ("OFF" if peaceful else "ON")

        var target_lock_enabled: bool = bool(Game.settings.get("enable_target_lock", true))
        _status_peaceful.text = "    TARGET LOCK:    %s" % "ON" if target_lock_enabled else "OFF"

    # Target readout + lead indicator.
    var lead_pos := Vector2.ZERO
    var show_lead := false

    var target: Node3D = null
    if _target_ref != null:
        target = _target_ref.get_ref() as Node3D
    if target == null:
        _lbl_target.text = "   TARGET:"
    elif Game.main_camera and p and p is Node3D:
        var cam := Game.main_camera as Camera3D
        var p3 := p as Node3D
        var d := (target.global_position - p3.global_position).length()
        _lbl_target.text = "   TARGET:  %s" % target.name
        _lbl_target_dist.text = "       DIST:  %03d" % int(d)
        # Time-to-intercept estimate (simple constant-speed lead).
        var tti: float = clampf(d / 520.0, 0.0, 3.0)

        var v = target.get("vel")
        var target_vel: Vector3 = Vector3.ZERO
        if typeof(v) == TYPE_VECTOR3:
            target_vel = v

        var pred: Vector3 = target.global_position + target_vel * tti
        var sp: Vector2 = cam.unproject_position(pred)
        if sp.x > 0 and sp.x < get_viewport().get_visible_rect().size.x and sp.y > 0 and sp.y < get_viewport().get_visible_rect().size.y:
            lead_pos = sp
            show_lead = true

    # Draw each frame.
    var r = _root.get_node_or_null("Reticle")
    if r:
        r.target = target
        r.lead_pos = lead_pos
        r.show_lead = show_lead
        r.hit_flash = _hit_t
        r.queue_redraw()

func _mk_label(pos: Vector2, txt: String) -> Label:
    var l := Label.new()
    l.text = txt
    l.position = pos
    # Use font from font manager if available
    var font = FontManagerScript.get_hud_font()
    if font != null:
        l.set("theme_override_fonts/font", font)
    l.add_theme_color_override("font_color", Color(0.75, 1.0, 0.95, 0.92))
    l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
    l.add_theme_constant_override("shadow_offset_x", 2)
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.add_theme_font_size_override("font_size", 32)
    _root.add_child(l)
    return l

func _mk_label_bigger(pos: Vector2, txt: String) -> Label:
    var lbl := Label.new()
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    
    lbl.text = txt
    lbl.position = pos
    # Use font from font manager if available
    
    var font = FontManagerScript.get_hud_font()
    # Theme styling (same as your snippet)
    if font != null:
        lbl.set("theme_override_fonts/font", font)
    lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.9))
    lbl.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1, 0.9))
    lbl.add_theme_constant_override("shadow_offset_x", 2)
    lbl.add_theme_constant_override("shadow_offset_y", 2)

    # Simple formatting: headers bigger, bullet lines smaller
    var is_header := not txt.begins_with("-")
    lbl.add_theme_font_size_override("font_size", 42 if is_header else 36)

    return lbl
    
func _apply_png_panel(panel: PanelContainer, tex_path: String, border_px: float = 24.0, padding_px: float = 12.0, draw_center: bool = true) -> void:
    var tex := load(tex_path) as Texture2D
    if tex == null:
        push_warning("HUD: couldn't load panel texture: %s" % tex_path)
        return

    var sb := StyleBoxTexture.new()
    sb.texture = tex

    # 9-slice border thickness (in source texture pixels)
    sb.texture_margin_left = border_px
    sb.texture_margin_right = border_px
    sb.texture_margin_top = border_px
    sb.texture_margin_bottom = border_px

    # If your PNG center is transparent already, leaving this true is fine.
    # If you ONLY want the border and guaranteed transparent center, set draw_center = false.
    sb.draw_center = draw_center

    # Padding so text doesn't touch the border.
    sb.set_content_margin(SIDE_LEFT, padding_px)
    sb.set_content_margin(SIDE_RIGHT, padding_px)
    sb.set_content_margin(SIDE_TOP, padding_px)
    sb.set_content_margin(SIDE_BOTTOM, padding_px)

    panel.add_theme_stylebox_override("panel", sb)


class StickIndicator extends Control:
    var stick: Vector2 = Vector2.ZERO

    func _draw() -> void:
        var r: float = minf(size.x, size.y) * 0.5 - 4.0
        r = maxf(r, 10.0)
        var c := size * 0.5
        draw_circle(c, r, Color(1, 1, 1, 0.13))
        draw_circle(c, 2.0, Color(1, 1, 1, 0.35))
        var p: Vector2 = c + Vector2(stick.x, stick.y) * r
        draw_circle(p, 4.0, Color(1.0, 0.85, 0.2, 0.9))

class Reticle extends Control:
    var radar_radius: float = 120.0
    var target: Node3D
    var lead_pos := Vector2.ZERO
    var show_lead := false
    var hit_flash := 0.0

    func _draw() -> void:
        var vp := get_viewport_rect().size
        var center := vp * 0.5
        # --- Artificial horizon + radar (orientation helpers) ---------------
        var p_obj = Game.player
        var p: Node3D = null
        if is_instance_valid(p_obj):
            p = p_obj as Node3D

        # Artificial horizon (roll/pitch)
        if p:
            var roll: float = float(p.global_rotation.z)
            var pitch: float = float(p.global_rotation.x)
            pitch = clampf(pitch, -1.0, 1.0)
            var yoff: float = pitch * 120.0

            draw_set_transform(center + Vector2(0, yoff), -roll, Vector2.ONE)
            var hc := Color(0.10, 0.95, 1.0, 0.55)
            draw_line(Vector2(-260, 0), Vector2(260, 0), hc, 2.0)
            for t in [-120, -80, -40, 40, 80, 120]:
                draw_line(Vector2(-24, t), Vector2(24, t), hc, 1.0)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

        # Radar (enemy relative direction)
        var radar_center := Vector2(96, vp.y - 96)
        var rr: float = radar_radius
        draw_circle(radar_center, rr, Color(0, 0, 0, 0.25))
        draw_arc(radar_center, rr, 0.0, TAU, 64, Color(0.10, 0.95, 1.0, 0.35), 1.5)
        # Controls overlay (F3 toggles debug)
        if bool(Game.settings.get("show_debug", false)) and p:
            var stick_center := Vector2(240, vp.y - 96)
            var sr := 42.0
            draw_circle(stick_center, sr, Color(0, 0, 0, 0.25))
            draw_arc(stick_center, sr, 0.0, TAU, 32, Color(0.10, 0.95, 1.0, 0.25), 1.5)

            var r := float(p.get("in_roll"))
            var pit := float(p.get("in_pitch"))
            var dot := stick_center + Vector2(r, -pit) * sr
            draw_circle(dot, 5.0, Color(0.10, 0.95, 1.0, 0.85))

            var t := clampf(float(p.get("throttle")), 0.0, 1.0)
            var bar_pos := stick_center + Vector2(sr + 18.0, -sr)
            var bar_sz := Vector2(10.0, sr * 2.0)
            draw_rect(Rect2(bar_pos, bar_sz), Color(0, 0, 0, 0.25))
            var fill := Rect2(bar_pos + Vector2(0.0, bar_sz.y * (1.0 - t)), Vector2(bar_sz.x, bar_sz.y * t))
            draw_rect(fill, Color(0.10, 0.95, 1.0, 0.75))
        if p:
            var basis: Basis = p.global_transform.basis
            var enemies := get_tree().get_nodes_in_group("enemies")
            for e in enemies:
                if not (e is Node3D):
                    continue
                var rel3: Vector3 = basis.inverse() * ((e as Node3D).global_position - p.global_position)
                var rel := Vector2(-rel3.x, -rel3.z)
                var scale: float = 0.06
                var p2 := rel * scale
                if p2.length() > rr - 6.0:
                    p2 = p2.normalized() * (rr - 6.0)
                draw_circle(radar_center + p2, 2.8, Color(0.92, 0.45, 0.15, 0.95))
            draw_line(radar_center, radar_center + Vector2(0, -rr + 8.0), Color(0.10, 0.95, 1.0, 0.45), 1.0)


        # Center crosshair.
        var c0 := Color(0.2, 1.0, 0.9, 0.8)
        draw_line(center + Vector2(-10, 0), center + Vector2(-3, 0), c0, 2.0)
        draw_line(center + Vector2( 10, 0), center + Vector2( 3, 0), c0, 2.0)
        draw_line(center + Vector2(0, -10), center + Vector2(0, -3), c0, 2.0)
        draw_line(center + Vector2(0,  10), center + Vector2(0,  3), c0, 2.0)

        # Hit marker (tiny X flash at center).
        if hit_flash > 0.001:
            var a: float = clampf(hit_flash / 0.18, 0.0, 1.0)
            var hc := Color(1.0, 1.0, 1.0, 0.85 * a)
            draw_line(center + Vector2(-12, -12), center + Vector2(-4, -4), hc, 2.0)
            draw_line(center + Vector2( 12, -12), center + Vector2( 4, -4), hc, 2.0)
            draw_line(center + Vector2(-12,  12), center + Vector2(-4,  4), hc, 2.0)
            draw_line(center + Vector2( 12,  12), center + Vector2( 4,  4), hc, 2.0)

        # Lead pip.
        if show_lead:
            draw_circle(lead_pos, 4.5, Color(1.0, 0.35, 0.85, 0.85))

        # Target bracket + lock ring.
        if target == null or not is_instance_valid(target):
            return
        if Game.main_camera == null:
            return

        var cam := Game.main_camera as Camera3D
        if cam == null:
            return
        if cam.is_position_behind(target.global_position):
            return

        var screen_p := cam.unproject_position(target.global_position)
        var d := (target.global_position - cam.global_position).length()
        var s: float = clampf(60.0 * (120.0 / maxf(d, 1.0)), 18.0, 64.0)

        var col := Color(1.0, 0.25, 0.75, 0.92)
        # Corner brackets.
        var k: float = s * 0.42
        draw_line(screen_p + Vector2(-s, -s), screen_p + Vector2(-k, -s), col, 2.0)
        draw_line(screen_p + Vector2(-s, -s), screen_p + Vector2(-s, -k), col, 2.0)

        draw_line(screen_p + Vector2( s, -s), screen_p + Vector2( k, -s), col, 2.0)
        draw_line(screen_p + Vector2( s, -s), screen_p + Vector2( s, -k), col, 2.0)

        draw_line(screen_p + Vector2(-s,  s), screen_p + Vector2(-k,  s), col, 2.0)
        draw_line(screen_p + Vector2(-s,  s), screen_p + Vector2(-s,  k), col, 2.0)

        draw_line(screen_p + Vector2( s,  s), screen_p + Vector2( k,  s), col, 2.0)
        draw_line(screen_p + Vector2( s,  s), screen_p + Vector2( s,  k), col, 2.0)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        var ek := event as InputEventKey
        if ek.keycode == KEY_H:
            _show_help = not _show_help
            if _show_help:
                _help_t = 999.0
