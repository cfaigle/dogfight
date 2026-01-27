# Gun System Verification Plan

## Issue Summary
The gun system appears to be implemented but may have scene structure or configuration issues preventing it from working properly.

## Root Causes
1. **Missing Scene Nodes**: Gun system expects specific muzzle nodes that may not exist
2. **Missing Scene References**: Tracer scene may not be assigned
3. **Configuration Issues**: Gun definitions may be incomplete or incorrect

## Implementation Plan

### Phase 1: Verify Scene Structure

#### File: Scenes (player_plane.tscn or equivalent)

**Required Nodes for Gun System:**
```
PlayerPlane
├── Muzzles
│   ├── Left (Node3D)
│   └── Right (Node3D)
└── [existing structure]
```

**Verification Steps:**
1. Open player plane scene in Godot editor
2. Look for `Muzzles/Left` and `Muzzles/Right` nodes
3. Verify nodes are positioned correctly (near wingtips/cannon positions)
4. Ensure nodes have correct spatial relationships

**If Missing - Add Nodes:**
1. Add `Muzzles` Node3D to player plane
2. Add `Left` and `Right` Node3D children
3. Position appropriately for gun effects
4. Save scene

### Phase 2: Verify Gun Configuration

#### File: `scripts/actors/weapons/gun.gd`

**Critical Properties (lines 9, 28-29):**
```gdscript
@export var tracer_scene: PackedScene  # MUST be assigned
# Line 28-29 expect these nodes to exist:
var _muzzle_left: Node3D = get_node("Muzzles/Left")
var _muzzle_right: Node3D = get_node("Muzzles/Right")
```

#### File: `resources/defs/weapon_defs.tres`

**Verify Gun Definitions:**
```gdscript
gun = {
    "damage": 25.0,
    "cool_down": 0.067,  # ~900 RPM
    "heat_per_shot": 0.025,
    "cool_per_second": 0.12,
    "tracer_scene": "res://scenes/weapons/tracer.tscn",  # CRITICAL
    "muzzle_flash": true,
    "muzzle_flash_duration": 0.08,
    "range": 1200.0,
    "spread": 0.002,
    "audio_fire": "res://audio/weapons/gun_fire.wav"
}
```

### Phase 3: Verify Tracer Scene

#### File: `scenes/weapons/tracer.tscn`

**Required Components:**
- Tracer mesh (usually a thin cylinder or stretched sphere)
- `tracer.gd` script attached
- Proper collision setup (if applicable)
- Material assignment for visual effect

**If Missing - Create Tracer:**
1. Create CylinderMesh with small radius, extended height
2. Create Material3D with emissive yellow/orange color
3. Add `tracer.gd` script
4. Save as `scenes/weapons/tracer.tscn`

### Phase 4: Add Debug Output

#### File: `scripts/actors/plane/plane.gd`

**Add Gun System Debugging:**
```gdscript
# In _weapons_step(), before gun firing:
if Game.settings.get("show_debug", false) and gun_trigger:
    print("Gun trigger pressed")
    print("Gun exists: ", _gun != null)
    if _gun:
        print("Gun can fire: ", _gun.can_fire())
        print("Gun heat: ", _gun.heat if _gun.has_method("get_heat") else "N/A")
        print("Muzzle left exists: ", _gun.get_node_or_null("Muzzles/Left") != null)
        print("Muzzle right exists: ", _gun.get_node_or_null("Muzzles/Right") != null)
```

#### File: `scripts/actors/weapons/gun.gd`

**Add Debug Methods (if not present):**
```gdscript
func get_heat() -> float:
    return _heat

func can_fire() -> bool:
    return _cool_down_timer <= 0.0 and _heat < 0.98
```

### Phase 5: Verify Audio System

#### File: `resources/defs/weapon_defs.tres`

**Check Audio Path:**
```gdscript
"audio_fire": "res://audio/weapons/gun_fire.wav"
```

**Verify File Exists:**
- Check if `audio/weapons/gun_fire.wav` file exists
- If missing, add placeholder or comment out line temporarily

## Testing Procedure

### Step 1: Debug Output Verification
1. Enable debug mode: `Game.settings["show_debug"] = true`
2. Start game
3. Press **Left Mouse** or **Spacebar**
4. Check console for debug output
5. **Expected**: Should see gun component and muzzle node status

### Step 2: Visual Effects Test
1. Fire guns with visual line of sight (third person view)
2. **Expected**: Should see muzzle flash from wingtips
3. **Expected**: Should see tracer lines extending forward
4. **Expected**: Should hear gun firing sound

### Step 3: Hit Detection Test
1. Fire at terrain or buildings
2. **Expected**: Should see impact effects
3. **Expected**: Should cause damage to destructible objects
4. **Expected**: Console should show hit debug info (if enabled)

### Step 4: Performance Test
1. Fire continuously for several seconds
2. **Expected**: Heat should build up, preventing firing at ~0.98
3. **Expected**: Cooldown should work between shots
4. **Expected**: No performance degradation or frame drops

## Files to Verify/Potentially Modify

1. **Player plane scene** - Ensure muzzle nodes exist
2. **`scenes/weapons/tracer.tscn`** - Verify tracer scene exists
3. **`resources/defs/weapon_defs.tres`** - Check gun definitions
4. **`audio/weapons/gun_fire.wav`** - Verify audio file exists

## Risk Assessment

**Low Risk Verification**:
- Most changes are verification, not modification
- Debug output is non-intrusive
- Scene structure changes are straightforward

**Rollback Plan**:
- Remove debug print statements
- Scene changes can be reverted easily
- Game will return to current state if issues persist

## Validation Checklist

- [ ] Muzzle nodes exist in player plane scene
- [ ] Tracer scene loads correctly
- [ ] Audio file exists and plays
- [ ] Debug output shows gun system is functional
- [ ] Visual muzzle flash appears when firing
- [ ] Tracer lines are visible
- [ ] Impact effects work on terrain/objects
- [ ] Heat/cooldown systems function correctly
- [ ] No console errors during gun operation

## Troubleshooting

### Common Issues

**Issue**: "Node not found: Muzzles/Left"
- **Solution**: Add missing muzzle nodes to player plane scene
- **Check**: Node path and hierarchy in scene file

**Issue**: "Tracer scene is null"
- **Solution**: Create or assign tracer scene in weapon_defs
- **Check**: File path and scene existence

**Issue**: "Can't play audio: gun_fire.wav"
- **Solution**: Add missing audio file or disable temporarily
- **Check**: Audio file path and format

**Issue**: "Gun never fires (can_fire returns false)"
- **Solution**: Check heat level and cooldown timer
- **Check**: Weapon definitions for heat/cooling values

**Issue**: "No visual effects"
- **Solution**: Verify muzzle flash and tracer materials
- **Check**: Camera positioning and render settings

## Additional Notes

- The gun system architecture is sound - likely missing scene structure
- Debug output will quickly identify the specific issue
- Tracer scene is essential for visual feedback
- Audio system may be optional but enhances experience
- Heat and cooldown systems prevent unlimited firing

## Performance Considerations

- Limit tracer lifetime to prevent scene clutter
- Use object pooling for frequently created tracers
- Muzzle flash duration should be short
- Audio system should reuse audio streams