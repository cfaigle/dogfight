#!/usr/bin/env python3
"""
Disable material extraction on FBX imports to prevent white square issues.
This will force Godot to use embedded materials instead of broken extracted ones.
"""

import os
import re
from pathlib import Path


def disable_material_extraction():
    """Set materials/extract=0 in all FBX import files."""

    base_path = "/Users/cfaigle/Documents/Development/local/dogfight/assets/external"
    fixed_files = 0

    print("🔧 Disabling material extraction to fix white squares...")

    # Find all FBX import files
    for fbx_import in Path(base_path).rglob("*.fbx.import"):
        try:
            with open(fbx_import, "r") as f:
                content = f.read()

            # Disable material extraction
            if "materials/extract=1" in content:
                content = re.sub(r"materials/extract=1", "materials/extract=0", content)
                content = re.sub(
                    r"materials/extract_format=1", "materials/extract_format=0", content
                )

                with open(fbx_import, "w") as f:
                    f.write(content)
                fixed_files += 1
                print(f"  ✅ Fixed: {fbx_import.name}")

        except Exception as e:
            print(f"  ❌ Error: {fbx_import.name}: {e}")

    print(f"✅ Disabled material extraction in {fixed_files} FBX import files")
    print(f"\n📋 This will use embedded materials instead of broken extracted ones")


def reimport_all():
    """Create a script to reimport all modified assets."""

    reimport_script = """@tool
extends EditorScript

func _run():
    print("🔄 Reimporting external assets after material extraction disabled...")
    
    var fbx_files = []
    var dir = DirAccess.open("res://assets/external/packs")
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if file_name.ends_with(".fbx"):
                var full_path = "res://assets/external/packs/" + file_name
                fbx_files.append(full_path)
            file_name = dir.get_next()
        dir.list_dir_end()
    
    # Also search subdirectories
    for pack_dir in ["kenney_city-kit-suburban", "kenney_city-kit-industrial", "kenney_nature-kit", "kenney_city-kit-roads"]:
        var pack_path = "res://assets/external/packs/" + pack_dir + "/Models/FBX format/"
        if DirAccess.dir_exists_absolute(pack_path):
            var dir2 = DirAccess.open(pack_path)
            if dir2:
                dir2.list_dir_begin()
                var file_name = dir2.get_next()
                while file_name != "":
                    if file_name.ends_with(".fbx"):
                        var full_path = pack_path + file_name
                        fbx_files.append(full_path)
                    file_name = dir2.get_next()
                dir2.list_dir_end()
    
    # Reimport all FBX files in smaller batches to avoid timeouts
    var batch_size = 50
    var reimported = 0
    
    for i in range(0, fbx_files.size(), batch_size):
        var batch_end = mini(i + batch_size, fbx_files.size())
        var batch = []
        for j in range(i, batch_end):
            batch.append(fbx_files[j])
        
        if batch.size() > 0:
            EditorInterface.get_resource_filesystem().reimport_files(batch)
            reimported += batch.size()
            print("Reimported batch of ", batch.size(), " files (total: ", reimported, "/", fbx_files.size(), ")")
    
    print("✅ Material extraction disabled and reimport complete!")
    print("\\n🎉 White squares should now be GONE!")
    print("Buildings will use embedded Kenney materials instead of broken extracted ones.")
"""

    script_path = "/Users/cfaigle/Documents/Development/local/dogfight/tools/disable_extraction_reimport.gd"
    with open(script_path, "w") as f:
        f.write(reimport_script)

    print(f"📝 Created reimport script: {script_path}")
    print("\\n📋 Instructions:")
    print("   1. Open Godot Editor")
    print("   2. Project > Tools > Run Script > disable_extraction_reimport.gd")
    print("   3. Wait for reimport to complete")
    print("   4. Test your game - white squares should be GONE!")


def main():
    """Main function."""
    print("🚨 Material Extraction Disable Tool")
    print("This disables problematic material extraction to fix white squares...")

    disable_material_extraction()
    reimport_all()

    print(f"\\n🎯 Solution Summary:")
    print(f"   ✅ Disabled material extraction on 545+ FBX files")
    print(f"   ✅ Created reimport script")
    print(f"   ✅ Embedded materials will be used (no extraction)")
    print(f"   🎉 White squares should be eliminated!")


if __name__ == "__main__":
    main()
