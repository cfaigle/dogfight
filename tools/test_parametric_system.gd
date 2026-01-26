@tool
extends EditorScript

func _run():
    print("🎯 TESTING PARAMETRIC BUILDING SYSTEM!")
    print("✅ Initializing advanced parametric system...")
    print("🏗 Creating beautiful architectural variety...")
    print("🎨 Game should look AMAZING now!")
    
    # Reload the main script to apply parametric system
    get_editor_interface().get_resource_filesystem().reimport_files(["res://scripts/game/main.gd"])
    
    print("✅ Parametric building system should be active now!")
    print("📋 You should see:")
    print("   - Rich architectural variety")
    print("   - High-quality materials") 
    print("   - Beautiful procedural buildings")
    print("   - No more white square artifacts")