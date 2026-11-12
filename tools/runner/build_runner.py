"""Build runner USDZ files for RealityKit from Mixamo FBX downloads (one clip per FBX).

Run headless from the repo root:
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python tools/runner/build_runner.py

Inputs  (gitignored): assets/runner/<clip source>.fbx — Mixamo, "In Place", with skin.
Outputs (gitignored): assets/runner/build/runner_<clip>.usdz — mesh + skeleton + one looping clip.

The app loads one file as the character and plays the other files' clips on it (same rig).
Each clip's natural speed (m/s at playback rate 1, measured from foot contact) is printed so it
can be copied into RunnerAnimator.clips — that's what keeps the feet from sliding.
"""
import os
import statistics
import bpy

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(REPO, "assets", "runner")
OUT = os.path.join(SRC, "build")

# clip name -> source FBX (add Jogging / Idle here when downloaded)
CLIPS = {
    # Locomotion, slowest -> fastest. Chosen so each clip's step length matches Jim's at the
    # speeds it covers (Garmin: ~1.02 m at 10 km/h -> ~1.32 m at 14 km/h, cadence 165-175).
    "walk": "Standard Walk.fbx",      # 4.9 km/h
    "jog": "Jogging.fbx",             # 3 strides per loop, step ~0.97 m
    "run": "Running_02.fbx",          # step ~1.26 m
    "fast": "Medium Run.fbx",         # step ~1.55 m
    "sprint": "Running.fbx",          # step ~1.96 m; also provides the character mesh
    # Idles: no travel speed; the app alternates them while the belt is stopped.
    "idle_arms": "Arm Stretching.fbx",
    "idle_neck": "Neck Stretching.fbx",
}
# Downloaded but not used: Running_slower (similar to Jogging), Standard Run and Run Forward
# (sprint strides like Running).

BONE_COLOUR = (0.86, 0.83, 0.75, 1.0)  # ivory instead of Mixamo's flat grey


def log(msg):
    print(f"build_runner: {msg}", flush=True)


def natural_speed(arm, f0, f1):
    """Median ground speed of the planted feet = travel speed with no foot slide."""
    sc = bpy.context.scene
    fps = sc.render.fps
    speeds = []
    for bone in ("mixamorig:LeftToeBase", "mixamorig:RightToeBase"):
        pts = []
        for i in range((f1 - f0) * 8 + 1):
            t = f0 + i / 8
            sc.frame_set(int(t), subframe=t - int(t))
            pts.append((t, (arm.matrix_world @ arm.pose.bones[bone].head).copy()))
        zmin = min(p.z for _, p in pts)
        speeds += [abs(b.y - a.y) / ((tb - ta) / fps)
                   for (ta, a), (tb, b) in zip(pts, pts[1:])
                   if a.z < zmin + 0.015 and b.z < zmin + 0.015]
    return statistics.median(speeds)


def steps_per_loop(arm, f0, f1):
    """Steps in the loop. Mixamo loops can hold several strides, so find how many times the
    left foot's height pattern repeats within the loop (2 steps per repeat)."""
    sc = bpy.context.scene
    n = (f1 - f0) * 4
    zs = []
    for i in range(n):
        t = f0 + i / 4
        sc.frame_set(int(t), subframe=t - int(t))
        zs.append((arm.matrix_world @ arm.pose.bones["mixamorig:LeftToeBase"].head).z)
    mean = sum(zs) / n
    d = [z - mean for z in zs]
    var = sum(x * x for x in d) or 1e-9

    def corr(lag):
        return sum(d[i] * d[(i + lag) % n] for i in range(n)) / var

    best = 1
    for k in range(2, 6):  # k strides per loop -> the pattern repeats every n/k samples
        if corr(round(n / k)) > 0.85:
            best = k
    return 2 * best


def build(clip, fbx):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, fbx))
    sc = bpy.context.scene
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    f0, f1 = map(int, arm.animation_data.action.frame_range)

    cycle = (f1 - f0) / sc.render.fps
    if clip.startswith("idle"):
        log(f"{clip}: {f1 - f0} frames, {cycle:.2f}s")
    else:
        v = natural_speed(arm, f0, f1)
        spm = steps_per_loop(arm, f0, f1) * 60 / cycle
        log(f"{clip}: {f1 - f0} frames, {spm:.0f} spm, natural speed {v:.2f} m/s "
            f"({v * 3.6:.1f} km/h), step {v / (spm / 60):.2f} m")

    for mat in bpy.data.materials:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Base Color"].default_value = BONE_COLOUR
            bsdf.inputs["Roughness"].default_value = 0.6

    # Mixamo's last frame repeats the first; drop it so the loop doesn't hitch.
    sc.frame_start, sc.frame_end = f0, f1 - 1

    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, f"runner_{clip}.usdz")
    bpy.ops.wm.usd_export(
        filepath=out,
        selected_objects_only=False,
        export_animation=True,
        export_armatures=True,
        only_deform_bones=True,
        export_materials=True,
        generate_preview_surface=True,
        convert_orientation=True,
        export_global_up_selection="Y",
        export_cameras=False,
        export_lights=False,
    )
    log(f"wrote {out} ({os.path.getsize(out) / 1e6:.1f} MB)")


for clip, fbx in CLIPS.items():
    build(clip, fbx)
