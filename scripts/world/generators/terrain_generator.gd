class_name TerrainGenerator
extends RefCounted

## Handles terrain queries + generation of terrain mesh, ocean, rivers, runway, and simple landmarks.
## Implemented to be callable from the modular WorldBuilder pipeline.

# Heightmap data
var _hmap: PackedFloat32Array = PackedFloat32Array()
var _hmap_res: int = 0
var _hmap_half: float = 0.0
var _hmap_step: float = 0.0

# Terrain parameters
var _terrain_size: float = 0.0
var _terrain_res: int = 0
var _terrain_render_root: Node3D = null

# Generated features
var _rivers: Array = []
var _settlements: Array = []

# Assets / caches
var TerrainShader: Shader = preload("res://resources/shaders/terrain_ww2.gdshader")
var _assets: RefCounted = null
var _mesh_cache: Dictionary = {}
var _material_cache: Dictionary = {}

func set_assets(assets: RefCounted) -> void:
    _assets = assets

func set_mesh_cache(cache: Dictionary) -> void:
    _mesh_cache = cache

func set_material_cache(cache: Dictionary) -> void:
    _material_cache = cache

func set_heightmap_data(hmap: PackedFloat32Array, res: int, step: float, half: float) -> void:
    _hmap = hmap
    _hmap_res = res
    _hmap_step = step
    _hmap_half = half
    _terrain_size = half * 2.0
    _terrain_res = res

func set_rivers(rivers: Array) -> void:
    _rivers = rivers

func set_settlements(settlements: Array) -> void:
    _settlements = settlements

func get_terrain_render_root() -> Node3D:
    return _terrain_render_root

## Main generator entry (kept for compatibility)
func generate(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    build_terrain(world_root, params, rng)

# --- Queries ---

func get_height_at(x: float, z: float) -> float:
    return _ground_height(x, z)

func get_normal_at(x: float, z: float) -> Vector3:
    if _hmap_res <= 0 or _hmap.is_empty():
        return Vector3.UP
    var u: float = (x + _hmap_half) / _hmap_step
    var v: float = (z + _hmap_half) / _hmap_step
    u = clamp(u, 0.0, float(_hmap_res))
    v = clamp(v, 0.0, float(_hmap_res))
    var x0: int = int(floor(u))
    var z0: int = int(floor(v))
    return _n_at_idx(x0, z0, _hmap_step)

## Returns slope angle in degrees.
func get_slope_at(x: float, z: float) -> float:
    return rad_to_deg(atan(_slope_grad_at(x, z)))

## Returns the direction of the slope (angle in radians) at the given coordinates.
## This represents the direction water would flow downhill.
func get_slope_direction_at(x: float, z: float) -> float:
    var normal: Vector3 = get_normal_at(x, z)
    # Project the normal onto the XZ plane to get the direction of maximum slope
    var slope_dir: Vector3 = Vector3(normal.x, 0, normal.z).normalized()
    if slope_dir.length() < 0.001:  # If the normal is nearly vertical (flat terrain)
        return 0.0
    return atan2(slope_dir.z, slope_dir.x)

func is_near_coast(x: float, z: float, radius: float) -> bool:
    var h: float = _ground_height(x, z)
    if h > Game.sea_level + 1.5:
        return false
    for i in range(8):
        var ang: float = float(i) * PI * 0.25
        var tx: float = x + cos(ang) * radius
        var tz: float = z + sin(ang) * radius
        var th: float = _ground_height(tx, tz)
        if th < Game.sea_level:
            return true
    return false

func find_land_point(rng: RandomNumberGenerator, min_height: float, max_slope_grad: float, prefer_coast: bool) -> Vector3:
    var sz: float = _terrain_size
    var max_tries: int = 700
    for _i in range(max_tries):
        var x: float = rng.randf_range(-sz * 0.45, sz * 0.45)
        var z: float = rng.randf_range(-sz * 0.45, sz * 0.45)
        var h: float = _ground_height(x, z)
        var sl: float = _slope_grad_at(x, z)
        if h < min_height or sl > max_slope_grad:
            continue
        if prefer_coast and not is_near_coast(x, z, 150.0):
            continue
        return Vector3(x, h, z)
    return Vector3.ZERO

# --- Generation: terrain mesh + collision ---

func build_terrain(world_root: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> Node3D:
    if _hmap_res <= 0 or _hmap.is_empty():
        push_error("TerrainGenerator.build_terrain: missing heightmap")
        return null

    var res: int = _terrain_res
    var step: float = _hmap_step
    var half: float = _hmap_half

    # Create / replace terrain root
    var terrain_root := Node3D.new()
    terrain_root.name = "Terrain"
    world_root.add_child(terrain_root)
    _terrain_render_root = terrain_root

    # Terrain material (shader + textures)
    var tmat := ShaderMaterial.new()
    tmat.shader = TerrainShader
    tmat.set_shader_parameter("sea_level", float(Game.sea_level))
    tmat.set_shader_parameter("show_road_grid", false)  # Disable procedural grid lines
    # Load and apply terrain textures if available
    if _assets != null and _assets.has_method("enabled") and bool(_assets.call("enabled")):
        if _assets.has_method("get_texture_set"):
            var grass_textures: Dictionary = _assets.call("get_texture_set", "terrain_grass")
            var pavement_textures: Dictionary = _assets.call("get_texture_set", "terrain_pavement")
            if grass_textures.has("albedo") and pavement_textures.has("albedo"):
                tmat.set_shader_parameter("use_textures", true)
                tmat.set_shader_parameter("grass_texture", grass_textures["albedo"])
                tmat.set_shader_parameter("pavement_texture", pavement_textures["albedo"])
                tmat.set_shader_parameter("texture_scale", 32.0)

    # Chunking
    var target_cells: int = int(params.get("terrain_chunk_cells", 32))
    var cells: int = _pick_chunk_cells(target_cells, res)
    var chunks: int = int(res / cells)

    for cz in range(chunks):
        for cx in range(chunks):
            var ix0: int = cx * cells
            var iz0: int = cz * cells
            var chunk := Node3D.new()
            chunk.name = "Chunk_%d_%d" % [cx, cz]
            terrain_root.add_child(chunk)

            var center_x: float = -half + (float(ix0) + float(cells) * 0.5) * step
            var center_z: float = -half + (float(iz0) + float(cells) * 0.5) * step
            chunk.set_meta("center", Vector2(center_x, center_z))
            chunk.set_meta("lod", -1)

            var mi0 := MeshInstance3D.new()
            mi0.name = "LOD0"
            mi0.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 1, half, step)
            mi0.material_override = tmat
            chunk.add_child(mi0)

            var mi1 := MeshInstance3D.new()
            mi1.name = "LOD1"
            mi1.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 2, half, step)
            mi1.material_override = tmat
            mi1.visible = false
            chunk.add_child(mi1)

            var mi2 := MeshInstance3D.new()
            mi2.name = "LOD2"
            mi2.mesh = _make_terrain_chunk_mesh(ix0, iz0, cells, 4, half, step)
            mi2.material_override = tmat
            mi2.visible = false
            chunk.add_child(mi2)

    # Collision: Use mesh-based collision instead of HeightMapShape3D
    # HeightMapShape3D has issues with scaling in Godot 4

    # Create a low-res collision mesh (use LOD2 for performance)
    var collision_mesh = _make_terrain_chunk_mesh(0, 0, res, 4, half, step)

    # Create MeshInstance3D with collision
    var collision_mesh_instance := MeshInstance3D.new()
    collision_mesh_instance.name = "TerrainCollision"
    collision_mesh_instance.mesh = collision_mesh
    collision_mesh_instance.visible = false  # Don't render, just collision

    # Create trimesh collision from the mesh
    collision_mesh_instance.create_trimesh_collision()

    # Set collision layers on the generated StaticBody3D
    for child in collision_mesh_instance.get_children():
        if child is StaticBody3D:
            var ground = child as StaticBody3D
            ground.collision_layer = 1
            ground.collision_mask = 1

    world_root.add_child(collision_mesh_instance)

    # Initial LOD based on runway spawn or camera
    var cam_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
    if params.has("runway_spawn") and (params["runway_spawn"] is Vector3):
        cam_pos = params["runway_spawn"]
    apply_terrain_lod(cam_pos, bool(params.get("terrain_lod_enabled", true)), float(params.get("terrain_lod0_r", 6500.0)), float(params.get("terrain_lod1_r", 16000.0)))

    return terrain_root

## Apply LOD to terrain chunks
func apply_terrain_lod(camera_pos: Vector3, lod_enabled: bool, lod0_r: float, lod1_r: float) -> void:
    if _terrain_render_root == null or not is_instance_valid(_terrain_render_root):
        return

    for c in _terrain_render_root.get_children():
        if not (c is Node3D):
            continue
        var chunk: Node3D = c as Node3D
        var center: Vector2 = chunk.get_meta("center", Vector2.ZERO)
        var dist: float = Vector2(camera_pos.x, camera_pos.z).distance_to(center)

        var new_lod: int = 0
        if lod_enabled:
            new_lod = 0 if dist < lod0_r else (1 if dist < lod1_r else 2)
        else:
            new_lod = 0

        var old_lod: int = int(chunk.get_meta("lod", -1))
        if old_lod == new_lod:
            continue
        chunk.set_meta("lod", new_lod)

        var mi0: MeshInstance3D = chunk.get_node_or_null("LOD0") as MeshInstance3D
        var mi1: MeshInstance3D = chunk.get_node_or_null("LOD1") as MeshInstance3D
        var mi2: MeshInstance3D = chunk.get_node_or_null("LOD2") as MeshInstance3D
        if mi0 != null:
            mi0.visible = (new_lod == 0)
        if mi1 != null:
            mi1.visible = (new_lod == 1)
        if mi2 != null:
            mi2.visible = (new_lod == 2)

# --- Generation: ocean / rivers / runway / landmarks ---

func build_ocean(parent: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var ocean := MeshInstance3D.new()
    ocean.name = "Ocean"
    var pm := PlaneMesh.new()
    pm.size = Vector2(82000.0, 82000.0)
    pm.subdivide_width = 24
    pm.subdivide_depth = 24
    ocean.mesh = pm
    ocean.position = Vector3(0.0, Game.sea_level - 0.35, 0.0)

    var mat := ShaderMaterial.new()
    mat.shader = preload("res://resources/shaders/ocean.gdshader")
    ocean.material_override = mat
    ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(ocean)

func build_rivers(parent: Node3D, rivers: Array, params: Dictionary, rng: RandomNumberGenerator) -> void:
    if rivers == null or rivers.is_empty():
        return

    var root := Node3D.new()
    root.name = "Rivers"
    parent.add_child(root)

    var river_mat := ShaderMaterial.new()
    river_mat.shader = preload("res://resources/shaders/ocean.gdshader")
    # Orange color scheme for rivers (temporary for debugging)
    river_mat.set_shader_parameter("deep_color", Vector3(0.35, 0.15, 0.02))  # Deep orange
    river_mat.set_shader_parameter("glow_color", Vector3(0.95, 0.55, 0.15))  # Bright orange

    for r in rivers:
        if not (r is Dictionary):
            continue
        var rd: Dictionary = r as Dictionary
        var pts: PackedVector3Array = rd.get("points", PackedVector3Array())
        if pts.size() < 6:
            continue

        var w0: float = float(rd.get("width0", 12.0))
        var w1: float = float(rd.get("width1", 44.0))

        var mi := MeshInstance3D.new()
        mi.material_override = river_mat
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)

        for i in range(pts.size()):
            var t: float = float(i) / float(max(1, pts.size() - 1))
            var width: float = lerp(w0, w1, pow(t, 0.85))

            var p: Vector3 = pts[i]
            var p_prev: Vector3 = pts[max(0, i - 1)]
            var p_next: Vector3 = pts[min(pts.size() - 1, i + 1)]

            var dir: Vector3 = (p_next - p_prev)
            dir.y = 0.0
            if dir.length() < 0.001:
                dir = Vector3(1, 0, 0)
            dir = dir.normalized()
            var side: Vector3 = dir.cross(Vector3.UP).normalized()

            var y: float = _ground_height(p.x, p.z) + 0.18
            var py: Vector3 = Vector3(p.x, maxf(y, Game.sea_level + 0.05), p.z)

            var left: Vector3 = py - side * (width * 0.5)
            var right: Vector3 = py + side * (width * 0.5)

            if i > 0:
                var t0: float = float(i - 1) / float(max(1, pts.size() - 1))
                var w_prev: float = lerp(w0, w1, pow(t0, 0.85))

                var pp: Vector3 = pts[i - 1]
                var pp_prev: Vector3 = pts[max(0, i - 2)]
                var pp_next: Vector3 = pts[min(pts.size() - 1, i)]
                var d2: Vector3 = (pp_next - pp_prev)
                d2.y = 0.0
                if d2.length() < 0.001:
                    d2 = Vector3(1, 0, 0)
                d2 = d2.normalized()
                var s2: Vector3 = d2.cross(Vector3.UP).normalized()

                var yy: float = _ground_height(pp.x, pp.z) + 0.18
                var ppy: Vector3 = Vector3(pp.x, maxf(yy, Game.sea_level + 0.05), pp.z)

                var l0: Vector3 = ppy - s2 * (w_prev * 0.5)
                var r0: Vector3 = ppy + s2 * (w_prev * 0.5)

                st.add_vertex(l0)
                st.add_vertex(r0)
                st.add_vertex(left)

                st.add_vertex(r0)
                st.add_vertex(right)
                st.add_vertex(left)

        st.generate_normals()
        mi.mesh = st.commit()
        root.add_child(mi)

func build_runway(parent: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> Vector3:
    var runway_len: float = float(params.get("runway_len", 900.0))
    var runway_w: float = float(params.get("runway_w", 80.0))

    var spawn_z: float = -runway_len * 0.35
    var y: float = maxf(_ground_height(0.0, spawn_z) + 25.0, Game.sea_level + 80.0)
    var runway_spawn := Vector3(0.0, y, spawn_z)

    var runway_y: float = _ground_height(0.0, 0.0) + 0.05

    var runway := MeshInstance3D.new()
    runway.name = "Runway"
    var pm := PlaneMesh.new()
    pm.size = Vector2(runway_w, runway_len)
    pm.subdivide_depth = 8
    runway.mesh = pm
    runway.position = Vector3(0.0, runway_y, 0.0)
    var rmat := StandardMaterial3D.new()
    rmat.albedo_color = Color(0.07, 0.07, 0.075)
    rmat.roughness = 0.95
    runway.material_override = rmat
    parent.add_child(runway)

    var line := MeshInstance3D.new()
    line.name = "RunwayLine"
    var bm := BoxMesh.new()
    bm.size = Vector3(2.4, 0.15, runway_len * 0.88)
    line.mesh = bm
    line.position = runway.position + Vector3(0.0, 0.10, 0.0)
    var lmat := StandardMaterial3D.new()
    lmat.albedo_color = Color(0.92, 0.92, 0.86)
    lmat.roughness = 1.0
    line.material_override = lmat
    parent.add_child(line)

    # Minimal hangars for orientation
    var hang_body_mat := StandardMaterial3D.new()
    hang_body_mat.albedo_color = Color(0.26, 0.28, 0.22)
    hang_body_mat.roughness = 0.95
    var hang_roof_mat := StandardMaterial3D.new()
    hang_roof_mat.albedo_color = Color(0.20, 0.19, 0.18)
    hang_roof_mat.roughness = 0.92

    for s in [-1, 1]:
        var hangar := Node3D.new()
        hangar.name = "Hangar_%s" % str(s)
        hangar.position = Vector3(float(s) * 92.0, runway_y, -140.0)
        parent.add_child(hangar)

        var base := MeshInstance3D.new()
        var hb := BoxMesh.new()
        hb.size = Vector3(46.0, 14.0, 72.0)
        base.mesh = hb
        base.position = Vector3(0.0, hb.size.y * 0.5, 0.0)
        base.material_override = hang_body_mat
        hangar.add_child(base)

        var roof := MeshInstance3D.new()
        var rb := BoxMesh.new()
        rb.size = Vector3(hb.size.x * 1.05, 8.0, hb.size.z * 1.05)
        roof.mesh = rb
        roof.position = Vector3(0.0, hb.size.y + rb.size.y * 0.5, 0.0)
        roof.material_override = hang_roof_mat
        hangar.add_child(roof)

    return runway_spawn

func build_landmarks(parent: Node3D, params: Dictionary, rng: RandomNumberGenerator) -> void:
    var count: int = int(params.get("landmark_count", 0))
    count = clampi(count, 0, 80)
    if count <= 0:
        return

    for i in range(count):
        var m := MeshInstance3D.new()
        var cm := CylinderMesh.new()
        cm.top_radius = 0.0
        cm.bottom_radius = rng.randf_range(420.0, 980.0)
        cm.height = rng.randf_range(650.0, 1900.0)
        m.mesh = cm

        var a: float = float(i) / float(max(1, count)) * TAU
        var dist: float = rng.randf_range(_terrain_size * 0.62, _terrain_size * 0.92)
        var x: float = cos(a) * dist
        var z: float = sin(a) * dist
        var y: float = _ground_height(x, z) + cm.height * 0.50 - 20.0
        m.position = Vector3(x, y, z)

        var mm := StandardMaterial3D.new()
        mm.albedo_color = Color(0.22, 0.23, 0.24)
        mm.roughness = 1.0
        m.material_override = mm
        parent.add_child(m)

# --- Internal helpers ---

func _ground_height(x: float, z: float) -> float:
    if _hmap_res <= 0 or _hmap.is_empty():
        return float(Game.sea_level)

    var u: float = (x + _hmap_half) / _hmap_step
    var v: float = (z + _hmap_half) / _hmap_step
    u = clamp(u, 0.0, float(_hmap_res))
    v = clamp(v, 0.0, float(_hmap_res))

    var x0: int = int(floor(u))
    var z0: int = int(floor(v))
    var x1: int = min(x0 + 1, _hmap_res)
    var z1: int = min(z0 + 1, _hmap_res)

    var fu: float = u - float(x0)
    var fv: float = v - float(z0)

    var w: int = _hmap_res + 1
    var h00: float = float(_hmap[z0 * w + x0])
    var h10: float = float(_hmap[z0 * w + x1])
    var h01: float = float(_hmap[z1 * w + x0])
    var h11: float = float(_hmap[z1 * w + x1])

    var a: float = lerp(h00, h10, fu)
    var b: float = lerp(h01, h11, fu)
    return lerp(a, b, fv)

func _slope_grad_at(x: float, z: float) -> float:
    if _hmap_res <= 0:
        return 0.0
    var h: float = _ground_height(x, z)
    var hx: float = _ground_height(x + _hmap_step, z)
    var hz: float = _ground_height(x, z + _hmap_step)
    var sx: float = absf(hx - h) / maxf(0.001, _hmap_step)
    var sz: float = absf(hz - h) / maxf(0.001, _hmap_step)
    return maxf(sx, sz)

func _h_at_idx(ix: int, iz: int) -> float:
    var res: int = _terrain_res
    var w: int = res + 1
    ix = clampi(ix, 0, res)
    iz = clampi(iz, 0, res)
    return float(_hmap[iz * w + ix])

func _n_at_idx(ix: int, iz: int, step: float) -> Vector3:
    var hL: float = _h_at_idx(ix - 1, iz)
    var hR: float = _h_at_idx(ix + 1, iz)
    var hD: float = _h_at_idx(ix, iz - 1)
    var hU: float = _h_at_idx(ix, iz + 1)
    var nx: float = hL - hR
    var nz: float = hD - hU
    var n := Vector3(nx, 2.0 * step, nz)
    if n.length() < 0.0001:
        return Vector3.UP
    return n.normalized()

func _pick_chunk_cells(target_cells: int, res: int) -> int:
    var cand := [64, 48, 40, 32, 24, 20, 16, 12, 10, 8]
    if target_cells > 0 and (res % target_cells == 0):
        return target_cells
    for c in cand:
        if res % int(c) == 0:
            return int(c)
    return max(8, res)

func _make_terrain_chunk_mesh(ix0: int, iz0: int, cells: int, stride: int, half: float, step: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var ix1: int = ix0 + cells
    var iz1: int = iz0 + cells

    for iz in range(iz0, iz1, stride):
        for ix in range(ix0, ix1, stride):
            var ixn: int = min(ix + stride, ix1)
            var izn: int = min(iz + stride, iz1)

            var x0: float = -half + float(ix) * step
            var z0: float = -half + float(iz) * step
            var x1: float = -half + float(ixn) * step
            var z1: float = -half + float(izn) * step

            var h00: float = _h_at_idx(ix, iz)
            var h10: float = _h_at_idx(ixn, iz)
            var h01: float = _h_at_idx(ix, izn)
            var h11: float = _h_at_idx(ixn, izn)

            var p00 := Vector3(x0, h00, z0)
            var p10 := Vector3(x1, h10, z0)
            var p01 := Vector3(x0, h01, z1)
            var p11 := Vector3(x1, h11, z1)

            var n00: Vector3 = _n_at_idx(ix, iz, step)
            var n10: Vector3 = _n_at_idx(ixn, iz, step)
            var n01: Vector3 = _n_at_idx(ix, izn, step)
            var n11: Vector3 = _n_at_idx(ixn, izn, step)

            var uv00 := Vector2(float(ix) / float(_terrain_res), float(iz) / float(_terrain_res))
            var uv10 := Vector2(float(ixn) / float(_terrain_res), float(iz) / float(_terrain_res))
            var uv01 := Vector2(float(ix) / float(_terrain_res), float(izn) / float(_terrain_res))
            var uv11 := Vector2(float(ixn) / float(_terrain_res), float(izn) / float(_terrain_res))

            # Two tris: p00-p10-p01, p10-p11-p01
            st.set_normal(n00)
            st.set_uv(uv00)
            st.add_vertex(p00)

            st.set_normal(n10)
            st.set_uv(uv10)
            st.add_vertex(p10)

            st.set_normal(n01)
            st.set_uv(uv01)
            st.add_vertex(p01)

            st.set_normal(n10)
            st.set_uv(uv10)
            st.add_vertex(p10)

            st.set_normal(n11)
            st.set_uv(uv11)
            st.add_vertex(p11)

            st.set_normal(n01)
            st.set_uv(uv01)
            st.add_vertex(p01)

    st.generate_normals()
    return st.commit()
