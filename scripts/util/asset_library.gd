extends RefCounted

const MANIFEST_PATH := "res://assets/external/manifest.json"

var _enabled: bool = false
var _manifest: Dictionary = {}
var _variants: Dictionary = {}  # key -> Array[Mesh]
var _textures: Dictionary = {}  # key -> Dictionary with albedo, normal, roughness, etc.


func reload(enabled: bool) -> void:
    _enabled = enabled
    _manifest = {}
    _variants = {}
    _textures = {}

    if not _enabled:
        return

    var d := _load_manifest()
    if d.is_empty():
        return

    _manifest = d

    # Load mesh variants
    var v: Variant = d.get("variants", {})
    if v is Dictionary:
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

    # Load texture sets
    var t: Variant = d.get("textures", {})
    if t is Dictionary:
        for k in (t as Dictionary).keys():
            var texture_set: Variant = (t as Dictionary)[k]
            if texture_set is Dictionary:
                _textures[String(k)] = _load_texture_set(texture_set as Dictionary)


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


func get_texture_set(key: String) -> Dictionary:
    """Get a texture set (albedo, normal, roughness, etc.) by key.

    Returns a Dictionary with texture paths like:
    {
        "albedo": Texture2D,
        "normal": Texture2D,
        "roughness": Texture2D,
        "metallic": Texture2D,  # optional
        "ao": Texture2D,        # optional
        "height": Texture2D     # optional
    }
    """
    if not _enabled:
        return {}
    if _textures.has(key):
        return _textures[key] as Dictionary
    return {}


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


func _load_texture_set(texture_data: Dictionary) -> Dictionary:
    """Load textures from a texture set definition.

    Input: Dictionary with string paths like {"albedo": "res://...", "normal": "res://..."}
    Output: Dictionary with loaded Texture2D resources
    """
    var loaded: Dictionary = {}

    # Load each texture type if it exists in the data
    var texture_types: Array[String] = ["albedo", "normal", "roughness", "metallic", "ao", "height"]

    for tex_type in texture_types:
        if texture_data.has(tex_type):
            var path: Variant = texture_data[tex_type]
            if path is String and path != "":
                var tex: Resource = load(path as String)
                if tex is Texture2D:
                    loaded[tex_type] = tex
                elif tex != null:
                    push_warning("AssetLibrary: Expected Texture2D at %s, got %s" % [path, tex.get_class()])

    return loaded
