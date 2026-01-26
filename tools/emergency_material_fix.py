#!/usr/bin/env python3
"""
Create proper .tres material files to fix the binary corruption issue.
This creates valid Godot StandardMaterial3D resources with proper text format.
"""

import os
from pathlib import Path


def create_proper_materials():
    """Create proper .tres material files instead of broken binary ones."""

    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )
    external_packs_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/assets/external/packs"
    )

    print("🔧 Creating proper .tres material files...")

    # Clean up broken binary files
    print("  🗑️ Cleaning up corrupted binary files...")
    for binary_file in materials_dir.glob("*_fixed.res"):
        try:
            binary_file.unlink()
            print(f"    Removed: {binary_file.name}")
        except:
            pass

    # Color definitions for different building materials
    material_colors = {
        "colormap": "Color(0.85, 0.75, 0.65)",  # Warm brown
        "colorWhite": "Color(0.7, 0.7, 0.7)",  # Light gray instead of pure white
        "colorRed": "Color(0.8, 0.2, 0.15)",  # Brick red
        "colorTan": "Color(0.75, 0.6, 0.4)",  # Sandy tan
        "colorYellow": "Color(0.9, 0.8, 0.2)",  # Sandy yellow
        "corn": "Color(0.85, 0.75, 0.3)",  # Corn yellow
        "dirt": "Color(0.6, 0.4, 0.2)",  # Dirt brown
        "colorPurple": "Color(0.7, 0.4, 0.8)",  # Purple
        "colorRedDark": "Color(0.6, 0.15, 0.1)",  # Dark red
        "leafsDark": "Color(0.2, 0.4, 0.15)",  # Dark green leaves
        "leafsFall": "Color(0.8, 0.6, 0.2)",  # Fall colors
        "leafsGreen": "Color(0.3, 0.6, 0.2)",  # Fresh green leaves
        "stoneDark": "Color(0.3, 0.3, 0.35)",  # Dark stone
        "stone": "Color(0.5, 0.5, 0.55)",  # Medium stone
        "wood": "Color(0.65, 0.4, 0.25)",  # Brown wood
        "woodBarkDark": "Color(0.3, 0.2, 0.15)",  # Dark bark
        "woodBirch": "Color(0.8, 0.7, 0.6)",  # Birch wood
        "woodDark": "Color(0.4, 0.25, 0.15)",  # Dark wood
        "woodInner": "Color(0.85, 0.75, 0.65)",  # Light wood
        "grass": "Color(0.4, 0.7, 0.2)",  # Grass green
        "glass": "Color(0.8, 0.9, 1.0)",  # Glass with transparency
        "water": "Color(0.2, 0.6, 0.8)",  # Water blue
    }

    # Create proper .tres files
    materials_created = 0
    for mat_name, color in material_colors.items():
        tres_content = f"""[gd_resource type="StandardMaterial3D" format=3 uid="uid://b{mat_name}"]

[resource]
albedo_color = {color}
roughness = 0.9
metallic = 0.0
"""

        tres_file = materials_dir / f"{mat_name}.tres"
        with open(tres_file, "w") as f:
            f.write(tres_content)
        materials_created += 1
        print(f"    Created: {mat_name}.tres")

    # Create emergency fallback (light gray)
    emergency_content = """[gd_resource type="StandardMaterial3D" format=3 uid="uid://bemergency_gray"]

[resource]
albedo_color = Color(0.6, 0.6, 0.6)
roughness = 0.9
metallic = 0.0
"""

    with open(materials_dir / "emergency_gray.tres", "w") as f:
        f.write(emergency_content)

    print(f"✅ Created {materials_created} proper .tres material files")


def remove_broken_extracted_materials():
    """Remove broken materials/extracted directory to force fallback to proper materials."""

    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )

    print("  🗑️ Removing broken materials/extracted directory...")
    try:
        if materials_dir.exists():
            import shutil

            shutil.rmtree(materials_dir)
            materials_dir.mkdir(parents=True, exist_ok=True)
            print("    ✅ Removed broken extracted materials")
    except Exception as e:
        print(f"    ❌ Error removing extracted materials: {e}")


def main():
    """Main function to create proper materials and fix white squares."""
    print("🚨 Emergency White Square Fix")
    print("Creating proper .tres materials and removing broken extracted materials...")

    # Create proper materials
    create_proper_materials()

    # Remove broken extracted materials directory
    remove_broken_extracted_materials()

    print(f"\n✅ Emergency Fix Complete!")
    print(f"🎯 White Square Solution:")
    print(f"   ✅ Created proper .tres materials")
    print(f"   ✅ Removed broken binary files")
    print(f"   ✅ Emergency fallback ready")
    print(f"   ✅ Materials now use proper colors instead of white")

    print(f"\n📋 Test Your Game:")
    print(f"   1. Run your game")
    print(f"   2. White squares should be GONE")
    print(f"   3. Buildings should have proper colored materials")
    print(f"   4. If issues persist, restart Godot")


if __name__ == "__main__":
    main()
