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
1. ~~iPhone "test controller" page~~ **done 13 Nov**: Home ▸ Apple TV row (or the TV button in a
   run) → `TVControllerView`. New messages `tvStatus` (TV→phone: settings, option lists, quality
   levels, fps) and `tvSet` (phone→TV). Tested phone simulator ⇄ Unity editor; not yet on the
   real TV.
2. **Quality tiers** — built 13 Nov: Low / High / Ultra (see the Unity README), 30/60 fps cap,
   fps + resolution on the phone page and an fps overlay on the TV. The TV had been on the
   template's "Mobile" level and Unity's 30 fps default. **To do:** measure on the Living Room
   TV (and the new Apple TV, ordered 13 Nov) in the heaviest moods (night rain, fog), then set
   each TV's default tier (by device model) and tune the tier table.
2b. **Realism/lens switches + TV matching card** — built 13 Nov (phone page: SSAO, AA, lens
   dirt, vignette, grain, chromatic aberration; card for matching the Living Room TV to the
   Frame). Floodlight shadow atlas fixed (tiles were ~512 px: the "dancing" shadows). Reference
   stills/clips for Jim's LUT work: `kicks-ride-unity/Tools/reference_frames.sh` → `Reference/`.
   Next: Jim grades in AE/Resolve → 33-point .cube → convert to a URP Color Lookup strip per
   mood (LUT applies after ACES in LDR grading mode, on sRGB values = the reference frames).
   Noted: night clear is genuinely bright (twilight-blue sky), and the night-rain puddle reads as
   a dark slab.
2c. **14 Nov**: new Apple TV 4K (4th gen) = "Entertainment Room" (the gym box), installed.
   Link reliability: phone heartbeat every 2 s, TV drops a silent link after 6 s and restarts
   Bonjour; phone page has Reconnect + "Looking for Apple TV…" spinner and re-advertises on
   returning from background. Frame caps follow the display (50/25 on UK 50 Hz output). Remote
   ring clicks fixed (thumb position remembered — broke at 60 fps); untested on a real remote.
   Jim's setup notes: new box defaulted to 60 Hz Dolby Vision; DV makes our SDR app darker and
   oversaturated — suggested 4K SDR 60 Hz + Match Dynamic Range + Match Frame Rate, then match
   TVs with the card. Jim is moving to voice notes (Granola / Wispr Flow) for feedback batches.
3. Test the Unity TV app with the real phone on the treadmill.
4. Puddle *behaviour* (Jim: looks great, behaviour needs thought) — side quest below.
5. Back to the phone app: workouts/interval strip, recording/Strava, HUD design pass (Claude Design).

## Side quests (separate sessions, small handovers)
- **Cinematic lighting**: runner-only rim/fill lights (URP light layers) matched to the floodlight
  directions, a tight shadow-only light following the runner, per-mood LUT grades, lens flares;
  probe-volume baked GI with day/night scenarios and reflection probes as the big realism step.
  Jim will bring stills/video references.
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
