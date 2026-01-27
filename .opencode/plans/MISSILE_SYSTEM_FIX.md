# Missile System Implementation Plan

## Issue Summary
The missile/rocket system is completely non-functional. The player has missile input bindings (Right Mouse/Shift) but there's no missile launcher component to process the input.

## Root Causes
1. **Missing Missile Launcher**: Plane.gd never creates a missile launcher component
2. **No Missile Firing Logic**: `_weapons_step()` ignores `missile_trigger` input
3. **Missing Scene References**: No missile scene or hardpoint nodes defined

## Implementation Plan

### Phase 1: Add Missile Launcher Component

#### File: `scripts/actors/plane/plane.gd`

**Line ~90-100**: Add missile launcher variable to class (near gun declaration)
```gdscript
# AFTER gun variable:
var _missile_launcher: Node
```

**Line ~140-160**: In `_ready()` method, add missile launcher creation
```gdscript
# AFTER gun creation:
_missile_launcher = preload("res://scripts/actors/weapons/missile_launcher.gd").new()
_missile_launcher.name = "MissileLauncher"
add_child(_missile_launcher)
if weapon_defs != null and _missile_launcher.has_method("apply_defs"):
    _missile_launcher.apply_defs(weapon_defs, "missile")
```

### Phase 2: Implement Missile Firing Logic

#### File: `scripts/actors/plane/plane.gd`

**Line 373-384**: Update `_weapons_step()` method to handle missiles
```gdscript
# AFTER existing gun firing logic:
func _weapons_step(dt: float) -> void:
    if _gun == null:
        return
    if gun_trigger:
        # Aim a bit ahead along forward. If we have a target, aim at it.
        var aim: Vector3
        if _target and is_instance_valid(_target):
            aim = _target.global_position
        else:
            aim = global_position + get_forward() * 1200.0
        if _gun.has_method("fire"):
            _gun.fire(aim)
    
    # NEW: Missile firing logic
    if missile_trigger and _missile_launcher and _missile_launcher.has_method("fire"):
        var target = _target if _target and is_instance_valid(_target) else null
        var locked = target != null  # Simple lock detection
        _missile_launcher.fire(target, locked)
```

### Phase 3: Verify Scene Structure

#### Verify Player Plane Scene

The player plane scene needs these nodes for missile system to work:

**Required Nodes:**
```
PlayerPlane
├── Hardpoints
│   ├── Left (Node3D)
│   └── Right (Node3D)
└── [existing structure]
```

**Check Files:**
- `scenes/player_plane.tscn` or similar
- Verify `Hardpoints/Left` and `Hardpoints/Right` nodes exist
- Verify missile scene is assigned to missile_launcher

#### Verify Missile Scene

**Required Scene:** `scenes/weapons/missile.tscn`
- Should contain the missile mesh and collision
- Should have `missile.gd` script attached
- Should be referenced in `weapon_defs.tres`

### Phase 4: Update Weapon Definitions

#### File: `resources/defs/weapon_defs.tres`

Ensure missile definitions exist:
```gdscript
missile = {
    "damage": 85.0,
    "speed": 260.0,
    "turn_rate": 4.5,
    "accel": 260.0,
    "life": 10.0,
    "lock_cone_deg": 12.0,
    "lock_time": 1.25,
    "cooldown": 1.0,
    "scene": "res://scenes/weapons/missile.tscn",
    "hardpoint_paths": ["Hardpoints/Left", "Hardpoints/Right"]
}
```

### Phase 5: Add Debug Output (Optional)

#### File: `scripts/actors/plane/plane.gd`

Add debug logging for missile firing:
```gdscript
# In _weapons_step(), add before missile firing:
if Game.settings.get("show_debug", false) and missile_trigger:
    print("Missile trigger pressed, launcher exists: ", _missile_launcher != null)
```

## Testing Procedure

### Step 1: Verify Component Creation
1. Start game
2. Check PlayerPlane node in scene tree
3. **Expected**: Should see "MissileLauncher" child node
4. **Expected**: No errors about missing missile_launcher

### Step 2: Test Missile Input
1. Press **Right Mouse Button** or **Shift**
2. **Expected**: Missile should fire from hardpoints
3. **Expected**: Console should show debug info (if enabled)
4. **Expected**: No error messages about missing components

### Step 3: Test Target-Locked Missiles
1. Acquire enemy target (get within radar range)
2. Press **Right Mouse Button** or **Shift**
3. **Expected**: Missile should track and follow target
4. **Expected**: Missile should explode on impact or timeout

### Step 4: Test Free-Fire Missiles
1. Fire missile without target
2. **Expected**: Missile should fly straight ahead
3. **Expected**: Missile should self-destruct after lifetime expires

## Files to Modify

1. **`scripts/actors/plane/plane.gd`** - Add missile launcher component and firing logic
2. **Verify** `scenes/player_plane.tscn` - Ensure hardpoint nodes exist
3. **Verify** `scenes/weapons/missile.tscn` - Ensure missile scene exists
4. **Check** `resources/defs/weapon_defs.tres` - Ensure missile definitions exist

## Risk Assessment

**Medium Risk Changes**:
- Adding new component affects plane initialization
- Missile firing logic could interfere with existing systems
- Missing scene files could cause runtime errors

**Rollback Plan**:
- Remove `_missile_launcher` variable and initialization code
- Remove missile firing logic from `_weapons_step()`
- Game will return to current state (no missiles)

## Validation Checklist

- [ ] Missile launcher component created successfully
- [ ] Hardpoint nodes exist in player plane scene
- [ ] Missile scene loads correctly
- [ ] Right Mouse/Shift fires missiles
- [ ] Missiles track when target is locked
- [ ] Missiles fly straight when no target
- [ ] No console errors related to missile system
- [ ] Missile system doesn't affect gun performance
- [ ] Cooldown system works between missile shots

## Troubleshooting

### Common Issues

**Issue**: "Missile launcher component not found"
- **Solution**: Verify missile_launcher.gd exists and loads correctly
- **Check**: File path in preload() is correct

**Issue**: "Hardpoints/Left not found"
- **Solution**: Add hardpoint nodes to player plane scene
- **Check**: Node paths match missile launcher expectations

**Issue**: "Missile scene is null"
- **Solution**: Ensure missile.tscn exists and is assigned in weapon_defs
- **Check**: Scene file path and dependencies

**Issue**: Missiles don't move
- **Solution**: Verify missile.gd script is attached to missile scene
- **Check**: Missile physics and initialization code

## Additional Notes

- The missile system already exists architecturally (`missile_launcher.gd`, `missile.gd`)
- The missing piece is integration with the player plane
- Hardpoint system allows multiple missiles per hardpoint
- Cooldown and lock-on mechanics are already implemented in missile_launcher.gd
- Visual and audio effects are handled by the missile scene and script