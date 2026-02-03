#!/usr/bin/env python3
"""Fetch CC0 (no-attribution) asset packs and generate assets/external/manifest.json.

Designed for Dogfight1940 (Godot 4). Uses only the Python standard library.

What it does:
- Finds your Godot project root (looks for project.godot).
- Downloads selected Kenney asset pack ZIPs by scraping the Kenney asset page for the current ZIP link.
- (Optional) Downloads selected ambientCG texture ZIPs via their public 'get?file=' endpoint.
- Extracts everything under assets/external/packs/...
- Generates assets/external/manifest.json containing:
  - Current single-mesh keys used by the project (backwards compatible)
  - Variant pools under "variants" for future multi-type placement

Run:
  python3 tools/fetch_assets.py --project /path/to/Dogfight1940
  python3 tools/fetch_assets.py  # if you run it from inside the project tree

Local Files Mode:
- Place ZIP files in assets/ingest/ directory
- Run with --local-only to use local files instead of downloading
- Script will copy files from assets/ingest/ to assets/external/packs/

Examples:
  # Download everything from internet (default behavior)
  python3 tools/fetch_assets.py

  # Use only local files from assets/ingest/
  python3 tools/fetch_assets.py --local-only

  # Skip ambientCG textures
  python3 tools/fetch_assets.py --no-textures

  # Use local files and skip textures
  python3 tools/fetch_assets.py --local-only --no-textures

  # Include WW2-themed assets and textures
  python3 tools/fetch_assets.py --ww2-assets --ww2-textures

  # Local WW2 assets only
  python3 tools/fetch_assets.py --local-only --ww2-assets --ww2-textures

  # Include Poly Haven high-quality assets (large downloads)
  python3 tools/fetch_assets.py --polyhaven

  # Complete setup with all assets
  python3 tools/fetch_assets.py --ww2-assets --ww2-textures --polyhaven

  # Fetch ALL available assets (Kenney + Poly Haven + textures)
  python3 tools/fetch_assets.py --all

  # List available assets in assets/ingest/ without downloading
  python3 tools/fetch_assets.py --list-assets

  # Local mode with all asset types
  python3 tools/fetch_assets.py --local-only --all

Notes:
- If a provider changes page structure, the scraper may need tweaks.
- This script does NOT modify your Godot scenes/scripts — it only downloads assets + writes manifest.
- Local files in assets/ingest/ take precedence over internet downloads when --local-only is used.
- Poly Haven downloads have enhanced URL parsing with comprehensive error handling.
  - Automatic download attempts multiple URL patterns
  - Provides detailed error messages with helpful tips
  - Falls back gracefully to manual download instructions
  - Manual downloads should be placed in assets/ingest/
- The --list-assets option helps you see what's available locally before downloading.
- The --all option enables all asset types for a complete setup.
- Kenney assets work best with local files due to their website structure changes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from fnmatch import fnmatch
from pathlib import Path
from typing import Iterable, List, Optional, Tuple

USER_AGENT = "Dogfight1940AssetFetcher/1.0 (+https://godotengine.org)"


@dataclass(frozen=True)
class KenneyPack:
    slug: str
    page_url: str


@dataclass(frozen=True)
class AmbientCGTexture:
    file_name: str  # e.g. "Concrete023_2K-JPG.zip"


@dataclass(frozen=True)
class PolyHavenAsset:
    file_name: str  # e.g. "hangar_01.zip"
    url: str        # Direct download URL or page URL


# --- Recommended CC0 packs (no attribution required) ---
# These are intentionally low-poly-friendly for large instance counts.
KENNEY_PACKS: List[KenneyPack] = [
    KenneyPack("kenney_building-kit", "https://kenney.nl/assets/building-kit"),
    KenneyPack("kenney_city-kit-suburban", "https://kenney.nl/assets/city-kit-suburban"),
    KenneyPack("kenney_city-kit-industrial", "https://kenney.nl/assets/city-kit-industrial"),
    KenneyPack("kenney_city-kit-roads", "https://kenney.nl/assets/city-kit-roads"),
    KenneyPack("kenney_nature-kit", "https://kenney.nl/assets/nature-kit"),
]

# Additional Kenney packs for WW2 theme (optional)
KENNEY_WW2_PACKS: List[KenneyPack] = [
    KenneyPack("kenney_ww2", "https://kenney.nl/assets/ww2"),
    KenneyPack("kenney_tanks", "https://kenney.nl/assets/tanks"),
    KenneyPack("kenney_military-pack", "https://kenney.nl/assets/military-pack"),
]

# ambientCG is CC0; these are useful WW2-ish surface materials.
# Updated with verified available textures (as of 2026)
AMBIENTCG_TEXTURES: List[AmbientCGTexture] = [
    AmbientCGTexture("Concrete023_2K-JPG.zip"),      # Basic concrete
    AmbientCGTexture("Asphalt012_2K-JPG.zip"),       # Roads/pavement
    AmbientCGTexture("MetalPlates006_2K-JPG.zip"),    # Industrial metal
    AmbientCGTexture("Bricks079_2K-JPG.zip"),        # Updated brick texture
    AmbientCGTexture("WoodPlanks010_2K-JPG.zip"),    # Wood planks
    AmbientCGTexture("RoofTiles005_2K-JPG.zip"),     # Roof materials
    AmbientCGTexture("Sand002_2K-JPG.zip"),          # Beach/sand
    AmbientCGTexture("Grass004_2K-JPG.zip"),         # Ground cover
]

# Additional ambientCG textures for WW2 theme (optional)
# Using more realistic/available texture names
AMBIENTCG_WW2_TEXTURES: List[AmbientCGTexture] = [
    AmbientCGTexture("MetalRusted001_2K-JPG.zip"),    # Rusty metal
    AmbientCGTexture("ConcreteDamaged001_2K-JPG.zip"), # Damaged concrete
    AmbientCGTexture("WoodOld001_2K-JPG.zip"),        # Aged wood
    AmbientCGTexture("FabricWorn001_2K-JPG.zip"),     # For tents/tarps
    AmbientCGTexture("Dirt010_2K-JPG.zip"),           # Battlefield terrain
]

# Poly Haven CC0 assets - these are larger downloads but high quality
# Note: Poly Haven URLs may need updating as their site structure changes
POLYHAVEN_ASSETS: List[PolyHavenAsset] = [
    # Military/Industrial buildings
    PolyHavenAsset("hangar_01.zip", "https://polyhaven.com/a/hangar_01"),
    PolyHavenAsset("warehouse_01.zip", "https://polyhaven.com/a/warehouse_01"),
    PolyHavenAsset("factory_01.zip", "https://polyhaven.com/a/factory_01"),
    
    # WW2-era props (hypothetical - check Poly Haven for actual assets)
    # PolyHavenAsset("tank_destroyed.zip", "https://polyhaven.com/a/tank_destroyed"),
    # PolyHavenAsset("control_tower.zip", "https://polyhaven.com/a/control_tower"),
]

# Poly Haven textures - high quality PBR materials
# Note: Poly Haven uses different naming conventions, these may need manual download
POLYHAVEN_TEXTURES: List[AmbientCGTexture] = [
    # Using more standard naming that's likely to be available
    AmbientCGTexture("RustedIron001_2K-JPG.zip"),
    AmbientCGTexture("OldConcrete001_2K-JPG.zip"),
    AmbientCGTexture("WornMetal001_2K-JPG.zip"),
]


def _http_get(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _download(url: str, dst: Path, timeout: int = 120) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        total = resp.headers.get("Content-Length")
        total_i = int(total) if total and total.isdigit() else None
        read = 0
        chunk = 1024 * 256
        with open(dst, "wb") as f:
            while True:
                buf = resp.read(chunk)
                if not buf:
                    break
                f.write(buf)
                read += len(buf)
                if total_i:
                    pct = int(100 * read / total_i)
                    sys.stdout.write(f"\r  -> {dst.name}: {pct}%")
                    sys.stdout.flush()
    if total_i:
        sys.stdout.write("\n")


def find_project_root(start: Path) -> Path:
    start = start.resolve()
    if start.is_file():
        start = start.parent
    cur = start
    for _ in range(12):
        if (cur / "project.godot").exists():
            return cur
        if cur.parent == cur:
            break
        cur = cur.parent
    raise FileNotFoundError(
        f"Could not find project.godot above {start}. Use --project /path/to/project."
    )


def get_ingest_dir(project_root: Path) -> Path:
    """Get the assets/ingest/ directory path."""
    return project_root / "assets" / "ingest"


def ensure_ingest_dir_exists(project_root: Path) -> Path:
    """Ensure the assets/ingest/ directory exists, create if needed."""
    ingest_dir = get_ingest_dir(project_root)
    ingest_dir.mkdir(parents=True, exist_ok=True)
    return ingest_dir


def find_local_zip(packs_dir: Path, pack_slug: str) -> Optional[Path]:
    """Look for local ZIP files in assets/ingest/ directory with improved matching."""
    ingest_dir = get_ingest_dir(packs_dir)
    if ingest_dir.exists():
        # Normalize the pack slug for comparison
        normalized_slug = pack_slug.lower().replace('_', '').replace('-', '')
        
        for zip_file in ingest_dir.glob("*.zip"):
            # Normalize the zip file name for comparison
            normalized_zip_name = zip_file.name.lower().replace('_', '').replace('-', '')
            
            # Check if the normalized slug is in the normalized zip name
            if normalized_slug in normalized_zip_name:
                return zip_file
                
            # Also check for partial matches (e.g., "kenney_building" in "kenney_building-kit.zip")
            if normalized_slug.replace('kenney', '').strip() in normalized_zip_name:
                return zip_file
    return None


def download_to_ingest(url: str, file_name: str, project_root: Path) -> Path:
    """Download a file directly to assets/ingest/ directory."""
    ingest_dir = ensure_ingest_dir_exists(project_root)
    dst_path = ingest_dir / file_name
    
    print(f"  📥 Downloading to ingest: {file_name}")
    _download(url, dst_path)
    
    return dst_path


def list_available_local_assets(project_root: Path) -> List[str]:
    """List all available ZIP files in assets/ingest/ directory."""
    ingest_dir = get_ingest_dir(project_root)
    if ingest_dir.exists():
        return sorted([f.name for f in ingest_dir.glob("*.zip")])
    return []


def extract_zip(zip_path: Path, dst_dir: Path) -> None:
    dst_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(dst_dir)


def _pick_best_kenney_zip_link(html: str) -> Optional[str]:
    # Kenney pages include direct ZIP links behind the "Continue without donating" button.
    # We choose the last *.zip link on the page (usually the actual asset zip).
    zips = re.findall(r"https://kenney\\.nl/[^\"'<>\s]+\\.zip", html)
    if not zips:
        return None
    # Prefer kenney_*.zip files
    for cand in reversed(zips):
        if "/media/pages/assets/" in cand and "kenney_" in cand:
            return cand
    return zips[-1]


def fetch_kenney_pack(pack: KenneyPack, packs_dir: Path, project_root: Path) -> Path:
    print(f"\n[Kenney] {pack.slug}")
    
    # Get ingest directory
    ingest_dir = ensure_ingest_dir_exists(project_root)
    
    # Check for local ZIP file in ingest
    local_zip = None
    for zip_file in ingest_dir.glob("*.zip"):
        if pack.slug.lower() in zip_file.name.lower():
            local_zip = zip_file
            break
    
    if local_zip:
        print(f"  ✅ Found in ingest: {local_zip.name}")
    else:
        # Download from internet to ingest directory
        print(f"  📥 Downloading from {pack.page_url}")
        try:
            html = _http_get(pack.page_url).decode("utf-8", errors="replace")
            zip_url = _pick_best_kenney_zip_link(html)
            if not zip_url:
                raise RuntimeError(f"Could not find download link on {pack.page_url}")

            # Download directly to ingest
            local_zip = ingest_dir / f"{pack.slug}.zip"
            _download(zip_url, local_zip)
            print(f"  ✅ Downloaded to ingest: {local_zip.name}")
        except Exception as e:
            print(f"  ❌ Download failed: {e}")
            print(f"  💡 Please download {pack.slug}.zip manually to assets/ingest/")
            raise

    # Now extract from ingest to packs directory
    print(f"  📂 Extracting from ingest to packs")
    packs_dir.mkdir(parents=True, exist_ok=True)
    
    out_dir = packs_dir / pack.slug
    if out_dir.exists():
        shutil.rmtree(out_dir)
    
    extract_zip(local_zip, out_dir)
    print(f"  ✅ Extracted to: {out_dir}")
    
    return out_dir


def fetch_ambientcg_textures(textures: List[AmbientCGTexture], textures_dir: Path, project_root: Path) -> List[Path]:
    print("\n[ambientCG] textures")
    extracted_dirs: List[Path] = []
    
    # Get ingest directory
    ingest_dir = ensure_ingest_dir_exists(project_root)
    
    for tex in textures:
        # Check for local file in ingest first
        local_zip = None
        for zip_file in ingest_dir.glob("*.zip"):
            if tex.file_name.lower() in zip_file.name.lower():
                local_zip = zip_file
                break
        
        if local_zip:
            print(f"  ✅ Found in ingest: {local_zip.name}")
        else:
            # Download from internet to ingest directory
            url = f"https://ambientcg.com/get?file={tex.file_name}"
            print(f"  📥 Downloading {tex.file_name}")
            try:
                local_zip = ingest_dir / tex.file_name
                _download(url, local_zip)
                print(f"  ✅ Downloaded to ingest: {local_zip.name}")
            except urllib.error.HTTPError as e:
                print(f"  ❌ Failed ({e.code}) for {tex.file_name} — skipping")
                continue
            except Exception as e:
                print(f"  ❌ Download failed for {tex.file_name}: {e} — skipping")
                continue
        
        # Process from ingest to textures directory
        print(f"  📁 Processing from ingest: {local_zip.name}")
        
        # Create textures/_zips directory
        zips_dir = textures_dir / "_zips"
        zips_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy to textures/_zips directory
        out_zip = zips_dir / tex.file_name
        shutil.copy2(local_zip, out_zip)
        
        # Extract to textures directory
        out_dir = textures_dir / tex.file_name.replace(".zip", "")
        if out_dir.exists():
            shutil.rmtree(out_dir)
        
        print(f"  📂 Extracting to: {out_dir}")
        extract_zip(out_zip, out_dir)
        extracted_dirs.append(out_dir)
        print(f"  ✅ Successfully extracted!")
        
        # be polite
        time.sleep(0.25)
    return extracted_dirs


def _parse_polyhaven_download_url(html: str) -> Optional[str]:
    """Parse Poly Haven page HTML to find direct download URL."""
    # Poly Haven's actual structure - look for various download patterns
    patterns = [
        # Direct CDN download links (most reliable)
        r"https://cdn\.polyhaven\.com/asset_downloads/[^\"'< >\s]+\.zip",
        
        # Alternative download patterns found on Poly Haven
        r"https://polyhaven\.com/a/[^\"'< >\s]+/download[^\"'< >\s]*",
        r"https://polyhaven\.com/download_asset[^\"'< >\s]*",
        r"https://[^\"'< >\s]+polyhaven[^\"'< >\s]+\.zip",
        
        # Query parameter based downloads
        r"https://[^\"'< >\s]+/download\?file=[^\"'< >\s]+\.zip",
        r"https://[^\"'< >\s]+/get\?file=[^\"'< >\s]+\.zip",
        
        # Button links and API endpoints
        r"https://api\.polyhaven\.com/[^\"'< >\s]+\.zip",
        r"https://[^\"'< >\s]+/assets/[^\"'< >\s]+/download[^\"'< >\s]*",
    ]
    
    for pattern in patterns:
        matches = re.findall(pattern, html)
        if matches:
            # Return the first match that looks like a valid download URL
            for match in matches:
                if (match.endswith('.zip') or 
                    'download' in match.lower() or
                    'polyhaven.com/a/' in match):
                    return match
    
    # If no specific patterns matched, try to find any polyhaven link that might be a download
    polyhaven_links = re.findall(r"https://[^\"'< >\s]+polyhaven[^\"'< >\s]+", html)
    for link in polyhaven_links:
        if ('download' in link.lower() or 
            'asset' in link.lower() or
            'cdn' in link.lower()):
            return link
    
    return None


def fetch_polyhaven_asset(asset: PolyHavenAsset, packs_dir: Path, project_root: Path) -> Optional[Path]:
    """Fetch a single Poly Haven asset with enhanced download logic and better error handling."""
    print(f"\n[Poly Haven] {asset.file_name}")
    
    # Check for local file first
    local_zip = None
    ingest_dir = get_ingest_dir(project_root)
    if ingest_dir.exists():
        for zip_file in ingest_dir.glob("*.zip"):
            # More flexible matching for Poly Haven assets
            if (asset.file_name.lower().replace('_', '').replace('-', '') in 
                zip_file.name.lower().replace('_', '').replace('-', '')):
                local_zip = zip_file
                break
    
    if local_zip:
        print(f"  ✅ Found local file: {local_zip}")
    else:
        # Try to download from Poly Haven to ingest directory
        print(f"  from {asset.url}")
        print(f"  🔍 Searching for download link...")
        
        try:
            html = _http_get(asset.url).decode("utf-8", errors="replace")
            download_url = _parse_polyhaven_download_url(html)
            
            if download_url:
                print(f"  ✅ Found download URL: {download_url}")
                print(f"  📥 Downloading to ingest...")
                local_zip = download_to_ingest(download_url, asset.file_name, project_root)
                print(f"  ✅ Downloaded to ingest: {local_zip.name}")
            else:
                print(f"  ❌ Could not find download URL on {asset.url}")
                print(f"  💡 Tip: Poly Haven may require manual download.")
                print(f"  📁 Please download {asset.file_name} manually")
                print(f"     and place it in: assets/ingest/")
                print(f"  🔗 Asset page: {asset.url}")
                return None
        except urllib.error.HTTPError as e:
            print(f"  ❌ HTTP Error {e.code}: {e.reason}")
            print(f"  💡 The asset page may not exist or require authentication.")
            print(f"  🔗 Please check: {asset.url}")
            return None
        except Exception as e:
            print(f"  ❌ Download failed: {e}")
            print(f"  💡 Network issues or website changes may have occurred.")
            print(f"  🔧 Try again later or download manually from: {asset.url}")
            return None
    
    # Process from ingest to packs directory
    print(f"  📁 Processing from ingest: {local_zip.name}")
    
    # Ensure packs directory exists
    packs_dir.mkdir(parents=True, exist_ok=True)
    
    # Copy to packs directory with polyhaven prefix
    out_zip = packs_dir / f"polyhaven_{asset.file_name}"
    shutil.copy2(local_zip, out_zip)
    
    # Extract the asset
    out_dir = packs_dir / f"polyhaven_{asset.file_name.replace('.zip', '')}"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    
    print(f"  📂 Extracting to: {out_dir}")
    try:
        extract_zip(out_zip, out_dir)
        print(f"  ✅ Successfully extracted!")
    except Exception as e:
        print(f"  ❌ Extraction failed: {e}")
        print(f"  💡 The ZIP file may be corrupted or password-protected.")
        return None
    
    return out_dir


def _walk_files(root: Path, exts: Tuple[str, ...]) -> List[Path]:
    out: List[Path] = []
    for p in root.rglob("*"):
        if p.is_file() and p.suffix.lower() in exts:
            out.append(p)
    return out


def _rel_res_path(project_root: Path, abs_path: Path) -> str:
    rel = abs_path.resolve().relative_to(project_root.resolve())
    return "res://" + str(rel).replace("\\", "/")


def _select_by_patterns(paths: Iterable[Path], include: List[str], exclude: List[str]) -> List[Path]:
    out: List[Path] = []
    for p in paths:
        name = p.name.lower()
        ok = any(fnmatch(name, pat.lower()) for pat in include) if include else True
        if not ok:
            continue
        if any(fnmatch(name, pat.lower()) for pat in exclude):
            continue
        out.append(p)
    return out


def build_variant_pools(project_root: Path, pack_dirs: List[Path]) -> dict:
    # Prefer GLB/GLTF, then FBX/OBJ.
    model_files: List[Path] = []
    for d in pack_dirs:
        model_files += _walk_files(d, (".glb", ".gltf", ".fbx", ".obj"))

    # Rough categorization by filename. This is heuristic on purpose.
    suburban = [p for p in model_files if "suburban" in str(p).lower()]
    industrial = [p for p in model_files if "industrial" in str(p).lower()]
    building_kit = [p for p in model_files if "building" in str(p).lower() and "kit" in str(p).lower()]
    nature = [p for p in model_files if "nature" in str(p).lower()]

    euro_candidates = _select_by_patterns(
        suburban + building_kit,
        include=["*house*", "*building*", "*home*", "*residence*", "*hut*"],
        exclude=["*door*", "*window*", "*fence*", "*road*", "*lamp*", "*sign*", "*car*"],
    )
    ind_candidates = _select_by_patterns(
        industrial + building_kit,
        include=["*factory*", "*warehouse*", "*hangar*", "*building*", "*shed*", "*container*"],
        exclude=["*road*", "*lamp*", "*sign*", "*car*"],
    )
    shack_candidates = _select_by_patterns(
        suburban + building_kit,
        include=["*hut*", "*cabin*", "*shack*", "*house*", "*small*"],
        exclude=["*door*", "*window*", "*fence*"],
    )
    tree_candidates = _select_by_patterns(
        nature,
        include=["*tree*", "*pine*", "*palm*"],
        exclude=["*log*", "*stump*", "*leaf*"],
    )

    # Classify trees by type
    conifer_candidates = [p for p in tree_candidates if any(k in p.name.lower() for k in ["pine", "fir", "spruce", "conifer"])]
    palm_candidates = [p for p in tree_candidates if "palm" in p.name.lower()]
    broadleaf_candidates = [p for p in tree_candidates if p not in conifer_candidates and p not in palm_candidates]

    # If no specific types found, use all as broadleaf fallback
    if not conifer_candidates and not palm_candidates and tree_candidates:
        broadleaf_candidates = tree_candidates

    # Convert to res:// paths
    def rp(xs: List[Path]) -> List[str]:
        return [_rel_res_path(project_root, p) for p in xs]

    return {
        "euro_buildings": rp(euro_candidates)[:24],
        "industrial_buildings": rp(ind_candidates)[:24],
        "beach_shacks": rp(shack_candidates)[:24],
        "trees_conifer": rp(conifer_candidates)[:32],
        "trees_broadleaf": rp(broadleaf_candidates)[:32],
        "trees_palm": rp(palm_candidates)[:32],
    }


def build_texture_sets(project_root: Path, textures_dir: Path) -> dict:
    """Build texture set mappings from downloaded ambientCG textures."""
    texture_sets = {}

    if not textures_dir.exists():
        return texture_sets

    # Map texture directories to logical keys
    texture_mappings = {
        "building_atlas_euro": ["Bricks079", "Concrete023"],
        "building_atlas_industrial": ["MetalPlates006", "Concrete023"],
        "terrain_grass": ["Grass004"],
        "terrain_pavement": ["Asphalt012", "Concrete023"],
    }

    for key, texture_names in texture_mappings.items():
        # Find first available texture set from the list
        for tex_name in texture_names:
            tex_dirs = list(textures_dir.glob(f"{tex_name}*"))
            if tex_dirs:
                tex_dir = tex_dirs[0]
                base_name = tex_dir.name.replace("_2K-JPG", "")

                # Build texture set with PBR maps
                texture_set = {}

                # Color/Albedo
                color_files = list(tex_dir.glob(f"{base_name}*Color.jpg"))
                if color_files:
                    texture_set["albedo"] = _rel_res_path(project_root, color_files[0])

                # Normal map (use OpenGL format for Godot)
                normal_files = list(tex_dir.glob(f"{base_name}*NormalGL.jpg"))
                if normal_files:
                    texture_set["normal"] = _rel_res_path(project_root, normal_files[0])

                # Roughness
                roughness_files = list(tex_dir.glob(f"{base_name}*Roughness.jpg"))
                if roughness_files:
                    texture_set["roughness"] = _rel_res_path(project_root, roughness_files[0])

                # Metalness (not all textures have this)
                metalness_files = list(tex_dir.glob(f"{base_name}*Metalness.jpg"))
                if metalness_files:
                    texture_set["metallic"] = _rel_res_path(project_root, metalness_files[0])

                # Ambient Occlusion
                ao_files = list(tex_dir.glob(f"{base_name}*AmbientOcclusion.jpg"))
                if ao_files:
                    texture_set["ao"] = _rel_res_path(project_root, ao_files[0])

                # Displacement/Height
                disp_files = list(tex_dir.glob(f"{base_name}*Displacement.jpg"))
                if disp_files:
                    texture_set["height"] = _rel_res_path(project_root, disp_files[0])

                if texture_set:
                    texture_sets[key] = texture_set
                    break  # Found texture for this key, move to next

    return texture_sets


def write_manifest(project_root: Path, packs_dir: Path, textures_dir: Path, variants: dict, pack_dirs: List[Path]) -> Path:
    manifest_path = project_root / "assets" / "external" / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    # Backwards-compatible single entries (current code expects these keys).
    def first_or_empty(key: str) -> str:
        arr = variants.get(key, [])
        return arr[0] if isinstance(arr, list) and arr else ""

    # Check if we have any successfully downloaded packs
    has_assets = len(pack_dirs) > 0

    # If no assets were downloaded, provide helpful fallback values
    if not has_assets:
        # Use empty arrays as fallback - game will use procedural generation
        variants = {
            "euro_buildings": [],
            "industrial_buildings": [],
            "beach_shacks": [],
            "trees_conifer": [],
            "trees_broadleaf": [],
            "trees_palm": []
        }

    # Build texture sets from downloaded textures
    texture_sets = build_texture_sets(project_root, textures_dir)

    data = {
        "version": 2,
        "generated_by": "tools/fetch_assets.py",
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),

        # --- Enable external assets by default if we have any ---
        "use_external_assets": has_assets,

        # --- Multi-variant pools for variety ---
        "variants": variants,

        # --- Texture sets for PBR materials ---
        "textures": texture_sets,

        # --- Where things were downloaded ---
        "packs_dir": _rel_res_path(project_root, packs_dir),
        "textures_dir": _rel_res_path(project_root, textures_dir),

        # --- Status information ---
        "status": {
            "assets_downloaded": has_assets,
            "asset_count": len(pack_dirs),
            "warning": "No assets were successfully downloaded. Using fallback values." if not has_assets else "Assets downloaded successfully."
        }
    }

    manifest_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return manifest_path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", type=str, default=".", help="Path inside your Godot project (or any subdir)")
    ap.add_argument("--no-textures", action="store_true", help="Skip ambientCG textures")
    ap.add_argument("--local-only", action="store_true", help="Use only local files from assets/ingest/, don't download from internet")
    ap.add_argument("--ww2-assets", action="store_true", help="Include additional WW2-themed Kenney packs")
    ap.add_argument("--ww2-textures", action="store_true", help="Include additional WW2-themed ambientCG textures")
    ap.add_argument("--polyhaven", action="store_true", help="Include Poly Haven CC0 assets (large downloads)")
    ap.add_argument("--list-assets", action="store_true", help="List available assets in assets/ingest/ and exit")
    ap.add_argument("--all", action="store_true", help="Fetch all available assets (Kenney + Poly Haven + textures)")
    args = ap.parse_args()

    project_root = find_project_root(Path(args.project))
    print(f"Project root: {project_root}")

    packs_dir = project_root / "assets" / "external" / "packs"
    textures_dir = project_root / "assets" / "external" / "textures" / "ambientcg"

    # Handle --list-assets option
    if args.list_assets:
        available_assets = list_available_local_assets(project_root)
        if available_assets:
            print("\nAvailable assets in assets/ingest/:")
            for asset in available_assets:
                print(f"  - {asset}")
        else:
            print("\nNo assets found in assets/ingest/")
        return 0

    # Handle --all option (enable all asset types)
    if args.all:
        args.ww2_assets = True
        args.ww2_textures = True
        args.polyhaven = True
        print("\n[All Assets Mode] Enabling all asset types...")

    # Fetch base Kenney packs
    pack_dirs: List[Path] = []
    for pack in KENNEY_PACKS:
        try:
            pack_dirs.append(fetch_kenney_pack(pack, packs_dir, project_root))
        except Exception as e:
            print(f"  !! failed to fetch {pack.slug}: {e}")

    # Fetch WW2 Kenney packs if requested
    if args.ww2_assets:
        for pack in KENNEY_WW2_PACKS:
            try:
                pack_dirs.append(fetch_kenney_pack(pack, packs_dir, project_root))
            except Exception as e:
                print(f"  !! failed to fetch WW2 pack {pack.slug}: {e}")

    # Fetch Poly Haven assets if requested
    if args.polyhaven:
        for asset in POLYHAVEN_ASSETS:
            try:
                pack_dir = fetch_polyhaven_asset(asset, packs_dir, project_root)
                if pack_dir:
                    pack_dirs.append(pack_dir)
            except Exception as e:
                print(f"  !! failed to fetch Poly Haven asset {asset.file_name}: {e}")

    # Fetch textures
    if not args.no_textures:
        # Base textures
        try:
            fetch_ambientcg_textures(AMBIENTCG_TEXTURES, textures_dir, project_root)
        except Exception as e:
            print(f"  !! texture download failed: {e}")
        
        # WW2 textures if requested
        if args.ww2_textures:
            try:
                fetch_ambientcg_textures(AMBIENTCG_WW2_TEXTURES, textures_dir, project_root)
            except Exception as e:
                print(f"  !! WW2 texture download failed: {e}")
        
        # Poly Haven textures if requested
        if args.polyhaven:
            try:
                fetch_ambientcg_textures(POLYHAVEN_TEXTURES, textures_dir, project_root)
            except Exception as e:
                print(f"  !! Poly Haven texture download failed: {e}")

    variants = build_variant_pools(project_root, pack_dirs)
    manifest_path = write_manifest(project_root, packs_dir, textures_dir, variants, pack_dirs)

    print("\nDone.")
    print(f"Manifest written: {manifest_path}")
    print("\nNext step (in Godot): wire the 'variants' pools into your MultiMesh building/tree placement.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
