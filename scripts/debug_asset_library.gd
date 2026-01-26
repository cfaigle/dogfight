extends SceneTree

# Debug script to test AssetLibrary texture loading

func _init():
    print("=== Asset Library Debug ===")
    
    var AssetLibraryScript = preload("res://scripts/util/asset_library.gd")
    var assets = AssetLibraryScript.new()
    
    # Test with external assets enabled
    assets.reload(true)
    
    print("Assets enabled: ", assets.enabled())
    print("Manifest flag default: ", assets.manifest_flag_default())
    
    # Test texture loading
    var grass_textures = assets.get_texture_set("terrain_grass")
    print("\n=== Grass Textures ===")
    print("Texture set size: ", grass_textures.size())
    for key in grass_textures.keys():
        var tex = grass_textures[key]
        print("  ", key, ": ", tex.get_class(), " - ", tex.get_size() if tex else "null")
    
    var pavement_textures = assets.get_texture_set("terrain_pavement")
    print("\n=== Pavement Textures ===")
    print("Texture set size: ", pavement_textures.size())
    for key in pavement_textures.keys():
        var tex = pavement_textures[key]
        print("  ", key, ": ", tex.get_class(), " - ", tex.get_size() if tex else "null")
    
    var euro_textures = assets.get_texture_set("building_atlas_euro")
    print("\n=== Euro Building Textures ===")
    print("Texture set size: ", euro_textures.size())
    for key in euro_textures.keys():
        var tex = euro_textures[key]
        print("  ", key, ": ", tex.get_class(), " - ", tex.get_size() if tex else "null")
    
    var industrial_textures = assets.get_texture_set("building_atlas_industrial")
    print("\n=== Industrial Building Textures ===")
    print("Texture set size: ", industrial_textures.size())
    for key in industrial_textures.keys():
        var tex = industrial_textures[key]
        print("  ", key, ": ", tex.get_class(), " - ", tex.get_size() if tex else "null")
    
    # Test mesh loading
    print("\n=== Mesh Variants ===")
    var euro_meshes = assets.get_mesh_variants("euro_buildings")
    print("Euro building meshes: ", euro_meshes.size())
    for i in range(min(3, euro_meshes.size())):
        var mesh = euro_meshes[i]
        if mesh:
            print("  Mesh ", i, ": ", mesh.get_class(), " - surface count: ", mesh.get_surface_count())
        else:
            print("  Mesh ", i, ": null")
    
    quit()
