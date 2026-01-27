# Peaceful Mode Fixes Implementation Plan

## Issue Summary
The game starts in peaceful mode by default, preventing enemy planes from spawning. Additionally, there's no HUD indicator showing the current peaceful mode status.

## Root Causes
1. **Default Peaceful Mode**: `Game.settings["peaceful_mode"]` defaults to `true` in `game.gd:89`
2. **HUD Missing Indicator**: HUD doesn't display peaceful mode status anywhere
3. **Initial State**: `main.gd` initializes `_peaceful_mode` as `true` (line 62)

## Implementation Plan

### Phase 1: Change Default Settings

#### File: `scripts/game/game.gd`
**Line 89**: Change default peaceful mode setting
```gdscript
# BEFORE:
"peaceful_mode": true,

# AFTER:
"peaceful_mode": false,
```

#### File: `scripts/game/main.gd`
**Line 62**: Change initial peaceful mode state
```gdscript
# BEFORE:
var _peaceful_mode: bool = true

# AFTER:
var _peaceful_mode: bool = false
```

**Line 103**: Change default in settings getter
```gdscript
# BEFORE:
_peaceful_mode = bool(Game.settings.get("peaceful_mode", true))

# AFTER:
_peaceful_mode = bool(Game.settings.get("peaceful_mode", false))
```

### Phase 2: Add Peaceful Mode HUD Indicator

#### File: `scripts/ui/hud.gd`

**Line 30**: Add peaceful mode status variable to class
```gdscript
# AFTER other status label declarations:
var _status_peaceful: Label
```

**Line 130-154**: Add peaceful mode label to status panel
```gdscript
# AFTER _status_texture label creation (around line 154):
_status_peaceful = Label.new()
_status_peaceful.text = "MODE —"
_status_peaceful.mouse_filter = Control.MOUSE_FILTER_IGNORE
_status_peaceful.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
_status_peaceful.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
_status_peaceful.add_theme_constant_override("shadow_offset_x", 2)
_status_peaceful.add_theme_constant_override("shadow_offset_y", 2)
_status_peaceful.add_theme_font_size_override("font_size", 32)
sb.add_child(_status_peaceful)
```

**Line 286-294**: Update status panel logic
```gdscript
# AFTER _status_texture.text line (around line 294):
var peaceful: bool = bool(Game.settings.get("peaceful_mode", false))
_status_peaceful.text = "MODE %s (F4)" % ("PEACEFUL" if peaceful else "COMBAT")

# Optional: Add color coding
if peaceful:
    _status_peaceful.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 0.9))  # Green
else:
    _status_peaceful.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 0.9))  # Red
```

## Testing Procedure

### Step 1: Verify Default Behavior
1. Start the game without pressing any keys
2. **Expected**: Enemy planes should spawn within 1-2 seconds
3. **Expected**: HUD should show "MODE COMBAT (F4)" in upper right

### Step 2: Test Peaceful Mode Toggle
1. Press **F4** to toggle peaceful mode on
2. **Expected**: All existing enemies should be destroyed
3. **Expected**: HUD should show "MODE PEACEFUL (F4)" in green
4. **Expected**: No new enemies should spawn

### Step 3: Test Combat Mode Toggle
1. Press **F4** again to toggle peaceful mode off
2. **Expected**: HUD should show "MODE COMBAT (F4)" in red
3. **Expected**: Enemy waves should start spawning again

### Step 4: Verify Settings Persistence
1. Set peaceful mode to desired state
2. Exit game completely
3. Restart game
4. **Expected**: Last peaceful mode state should be remembered

## Files to Modify

1. **`scripts/game/game.gd`** - Default setting
2. **`scripts/game/main.gd`** - Initial state and settings getter
3. **`scripts/ui/hud.gd`** - HUD display implementation

## Risk Assessment

**Low Risk Changes**:
- Default setting changes only affect new game sessions
- HUD addition is purely cosmetic and non-intrusive
- Peaceful mode toggle logic already exists and works correctly

**Rollback Plan**:
- Revert the three modified files to original state
- Game will return to current behavior (peaceful mode by default)

## Validation Checklist

- [ ] Enemy planes spawn when game starts
- [ ] HUD shows "MODE COMBAT (F4)" initially
- [ ] F4 toggles between peaceful and combat modes
- [ ] HUD text and color update correctly on toggle
- [ ] Settings persist between game sessions
- [ ] No new console errors or warnings
- [ ] Performance unchanged by HUD additions

## Additional Notes

- The F4 key already toggles peaceful mode - no input changes needed
- Existing peaceful mode logic in `main.gd` handles enemy cleanup correctly
- HUD follows existing patterns used by flight and texture status displays
- Color coding is optional but provides better visual feedback