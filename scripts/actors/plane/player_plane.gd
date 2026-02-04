extends "res://scripts/actors/plane/plane.gd"

# Player controls.
# Trackpad-friendly mouse flight has 3 modes (cycle with F6):
#   POS    - holdable "virtual stick" (mouse position / virtual cursor)
#   RATE   - rate-style with spring to center
#   HYBRID - POS pitch + RATE roll
#
# Keys:
#   W/S throttle up/down
#   Q/E yaw
#   Arrow/WASD pitch/roll (also works)
#   Tab toggle mouse capture
#   C recenter stick
#   F6 cycle control mode

var _mouse_rel := Vector2.ZERO
var _last_mouse_pos := Vector2.ZERO
var _have_last_mouse_pos := false

var _invert_y := false

enum ControlMode { POS, RATE, HYBRID }
var _ctrl_mode := ControlMode.POS

var _pos_ref := Vector2.ZERO
var _have_pos_ref := false
var _virt_cursor := Vector2.ZERO

var _rate_stick := Vector2.ZERO
var _stick_sm := Vector2.ZERO

var _stick_return := 8.0
var _stick_smooth := 14.0
var _stick_radius_frac := 0.35
var _ignore_mouse_time := 0.0

var _dbg_text: String = ""
var _ctrl_dbg_t: float = 0.0


func _ready() -> void:
    is_player = true
    super()
    
    # Add to player group for weapon system to detect player
    add_to_group("player")
    
    # Ensure afterburner input action exists and is properly mapped
    if not InputMap.has_action("afterburner"):
        InputMap.add_action("afterburner")
    
    # Clear existing events and add new ones
    InputMap.action_erase_events("afterburner")
    
    # Add Shift key event
    var shift_event = InputEventKey.new()
    shift_event.keycode = KEY_SHIFT
    InputMap.action_add_event("afterburner", shift_event)
    
    # Also add Z key as backup for afterburner
    var z_event = InputEventKey.new()
    z_event.keycode = KEY_Z
    InputMap.action_add_event("afterburner", z_event)
    
    print("DEBUG: Afterburner input action configured with keys: Shift and Z")

    _invert_y = bool(Game.settings.get("invert_y", false))
    _stick_return = float(Game.settings.get("mouse_recenter", 8.0))
    _stick_smooth = float(Game.settings.get("mouse_smooth", 14.0))
    _stick_radius_frac = float(Game.settings.get("mouse_stick_radius_frac", 0.35))
    _ctrl_mode = int(Game.settings.get("ctrl_mode", ControlMode.POS))

    # Default to visible for trackpads; Tab switches to captured (relative) mode.
    var cap_start := bool(Game.settings.get("mouse_capture_on_start", false))
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if cap_start else Input.MOUSE_MODE_VISIBLE)

    _recenter_stick(true)


func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _mouse_rel += event.relative

    if event is InputEventKey:
        if event.pressed and not event.echo:
            match event.keycode:
                KEY_F6:
                    _cycle_control_mode()
                    return
                KEY_C:
                    _recenter_stick()
                    return
                KEY_ESCAPE:
                    # Only steal ESC when captured (otherwise let the game handle pause/menu).
                    if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
                        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
                        _recenter_stick(true)
                        return
                KEY_SHIFT:
                    # print("DEBUG: Shift key pressed directly!")
                    afterburner = true
                    return
                KEY_Z:
                    # Test with Z key as alternative afterburner
                    # print("DEBUG: Z key pressed - testing afterburner!")
                    afterburner = true
                    return
        elif not event.pressed:
            # Key release handling
            match event.keycode:
                KEY_SHIFT:
                    # print("DEBUG: Shift key released!")
                    afterburner = false
                    return
                KEY_Z:
                    # print("DEBUG: Z key released - afterburner off!")
                    afterburner = false
                    return


func _physics_process(dt: float) -> void:
    gun_trigger = Input.is_action_pressed("fire_gun")
    missile_trigger = Input.is_action_pressed("fire_missile")
    # print("DEBUG: Input states - gun_trigger: ", gun_trigger, " missile_trigger: ", missile_trigger)
    _read_input(dt)
    super(dt)

    # Handle target cycling
    if Input.is_action_just_pressed("target_next"):
        _cycle_target()

    if bool(Game.settings.get("show_debug", false)):
        _ctrl_dbg_t += dt
        if _ctrl_dbg_t > 0.25:
            _ctrl_dbg_t = 0.0
            _dbg_text = _make_debug_text()
            # print(_dbg_text)


func _read_input(dt: float) -> void:
    # --- weapons / throttle ---
    var throttle_rate := float(Game.settings.get("throttle_rate", 0.6))
    throttle = clampf(throttle + Input.get_axis("throttle_down", "throttle_up") * dt * throttle_rate, 0.0, 1.0)
    afterburner = Input.is_action_pressed("afterburner")
    # Debug afterburner input
    if afterburner:
        # print("DEBUG: Afterburner engaged!")
        pass
    gun_trigger = Input.is_action_pressed("fire_gun")
    missile_trigger = Input.is_action_just_pressed("fire_missile")

    # --- keyboard assists ---
    var kb_pitch := Input.get_axis("pitch_down", "pitch_up")   # down->+ (nose up)
    var kb_roll  := Input.get_axis("roll_right", "roll_left")
    var kb_yaw   := Input.get_axis("yaw_right", "yaw_left")

    # --- mouse stick ---
    var cap: bool = is_mouse_captured()

    # Gather rel (captured provides relative; visible cursor adds cursor delta).
    var rel := _mouse_rel
    _mouse_rel = Vector2.ZERO

    if _ignore_mouse_time > 0.0:
        _ignore_mouse_time -= dt
        rel = Vector2.ZERO

    var cursor := get_viewport().get_mouse_position()
    if not cap:
        if not _have_last_mouse_pos:
            _last_mouse_pos = cursor
            _have_last_mouse_pos = true
        rel += (cursor - _last_mouse_pos)
        _last_mouse_pos = cursor

    # Full deflection radius in pixels.
    var vp := get_viewport().get_visible_rect().size
    var r_px: float = max(120.0, min(vp.x, vp.y) * _stick_radius_frac * 0.5)

    # POS: "cursor stick" (absolute cursor position around screen center).
    # - Cursor stays visible and you steer by moving it away from center.
    # - Press C to recenter (warps cursor to center).
    var stick_pos := Vector2.ZERO
    if _ctrl_mode == ControlMode.POS:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        var rect := get_viewport().get_visible_rect()
        var center := rect.size * 0.5
        _pos_ref = center
        _have_pos_ref = true

        var d: Vector2 = cursor - center
        # Deadzone helps trackpads
        if d.length() < r_px * 0.06:
            d = Vector2.ZERO
        stick_pos = (d / r_px).limit_length(1.0)
    else:
        # Legacy POS behavior for captured/other modes (kept for safety)
        if cap:
            _virt_cursor += rel
            _virt_cursor.x = clampf(_virt_cursor.x, -r_px, r_px)
            _virt_cursor.y = clampf(_virt_cursor.y, -r_px, r_px)
            stick_pos = _virt_cursor / r_px
        else:
            if not _have_pos_ref:
                _pos_ref = cursor
                _have_pos_ref = true
            stick_pos = ((cursor - _pos_ref) / r_px).limit_length(1.0)
            if abs(stick_pos.x) > 0.98 or abs(stick_pos.y) > 0.98:
                _pos_ref = _pos_ref.lerp(cursor, 0.25)

    # RATE: spring to center
    var stick_rate := _rate_stick
    if rel.length() > 0.01:
        stick_rate += rel / r_px
    stick_rate.x = clampf(stick_rate.x, -1.0, 1.0)
    stick_rate.y = clampf(stick_rate.y, -1.0, 1.0)

    if rel.length() < 0.5:
        stick_rate = stick_rate.move_toward(Vector2.ZERO, _stick_return * dt)
    _rate_stick = stick_rate

    # Select active stick
    var stick_target := Vector2.ZERO
    match _ctrl_mode:
        ControlMode.POS:
            stick_target = stick_pos
        ControlMode.RATE:
            stick_target = stick_rate
        ControlMode.HYBRID:
            stick_target = Vector2(stick_rate.x, stick_pos.y)

    # Smooth to tame trackpad jitter and prevent death-spiral oscillations.
    var a := clampf(_stick_smooth * dt, 0.0, 1.0)
    _stick_sm = _stick_sm.lerp(stick_target, a)

    # Map to aircraft controls:
    # Screen Y+: down. We want "pull back (down) => pitch up".
    var mouse_pitch := (_stick_sm.y if not _invert_y else -_stick_sm.y)
    var mouse_roll := _stick_sm.x

    # Blend: mouse is primary; keyboard adds a bit.
    in_roll = clampf(mouse_roll + kb_roll * 0.55, -1.0, 1.0)
    in_pitch = clampf(mouse_pitch + kb_pitch * 0.55, -1.0, 1.0)

    # Coordinated-turn assist: add a little yaw when banking (unless explicitly yawing).
    var yaw_assist := 0.0
    if absf(kb_yaw) < 0.05:
        yaw_assist = -in_roll * 0.18
    in_yaw = clampf(kb_yaw + yaw_assist, -1.0, 1.0)


func _cycle_control_mode() -> void:
    _ctrl_mode = (_ctrl_mode + 1) % 3
    Game.settings["ctrl_mode"] = _ctrl_mode
    _recenter_stick()


func _recenter_stick(hard: bool = false) -> void:
    # In POS mode we treat the *screen center* as stick neutral.
    # Optional warp keeps the cursor from wandering to screen edges on trackpads.
    var rect := get_viewport().get_visible_rect()
    var center := rect.size * 0.5

    _pos_ref = center
    _have_pos_ref = true
    _virt_cursor = Vector2.ZERO
    _rate_stick = Vector2.ZERO
    _stick_sm = Vector2.ZERO
    _ignore_mouse_time = 0.15

    if hard:
        Input.warp_mouse(center)

func is_mouse_captured() -> bool:
    return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

func _make_debug_text() -> String:
    var spd: float = linear_velocity.length()
    var alt: float = global_position.y
    var cap: bool = is_mouse_captured()
    # stick is exposed as _stick_sm (smoothed) in -1..1
    var stick: Vector2 = _stick_sm
    var mode_s := "POS"
    match _ctrl_mode:
        ControlMode.POS: mode_s = "POS"
        ControlMode.RATE: mode_s = "RATE"
        ControlMode.HYBRID: mode_s = "HYB"
    return "[CTRL DBG] mode %s spd %.1f alt %.0f thr %.2f cap %s stick(%.2f,%.2f) in(p/r/y) %.2f %.2f %.2f a/b(deg) %.1f %.1f" % [
        mode_s, spd, alt, throttle, str(cap),
        stick.x, stick.y,
        in_pitch, in_roll, in_yaw,
        rad_to_deg(dbg_alpha), rad_to_deg(dbg_beta)
    ]


# --- HUD helper methods -------------------------------------------------------
# HUD asks for these by name via has_method(), so keep them stable.

func get_speed() -> float:
    return linear_velocity.length()

func get_altitude() -> float:
    return global_position.y

func get_control_mode_name() -> String:
    match _ctrl_mode:
        ControlMode.POS:
            return "POS"
        ControlMode.RATE:
            return "RATE"
        ControlMode.HYBRID:
            return "HYB"
    return "POS"

func get_stick() -> Vector2:
    return _stick_sm

func get_flight_debug_text() -> String:
    return _make_debug_text()
