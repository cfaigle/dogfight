extends RefCounted

const MANIFEST_PATH := "res://assets/external/manifest.json"

var _enabled: bool = false
var _manifest: Dictionary = {}
var _variants: Dictionary = {}  # key -> Array[Mesh]


func reload(enabled: bool) -> void:
    _enabled = enabled
    _manifest = {}
    _variants = {}

    if not _enabled:
        return

    var d := _load_manifest()
    if d.is_empty():
        return

    _manifest = d

    var v: Variant = d.get("variants", {})
    if not (v is Dictionary):
        return

    # Pre-load meshes for every declared variant list.
    for k in (v as Dictionary).keys():
        var arr: Array = _as_string_array((v as Dictionary)[k])
        var meshes: Array[Mesh] = []
        for p in arr:
            var m: Mesh = _load_mesh_from_path(p)
            if m != null:
                meshes.append(m)
        if not meshes.is_empty():
            _variants[String(k)] = meshes


func enabled() -> bool:
    return _enabled


# Back-compat: some callers use `is_enabled()`.
func is_enabled() -> bool:
    return _enabled


func manifest_flag_default(default_value: bool = false) -> bool:
    if _manifest.is_empty():
        return default_value
    return bool(_manifest.get("use_external_assets", default_value))


func get_mesh_variants(key: String) -> Array[Mesh]:
    if not _enabled:
        return []
    if _variants.has(key):
        return _variants[key] as Array[Mesh]
    return []


func _load_manifest() -> Dictionary:
    if not FileAccess.file_exists(MANIFEST_PATH):
        return {}
    var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
    if f == null:
        return {}
    var txt := f.get_as_text()
    f.close()

    var j := JSON.new()
    var err := j.parse(txt)
    if err != OK:
        push_warning("AssetLibrary: manifest.json parse error: %s" % j.get_error_message())
        return {}
    var data: Variant = j.data
    if data is Dictionary:
        return data as Dictionary
    return {}


func _as_string_array(v: Variant) -> Array:
    var out: Array = []
    if v is Array:
        for it in (v as Array):
            if it is String:
                out.append(it)
    return out


func _load_mesh_from_path(path: String) -> Mesh:
    if path == "":
        return null
    var res: Resource = load(path)
    if res == null:
        return null
    if res is Mesh:
        return res as Mesh
    if res is PackedScene:
        var inst := (res as PackedScene).instantiate()
        var m: Mesh = _extract_mesh_from_node(inst)
        inst.queue_free()
        return m
    return null


func _extract_mesh_from_node(root: Node) -> Mesh:
    # BFS search for first MeshInstance3D with a mesh.
    var q: Array[Node] = [root]
    while not q.is_empty():
        var n: Node = q.pop_front()
        if n is MeshInstance3D:
            var mi := n as MeshInstance3D
            if mi.mesh != null:
                return mi.mesh
        for c in n.get_children():
            if c is Node:
                q.append(c as Node)
    return null
