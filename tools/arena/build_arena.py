"""Build the runtime arena from the purchased JG3D .blend (which is never modified).

Strategy: strip whole elements we don't need rather than decimating anything; size each
texture by how much it's seen; let Xcode's realitytool GPU-compress textures (ASTC).

Run headless from the repo root:
  /Applications/Blender.app/Contents/MacOS/Blender -b \
    "assets/arena/Track&Field2.1.blend" --python tools/arena/build_arena.py

Outputs (gitignored, paid asset), in assets/arena/build/:
  arena.usdz                    — slimmed USDZ (also handy for Quick Look / look-dev)
  arena-<platform>.reality      — compiled, GPU-compressed, per platform (what the app loads)
"""
import os
import shutil
import subprocess
import sys
import bpy

# Objects removed from the build (exact names, plus all their children).
STRIP = [
    "Net",       # discus cage netting — 52k verts, 27% of the scene
    "Pillars",   # discus cage posts (bare poles without the net)
]

# Non-render objects that never belong in the runtime scene.
STRIP_TYPES = {"CAMERA", "LIGHT"}

# Roughness maps that are effectively one value: replaced by their mean.
FLAT_ROUGHNESS = {"rubberized_track_Roughness.jpg", "asphalt_Roughness.jpg", "Grass_Roughness.jpg"}

# Max texture size by filename prefix (first match wins). Seen from a runner's chase camera.
TEXTURE_SIZES = [
    ("Track2.0_BaseColor", 4096),  # atlas: lane markings, numbers, signs — keep sharp
    ("Track2.0_", 2048),
    ("rubberized_track_", 1024),   # tiling surfaces: detail comes from repeats
    ("Grass_", 1024),
    ("asphalt_", 1024),
    ("Stand_", 2048),              # always in the background
    ("ChainLink_", 2048),
]
DEFAULT_TEXTURE_SIZE = 2048

# Platforms to compile .reality files for, with deployment target.
PLATFORMS = [("appletvos", "26.0"), ("appletvsimulator", "26.0")]

DEV = "/Applications/Xcode.app/Contents/Developer"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "arena", "build")
OUT = os.path.join(OUT_DIR, "arena.usdz")


def log(msg):
    print(f"build_arena: {msg}", flush=True)


def mesh_verts():
    return sum(len(o.data.vertices) for o in bpy.context.scene.objects if o.type == "MESH")


def strip():
    scene = bpy.context.scene
    missing = [n for n in STRIP if n not in scene.objects]
    if missing:
        sys.exit(f"build_arena: objects not found (renamed in source?): {missing}")

    doomed = set()
    for name in STRIP:
        o = scene.objects[name]
        doomed.add(o)
        doomed.update(o.children_recursive)
    doomed.update(o for o in scene.objects if o.type in STRIP_TYPES)

    for o in doomed:
        bpy.data.objects.remove(o, do_unlink=True)
    return len(doomed)


def flatten_roughness():
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        nodes = mat.node_tree.nodes
        for n in list(nodes):
            if n.type != "TEX_IMAGE" or not n.image or n.image.name not in FLAT_ROUGHNESS:
                continue
            px = list(n.image.pixels)
            # mean of the R channel (greyscale map)
            value = sum(px[0::4]) / (len(px) // 4)
            for link in list(n.outputs["Color"].links):
                sock = link.to_socket
                mat.node_tree.links.remove(link)
                sock.default_value = value
            log(f"{mat.name}: {n.image.name} -> roughness {value:.3f}")
            nodes.remove(n)


def texture_size(filename):
    for prefix, size in TEXTURE_SIZES:
        if filename.startswith(prefix):
            return size
    return DEFAULT_TEXTURE_SIZE


def export_usdz():
    # Export .usdc + textures/ then zip with Apple's usdzip: Blender's own USDZ packer drops
    # images shared by two materials (Track/Trac2 both use Track2.0_*).
    stage_dir = os.path.join(OUT_DIR, "stage")
    shutil.rmtree(stage_dir, ignore_errors=True)
    os.makedirs(stage_dir)
    bpy.ops.wm.usd_export(
        filepath=os.path.join(stage_dir, "arena.usdc"),
        export_textures_mode="NEW",
        relative_paths=True,
        selected_objects_only=False,
        export_animation=False,
        export_materials=True,
        generate_preview_surface=True,  # UsdPreviewSurface: what RealityKit reads
        convert_orientation=True,       # Blender Z-up -> USD Y-up for RealityKit
        export_global_up_selection="Y",
        triangulate_meshes=True,
    )

    tex_dir = os.path.join(stage_dir, "textures")
    # Some packed images are written as .png although the USD references .jpg
    # (Track2.0_BaseColor / _Roughness); convert them to what the USD expects.
    for img in bpy.data.images:
        stem, ext = os.path.splitext(os.path.basename(img.filepath))
        want = os.path.join(tex_dir, stem + ext)
        got = os.path.join(tex_dir, stem + ".png")
        if ext.lower() in (".jpg", ".jpeg") and not os.path.exists(want) and os.path.exists(got):
            subprocess.run(["/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", "90",
                            got, "--out", want], check=True, capture_output=True)
            os.remove(got)

    # Resize textures (in place, keeping names so the USD references still match).
    for f in sorted(os.listdir(tex_dir)):
        path = os.path.join(tex_dir, f)
        img = bpy.data.images.load(path)
        w, h = img.size
        bpy.data.images.remove(img)
        target = texture_size(f)
        if max(w, h) > target:
            subprocess.run(["/usr/bin/sips", "-Z", str(target), path], check=True, capture_output=True)
            log(f"texture {f}: {w} -> {target}")
        else:
            log(f"texture {f}: {w} (kept)")

    if os.path.exists(OUT):
        os.remove(OUT)
    subprocess.run(["/usr/bin/usdzip", "--arkitAsset", "arena.usdc", OUT], cwd=stage_dir, check=True)
    log(f"wrote {OUT} ({os.path.getsize(OUT) / 1e6:.1f} MB)")


def compile_reality():
    # realitytool compiles an .rkassets folder; it GPU-compresses textures for each platform.
    rk = os.path.join(OUT_DIR, "Arena.rkassets")
    shutil.rmtree(rk, ignore_errors=True)
    os.makedirs(rk)
    shutil.copy(OUT, rk)
    env = dict(os.environ, DEVELOPER_DIR=DEV)
    for platform, target in PLATFORMS:
        out = os.path.join(OUT_DIR, f"arena-{platform}.reality")
        r = subprocess.run(
            ["xcrun", "realitytool", "compile", "--platform", platform,
             "--deployment-target", target, "--output-reality", out, rk],
            env=env, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"build_arena: realitytool failed for {platform}:\n{r.stdout}\n{r.stderr}")
        log(f"wrote {out} ({os.path.getsize(out) / 1e6:.1f} MB)")


def main():
    before = mesh_verts()
    n = strip()
    flatten_roughness()
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    log(f"removed {n} objects; mesh verts {before} -> {mesh_verts()}")
    export_usdz()
    compile_reality()


main()
