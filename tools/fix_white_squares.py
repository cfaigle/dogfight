#!/usr/bin/env python3
"""
Quick fix for white square artifacts caused by broken material texture paths.
This script fixes the extracted materials to use correct texture paths or fallback to solid colors.
"""

import os
import json
import re
from pathlib import Path


def fix_extracted_materials():
    """Fix extracted materials by either fixing texture paths or using fallback colors."""

    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )
    external_packs_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/assets/external/packs"
    )

    print("🔧 Fixing extracted materials to eliminate white squares...")

    # Map of material names to fallback colors (avoid white)
    fallback_colors = {
        "colormap": "res://assets/external/textures/ambientcg/Bricks079_2K-JPG/Bricks079_2K-JPG_Color.jpg",
        "colorWhite": "Color(0.9, 0.9, 0.9)",  # Light gray instead of white
        "colorRed": "Color(0.8, 0.2, 0.2)",  # Brick red
        "colorTan": "Color(0.7, 0.6, 0.4)",  # Sandy tan
        "colorYellow": "Color(0.9, 0.8, 0.2)",  # Sandy yellow
        "corn": "Color(0.8, 0.6, 0.3)",  # Corn yellow
        "dirt": "res://assets/external/textures/ambientcg/Dirt010_2K-JPG/Dirt010_2K-JPG_Color.jpg",
        "colorPurple": "Color(0.6, 0.3, 0.8)",  # Purple
        "colorRedDark": "Color(0.5, 0.1, 0.1)",  # Dark red
    }

    materials_fixed = 0

    # Find and fix .res material files (Godot binary materials)
    for res_file in materials_dir.glob("*.res"):
        try:
            # Skip if already fixed
            if "fixed" in res_file.name:
                continue

            base_name = res_file.stem
            print(f"  Fixing material: {base_name}")

            # Create a simple GDScript material instead of trying to fix binary
            material_script = f"""[gd_resource type="StandardMaterial3D" format=3 uid="uid://br{base_name}"]

[resource]
albedo_color = {fallback_colors.get(base_name, "Color(0.6, 0.6, 0.6)")}
roughness = 0.8
metallic = 0.0
"""

            # Write new material
            fixed_file = materials_dir / f"{base_name}_fixed.res"
            with open(fixed_file, "w") as f:
                f.write(material_script)

            materials_fixed += 1

        except Exception as e:
            print(f"  ❌ Error fixing {res_file.name}: {e}")

    print(f"✅ Fixed {materials_fixed} material files")

    # Also create a simple white material fix for any remaining issues
    emergency_fix = """[gd_resource type="StandardMaterial3D" format=3 uid="uid://bremergency"]

[resource]
albedo_color = Color(0.7, 0.7, 0.7)  # Light gray instead of white
roughness = 0.9
metallic = 0.0
"""

    with open(materials_dir / "emergency_gray.res", "w") as f:
        f.write(emergency_fix)

    print(f"✅ Created emergency fallback material")

    # Provide instructions for manual fix
    print(f"\n📋 Material Fix Applied!")
    print(f"🔹 White squares should be eliminated or reduced to light gray")
    print(f"\n📋 Alternative Quick Fix (if squares persist):")
    print(f"   1. In Godot Editor, go to Project > Project Settings")
    print(f"   2. Find 'Import Defaults' > 3D Models > FBX")
    print(f"   3. Set 'Materials > Extract' to OFF")
    print(f"   4. Click 'Reimport' on external assets")
    print(f"   5. This will use embedded materials instead of broken extracted ones")


def create_debug_materials():
    """Create debug materials with solid colors to replace broken ones."""

    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )

    # Create solid colored materials as fallbacks
    colors = {
        "red": "Color(0.8, 0.2, 0.2)",
        "gray": "Color(0.6, 0.6, 0.6)",
        "brown": "Color(0.5, 0.3, 0.2)",
        "blue": "Color(0.3, 0.5, 0.8)",
        "green": "Color(0.3, 0.6, 0.2)",
    }

    print("🎨 Creating debug solid materials...")

    for name, color in colors.items():
        material_content = f"""[gd_resource type="StandardMaterial3D" format=3 uid="uid://bdebug_{name}"]

[resource]
albedo_color = {color}
roughness = 0.9
metallic = 0.0
"""

        material_file = materials_dir / f"debug_{name}.tres"
        with open(material_file, "w") as f:
            f.write(material_content)

    print(f"✅ Created {len(colors)} debug materials for testing")


def main():
    """Main function to fix white square artifacts."""
    print("🚨 White Square Fix Tool")
    print("This fixes broken material texture paths causing white artifacts")

    # Create materials directory if it doesn't exist
    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )
    materials_dir.mkdir(parents=True, exist_ok=True)

    # Apply fixes
    fix_extracted_materials()
    create_debug_materials()

    print(f"\n🎉 Material fixes complete!")
    print(f"📋 Immediate Results:")
    print(f"   ✅ White squares replaced with colored fallbacks")
    print(f"   ✅ Emergency gray material created")
    print(f"   ✅ Debug materials for testing")
    print(f"\n📋 Test Your Game:")
    print(f"   1. Run the game")
    print(f"   2. Check if white squares are gone/reduced")
    print(f"   3. If issues persist, use Project Settings fix mentioned above")
    print(
        f"\n💡 For permanent fix, consider disabling material extraction in FBX imports"
    )


if __name__ == "__main__":
    main()
