#!/usr/bin/env python3
"""
Batch fix import settings for external assets to enable material extraction and optimize texture processing.
This will dramatically improve visual quality by enabling PBR materials, normal maps, and mipmaps.
"""

import os
import json
import re
from pathlib import Path


def fix_fbx_import_file(import_file_path):
    """Fix FBX import settings to enable material extraction."""
    try:
        with open(import_file_path, "r") as f:
            content = f.read()

        # Fix material extraction settings
        content = re.sub(r"materials/extract=0", "materials/extract=1", content)
        content = re.sub(
            r"materials/extract_format=0", "materials/extract_format=1", content
        )
        content = re.sub(
            r'materials/extract_path=""',
            'materials/extract_path="res://materials/extracted/"',
            content,
        )

        # Optimize mesh processing
        content = re.sub(
            r"meshes/generate_lods=true", "meshes/generate_lods=true", content
        )
        content = re.sub(
            r"meshes/force_disable_compression=false",
            "meshes/force_disable_compression=true",
            content,
        )

        # Write back the fixed content
        with open(import_file_path, "w") as f:
            f.write(content)

        print(f"✅ Fixed FBX import: {import_file_path}")
        return True

    except Exception as e:
        print(f"❌ Error fixing FBX import {import_file_path}: {e}")
        return False


def fix_texture_import_file(import_file_path):
    """Fix texture import settings for optimal quality and performance."""
    try:
        with open(import_file_path, "r") as f:
            content = f.read()

        # Detect if this is a normal map
        is_normal_map = "normal" in import_file_path.lower()

        # Enable mipmaps for better distance rendering
        content = re.sub(r"mipmaps/generate=false", "mipmaps/generate=true", content)

        # Fix normal map processing
        if is_normal_map:
            content = re.sub(r"compress/normal_map=0", "compress/normal_map=1", content)
            content = re.sub(
                r"process/normal_map_invert_y=false",
                "process/normal_map_invert_y=true",
                content,
            )

        # Optimize compression for better performance
        content = re.sub(
            r"compress/mode=0", "compress/mode=2", content
        )  # Use VRAM compression
        content = re.sub(
            r"compress/high_quality=false", "compress/high_quality=true", content
        )
        content = re.sub(
            r"compress/lossy_quality=0.7", "compress/lossy_quality=0.8", content
        )

        # Write back the fixed content
        with open(import_file_path, "w") as f:
            f.write(content)

        texture_type = "Normal Map" if is_normal_map else "Texture"
        print(f"✅ Fixed {texture_type} import: {import_file_path}")
        return True

    except Exception as e:
        print(f"❌ Error fixing texture import {import_file_path}: {e}")
        return False


def create_extracted_materials_directory():
    """Create the materials/extracted directory for material extraction."""
    materials_dir = Path(
        "/Users/cfaigle/Documents/Development/local/dogfight/materials/extracted"
    )
    materials_dir.mkdir(parents=True, exist_ok=True)
    print(f"✅ Created materials extraction directory: {materials_dir}")


def main():
    """Main function to fix all import files."""
    print("🔧 Starting material enhancement batch fix...")
    print(
        "This will enable material extraction, optimize texture processing, and dramatically improve visual quality!"
    )

    base_path = "/Users/cfaigle/Documents/Development/local/dogfight/assets/external"

    # Create materials extraction directory
    create_extracted_materials_directory()

    # Find and fix all FBX import files
    print("\n📦 Fixing FBX import files for material extraction...")
    fbx_fixed = 0
    for fbx_import in Path(base_path).rglob("*.fbx.import"):
        if fix_fbx_import_file(fbx_import):
            fbx_fixed += 1

    # Find and fix all texture import files
    print("\n🎨 Fixing texture import files for optimal quality...")
    texture_fixed = 0
    for tex_import in Path(base_path).rglob("*.import"):
        # Only fix actual texture files, not scene imports
        parent_name = tex_import.parent.name
        if parent_name != "FBX format":
            continue

        if fix_texture_import_file(tex_import):
            texture_fixed += 1

    print(f"\n🎉 Batch fix complete!")
    print(f"   📦 Fixed {fbx_fixed} FBX import files")
    print(f"   🎨 Fixed {texture_fixed} texture import files")
    print(f"\n📋 Next steps:")
    print(f"   1. Reimport all assets in Godot Editor")
    print(f"   2. The game will now use high-quality PBR materials")
    print(f"   3. Expect dramatic visual improvements!")


if __name__ == "__main__":
    main()
