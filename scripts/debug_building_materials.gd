extends SceneTree

# Debug script to examine building kit materials

func _init():
    print("=== Building Kit Materials Debug ===")
    
    var AssetLibraryScript = preload("res://scripts/util/asset_library.gd")
    
    var assets = AssetLibraryScript.new()
    assets.reload(true)
    
    print("Assets enabled: ", assets.enabled())
    
    # Test different styles
    var styles = ["hamlet", "town", "city", "industrial", "coastal"]
    
    for style in styles:
        print("\n=== Style: ", style, " ===")
        
        # Get textures for this style
        var texture_key = "building_atlas_euro"
        if style == "industrial":
            texture_key = "building_atlas_industrial"
        
        var textures = assets.get_texture_set(texture_key)
        print("Texture key: ", texture_key)
        print("Texture set size: ", textures.size())
        
        if textures.size() > 0:
            print("  Albedo: ", "found" if textures.has("albedo") else "null")
            if textures.has("albedo"):
                print("    ", textures["albedo"].get_class(), " ", textures["albedo"].get_size())
            print("  Normal: ", "found" if textures.has("normal") else "null")
            if textures.has("normal"):
                print("    ", textures["normal"].get_class(), " ", textures["normal"].get_size())
            print("  Roughness: ", "found" if textures.has("roughness") else "null")
            if textures.has("roughness"):
                print("    ", textures["roughness"].get_class(), " ", textures["roughness"].get_size())
            print("  Metallic: ", "found" if textures.has("metallic") else "null")
            if textures.has("metallic"):
                print("    ", textures["metallic"].get_class(), " ", textures["metallic"].get_size())
            print("  AO: ", "found" if textures.has("ao") else "null")
            if textures.has("ao"):
                print("    ", textures["ao"].get_class(), " ", textures["ao"].get_size())
        else:
            print("  No textures found")
    
    quit()
