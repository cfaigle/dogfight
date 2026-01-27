extends CanvasLayer

# HUD is created by code (Main.gd). It is self-contained and doesn't rely on global script classes.

var _root: Control
var _lbl_speed: Label
var _lbl_alt: Label
var _lbl_score: Label
var _lbl_wave: Label
var _lbl_hp: Label
var _lbl_target: Label
var _lbl_dbg: Label

var _ctrl_panel: PanelContainer
var _ctrl_label: Label
var _ctrl_stick: StickIndicator

var _status_panel: PanelContainer
var _status_flight: Label
var _status_texture: Label
var _status_peaceful: Label

var _help_panel: ColorRect
var _help_label: Label
var _show_help: bool = true
var _help_t: float = 12.0
var _radar_radius: float = 70.0

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

    # Quick-start controls hint (press H to toggle)
    _help_panel = ColorRect.new()
    _help_panel.color = Color(0, 0, 0, 0.40)
    _help_panel.anchor_left = 1.0; _help_panel.anchor_right = 1.0
    _help_panel.anchor_top = 1.0; _help_panel.anchor_bottom = 1.0
    _help_panel.offset_right = -20.0
    _help_panel.offset_left = -20.0 - 1000.0
    _help_panel.offset_top = -20.0 - 120.0
    _help_panel.offset_bottom = -20.0
    _root.add_child(_help_panel)

    _help_label = Label.new()
    _help_label.position = Vector2(12, 10)
    _help_label.size = _help_panel.size - Vector2(24, 20)
    _help_label.text = "FLIGHT: Mouse aim  W/S pitch  A/D roll  Q/E yaw  R/F throttle  Shift WEP
WEAPONS: LMB guns  RMB missiles  Tab cycle target  
SYSTEMS: Esc pause  H toggle help  F6 control mode  F7 textures  F2/F3 world
Press H to hide this help"
    _help_label.add_theme_color_override("font_color", Color(1,1,1,0.92))
    _help_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _help_label.add_theme_constant_override("shadow_offset_x", 2)
    _help_label.add_theme_constant_override("shadow_offset_y", 2)
    _help_label.add_theme_font_size_override("font_size", 24)
    _help_panel.add_child(_help_label)


    # Create background panel for upper left displays
    var upper_left_panel = PanelContainer.new()
    upper_left_panel.name = "UpperLeftPanel"
    upper_left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    upper_left_panel.anchor_left = 0.0
    upper_left_panel.anchor_right = 0.0
    upper_left_panel.anchor_top = 0.0
    upper_left_panel.anchor_bottom = 0.0
    upper_left_panel.offset_left = 10.0
    upper_left_panel.offset_right = 10.0 + 280.0
    upper_left_panel.offset_top = 10.0
    upper_left_panel.offset_bottom = 10.0 + 240.0
    _root.add_child(upper_left_panel)

    var ul_container := VBoxContainer.new()
    ul_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    upper_left_panel.add_child(ul_container)

    _lbl_speed = _mk_label_bigger(Vector2(0, 0), "SPD 000")
    _lbl_alt   = _mk_label_bigger(Vector2(0, 0), "ALT 0000")
    _lbl_hp    = _mk_label_bigger(Vector2(0, 0), "HP 000/000")

    _lbl_score = _mk_label_bigger(Vector2(0, 0), "SCORE 0")
    _lbl_wave  = _mk_label_bigger(Vector2(0, 0), "WAVE 1")
    _lbl_target = _mk_label_bigger(Vector2(0, 0), "TARGET —")
    _lbl_target.add_theme_color_override("font_color", Color(1.0, 0.35, 0.85, 0.92))

    _lbl_dbg = _mk_label_bigger(Vector2(0, 0), "")
    _lbl_dbg.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.78))
    _lbl_dbg.add_theme_font_size_override("font_size", 20)

    # Add all labels to the container
    ul_container.add_child(_lbl_speed)
    ul_container.add_child(_lbl_alt)
    ul_container.add_child(_lbl_hp)
    ul_container.add_child(_lbl_score)
    ul_container.add_child(_lbl_wave)
    ul_container.add_child(_lbl_target)
    ul_container.add_child(_lbl_dbg)

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
    _status_panel.name = "StatusPanel"
    _status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_panel.anchor_left = 1.0
    _status_panel.anchor_right = 1.0
    _status_panel.anchor_top = 0.0
    _status_panel.anchor_bottom = 0.0
    _status_panel.offset_right = -14.0
    _status_panel.offset_left = -14.0 - 260.0
    _status_panel.offset_top = 14.0
    _status_panel.offset_bottom = 14.0 + 64.0
    _root.add_child(_status_panel)

    var sb := VBoxContainer.new()
    sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_panel.add_child(sb)

    _status_flight = Label.new()
    _status_flight.text = "FLIGHT —"
    _status_flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_flight.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    _status_flight.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _status_flight.add_theme_constant_override("shadow_offset_x", 2)
    _status_flight.add_theme_constant_override("shadow_offset_y", 2)
    _status_flight.add_theme_font_size_override("font_size", 32)
    sb.add_child(_status_flight)

    _status_texture = Label.new()
    _status_texture.text = "TEX —"
    _status_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_texture.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    _status_texture.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _status_texture.add_theme_constant_override("shadow_offset_x", 2)
    _status_texture.add_theme_constant_override("shadow_offset_y", 2)
    _status_texture.add_theme_font_size_override("font_size", 32)
    sb.add_child(_status_texture)

    _status_peaceful = Label.new()
    _status_peaceful.text = "MODE —"
    _status_peaceful.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _status_peaceful.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    _status_peaceful.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _status_peaceful.add_theme_constant_override("shadow_offset_x", 2)
    _status_peaceful.add_theme_constant_override("shadow_offset_y", 2)
    _status_peaceful.add_theme_font_size_override("font_size", 32)
    sb.add_child(_status_peaceful)


    # Control mode + stick indicator (trackpad-friendly)
    _ctrl_panel = PanelContainer.new()
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

    var vb := VBoxContainer.new()
    vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ctrl_panel.add_child(vb)

    _ctrl_label = Label.new()
    _ctrl_label.text = "CTRL —"
    _ctrl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ctrl_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    _ctrl_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _ctrl_label.add_theme_constant_override("shadow_offset_x", 2)
    _ctrl_label.add_theme_constant_override("shadow_offset_y", 2)
    _ctrl_label.add_theme_font_size_override("font_size", 32)
    vb.add_child(_ctrl_label)

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
    _intro_panel = ColorRect.new()
    _intro_panel.color = Color(0, 0, 0, 0.32)
    _intro_panel.anchor_left = 0.5
    _intro_panel.anchor_right = 0.5
    _intro_panel.anchor_top = 1.0
    _intro_panel.anchor_bottom = 1.0
    _intro_panel.offset_left = -320
    _intro_panel.offset_right = 320
    _intro_panel.offset_top = -146
    _intro_panel.offset_bottom = -14
    _intro_panel.pivot_offset = Vector2(320, 66)
    _root.add_child(_intro_panel)

    var title := Label.new()
    title.text = "FAIGLELABS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.anchor_left = 0; title.anchor_top = 0
    title.anchor_right = 1; title.anchor_bottom = 0
    title.offset_left = 0
    title.offset_right = 0
    title.offset_top = 10
    title.offset_bottom = 50
    title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.9, 0.95))
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    title.add_theme_constant_override("shadow_offset_x", 2)
    title.add_theme_constant_override("shadow_offset_y", 2)
    title.add_theme_font_size_override("font_size", 30)
    _intro_panel.add_child(title)

    var help := Label.new()
    help.text = "Mouse: aim   LMB: guns   RMB: missiles\nW/S: pitch   A/D: roll   Q/E: yaw   R/F: throttle   SHIFT: WEP\nTAB: cycle target   ESC: pause   H: toggle help"
    help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    help.anchor_left = 0; help.anchor_top = 0
    help.anchor_right = 1; help.anchor_bottom = 0
    help.offset_left = 0
    help.offset_right = 0
    help.offset_top = 55
    help.offset_bottom = 115
    help.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
    help.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    help.add_theme_constant_override("shadow_offset_x", 2)
    help.add_theme_constant_override("shadow_offset_y", 2)
    help.add_theme_font_size_override("font_size", 16)
    _intro_panel.add_child(help)

func _on_score_changed(s: int) -> void:
    _lbl_score.text = "SCORE %d" % s

func _on_wave_changed(w: int) -> void:
    _lbl_wave.text = "WAVE %d" % w

func _on_target_changed(tgt: Node) -> void:
    var t: Node3D = tgt as Node3D
    _target_ref = weakref(t) if t != null else null

func _on_player_health_changed(hp: float, mx: float) -> void:
    _lbl_hp.text = "HP %d/%d" % [int(hp), int(mx)]

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
        _lbl_speed.text = "SPD %d" % int(p.get_speed())
        _lbl_alt.text = "ALT %d" % int(p.get_altitude())
        if _lbl_dbg:
            var show_dbg := bool(Game.settings.get("show_debug", false))
            if show_dbg and p.has_method("get_flight_debug_text"):
                _lbl_dbg.visible = true
                _lbl_dbg.text = p.get_flight_debug_text()
            else:
                _lbl_dbg.visible = false

    # Control indicator update
    if _ctrl_panel and _ctrl_label and _ctrl_stick and p and p.has_method("get_control_mode_name") and p.has_method("get_stick"):
        var mode: String = str(p.get_control_mode_name())
        var cap: bool = false
        if p.has_method("is_mouse_captured"):
            cap = bool(p.is_mouse_captured())
        _ctrl_label.text = "CTRL %s  %s" % [mode, ("CAP" if cap else "VIS")]
        _ctrl_stick.stick = p.get_stick()
        _ctrl_stick.queue_redraw()
    # Status panel update
    if _status_panel and _status_flight and _status_texture and _status_peaceful:
        var flight_mode := "—"
        if p and p.has_method("get_control_mode_name"):
            flight_mode = str(p.get_control_mode_name())
        _status_flight.text = "FLIGHT %s (F6)" % flight_mode

        var use_ext: bool = bool(Game.settings.get("use_external_assets", false))
        _status_texture.text = "TEX %s (F7)" % ("EXTERNAL" if use_ext else "BUILT-IN")

        var peaceful: bool = bool(Game.settings.get("peaceful_mode", false))
        _status_peaceful.text = "MODE %s (F4)" % ("PEACEFUL" if peaceful else "COMBAT")
        
        # Add color coding for visual feedback
        if peaceful:
            _status_peaceful.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 0.9))  # Green
        else:
            _status_peaceful.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 0.9))  # Red

    # Target readout + lead indicator.
    var lead_pos := Vector2.ZERO
    var show_lead := false

    var target: Node3D = null
    if _target_ref != null:
        target = _target_ref.get_ref() as Node3D
    if target == null:
        _lbl_target.text = "TARGET -"
    elif Game.main_camera and p and p is Node3D:
        var cam := Game.main_camera as Camera3D
        var p3 := p as Node3D
        var d := (target.global_position - p3.global_position).length()
        _lbl_target.text = "TARGET %s  %dm" % [target.name, int(d)]

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
    l.add_theme_color_override("font_color", Color(0.75, 1.0, 0.95, 0.92))
    l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
    l.add_theme_constant_override("shadow_offset_x", 2)
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.add_theme_font_size_override("font_size", 32)
    _root.add_child(l)
    return l

func _mk_label_bigger(pos: Vector2, txt: String) -> Label:
    var l := Label.new()
    l.text = txt
    l.position = pos
    l.add_theme_color_override("font_color", Color(0.75, 1.0, 0.95, 0.92))
    l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
    l.add_theme_constant_override("shadow_offset_x", 2)
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.add_theme_font_size_override("font_size", 32)
    return l


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
    var radar_radius: float = 70.0
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
                var rel := Vector2(rel3.x, -rel3.z)
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
