# Handover — 13 Nov 2026

For a fresh session picking up Kicks Ride / Virtual Trainer. Read `CLAUDE.md` (decisions,
hardware findings, history) and, for the TV app, `~/claude/kicks-ride-unity/README.md`.

## Where things stand
- **iPhone app** (Swift, `apple/KicksRide`): the treadmill brain. FTMS treadmill control
  (speed ±, incline ±1 % steps, End slows the belt to its minimum — the FR30z ignores FTMS STOP),
  HR strap, distance from belt speed, freestyle run HUD, Bluetooth log, and the phone→TV link
  (`KicksLink`, Bonjour `_kicksride._tcp` + WebSocket JSON). Not yet: workouts/intervals,
  recording/TCX/Strava, much of what the old web app did.
- **TV app — two versions, choice not final:**
  - RealityKit (`apple/KicksRideTV`): works, but weather/lighting effects were an uphill fight
    (no fog/reflections built in, bloom crashed). Parked.
  - **Unity** (`~/claude/kicks-ride-unity`, local git only — holds the paid arena, never push):
    Jim much prefers it. Title screen with orbit camera, phone link (tested with the iPhone app
    in the simulator; not yet with the real phone + treadmill), runner with gait blend tree on
    lane 1, chase cameras, time of day × weather, floodlights + bloom + volumetric light, fog,
    rain with splashes, noise-formed puddles that grow/dry with planar reflections + ripples,
    HUD placeholder. Installed on the Living Room Apple TV (`Tools/install_tv.sh "Living Room"`).

## Remote (Unity TV app)
Clicks only (touch is off: too sensitive). Ring ←/→ camera (orbit is one of the views),
↑/↓ belt speed in a run / time of day when idle, centre click weather (idle),
play/pause pause/resume in a run / screensaver run when idle.

## Next steps (Jim's list)
1. **iPhone "test controller" page**: switch TV variables from the phone instead of cramming them
   onto the remote — time of day, weather, camera, screensaver run on/off and speed, quality tier,
   wetness, volumetric strength… Needs new LinkMessage commands (phone→TV) in both apps.
2. **Quality tiers**: an on-screen frame-rate readout and a High/Ultra switch (shadow atlas size,
   MSAA/TAA, reflection resolution, volumetric steps) to find the Living Room TV's headroom; the
   new Apple TV (if bought) may take Ultra.
3. Test the Unity TV app with the real phone on the treadmill.
4. Puddle *behaviour* (Jim: looks great, behaviour needs thought) — side quest below.
5. Back to the phone app: workouts/interval strip, recording/Strava, HUD design pass (Claude Design).

## Side quests (separate sessions, small handovers)
- **Rain & wet surfaces** (good Fable 5.2 test later): in a *separate small Unity project*
  (arena + track + sky only) so it doesn't lock the main project; judge against reference videos
  Jim can supply; Apple TV/URP only (HDRP doesn't run on tvOS); bring results back as scripts/shaders.
- **Runner character** (Jim may do this in Codex/ChatGPT): concept sheets → image-to-3D → Blender
  rig/clean-up; the Unity side needs a Mixamo-compatible Generic rig (see `RunnerSetup.cs`).

## Working notes
- Unity is driven live via the Unity CLI (`unity command script eval`, `capture game_view`,
  `recompile`, `editor.playmode start/stop`); captures land in the scratchpad.
- Signing/installs run in the user's Terminal panel (keychain). Push the kicks-ride repo after
  each piece of work (standing permission); the Unity repo stays local.
- Don't use the Magnific connector's app tools for Blender/Unity.
