# Kicks Ride — project handover

Personal indoor training app for Jim (Manchester, UK; metric units; motion designer, 20+ yrs After Effects / Cinema 4D / Blender).
Started 8 Nov 2026 in a Claude chat; this file is the handover so Claude Code sessions start with full context.

## What exists today (web prototype, working)

Live: https://mrjimcampbell.github.io/kicks-ride/ · Route Explorer: https://mrjimcampbell.github.io/kicks-ride/concepts/
Repo: github.com/mrjimcampbell/kicks-ride (public, GitHub Pages from `main` root). Local copies also in `~/claude/kickr-ride/` (not a git repo).

- `index.html` — single-file app: three.js 0.160 (CDN import map) + Web Bluetooth. Runs in Chrome (Mac) and the Bluefy browser (iPad/iPhone; normal iOS browsers have no Web Bluetooth).
  - **FTMS (0x1826)** connection, auto-detects bike (Indoor Bike Data 0x2AD2) vs treadmill (Treadmill Data 0x2ACD). Control point 0x2AD9 writes serialised, waiting for indication responses.
  - Bike: Course (sim gradient 0x11 with difficulty %), ERG (0x05), fixed grade; physics speed from power/slope/mass (rider kg + 8 kg bike, default rider 69 kg); KICKR's own speed shown for calibration.
  - Treadmill: pace-first HUD; incline modes Course / Fixed / **Off (flat, never touches incline)**; Set Speed (0x02), Set Incline (0x03); never sends START to a treadmill.
  - Heart-rate strap / footpod (0x180D, RSC 0x1814) separate connect.
  - Workouts: library + quick builder. Run: distance reps @ pace, time recoveries @ km/h, incline per block, warm-up/cool-down, or steady pace-capped. Ride: FTP-% ERG blocks. Player: auto speed/incline/ERG per block, 3-2-1 beeps, pause/skip/end, auto-pause when belt stops, resend speed if ignored.
  - Recording → TCX with a lap per workout block; Finish & save; **direct Strava upload** via relay; CSV calibration log; snapshots (manual + max 3 random auto) with stats overlay.
  - HUD text size Normal/Large/XL (Jim runs without glasses — big numbers matter). Bluetooth explorer + copyable log.
- `concepts/index.html` — Route Explorer: keyboard/mouse fly-through of environment moods (highlands default, dawn, coast, night) with Blender models.
- `models/` — `rider.glb`, `runner.glb`, `scots-pines.glb` (script-built placeholders; Jim considers characters far short of the bar). Source: `~/claude/kickr-ride/models/kicks-ride-models.blend`.
- `strava-relay/worker.js` — Cloudflare Worker `https://kicks-ride-strava.jim-campbell.workers.dev` (/token, /refresh, /upload, /upload/:id). Holds `STRAVA_CLIENT_ID=295158` (var) and `STRAVA_CLIENT_SECRET` (encrypted secret, reset 8 Nov). Strava callback domain: mrjimcampbell.github.io. Never put the secret in code or chat.

## Hardware facts learned
- **Reebok FR30z treadmill**: FTMS works; accepts speed AND incline control. Belt reports 0.5 km/h when starting → treat >0.3 km/h as "moving". Sometimes ignores speed commands while ramping → resend after 5 s.
- **Wahoo KICKR Bike Shift**: FTMS works (power, cadence, sim, ERG). Gears/hood buttons are proprietary Wahoo BLE (unexplored).
- Bluefy needs **full 128-bit UUIDs** (no `'fitness_machine'` aliases) and may report characteristic UUIDs in short form — normalise when matching.
- Gym: Concept2 BikeErg (PM5, publishes its own BLE spec) — possible later display/record-only mode.
- Apple TVs: living-room 3rd-gen 4K (A15) → moving to the gym as the main treadmill unit; buying the newest model. Samsung Frame TV in front of the treadmill. Also iPhone, iPad mini (back-burner), Mac Studio (Blender, C4D trial ending, Xcode installed), MacBook Pro.

## Decisions (11 Nov 2026) — the new direction
1. **Park the bike/world-building. First goal: something Jim actually uses daily** — treadmill intervals on a **400 m athletics track**.
2. **Native Apple apps** (Swift). tvOS has no WebView, so the TV renders with **RealityKit** (USDZ assets). The three.js web app stays as a quick look-dev sandbox.
3. **iPhone = the brain**: owns the treadmill BLE connection, workouts, recording, Strava. Must work fully headless (Jim may just watch YouTube). Rich workout builder + library (Jim also asks Claude to author workouts in plain language).
4. **Apple TV = display + big HUD** joining over the local network (Network.framework / Bonjour). Phone shows a stripped HUD + controls (stop, snapshot, skip) — like Zwift Companion. Keep a shared Swift package so roles could later be swapped (TV as standalone driver).
5. **Arena**: bought "Track And Field Arena" by JG3D (Fab). Jim has the .blend, USDZ, textures and a PDF. ~254k verts, 3–4K textures → slim for tvOS (decimate where safe, 1–2K textures, KTX/ASTC). **Paid asset: never commit it to the public repo** — keep under `assets/` and gitignore it.
6. **Exact 400 m**: lane 1 measured 0.30 m from the inner kerb; straights 84.39 m, inner kerb bend radius 36.5 m. Verify/rescale the arena's track; overlay an exact-spec track surface if its markings are off. Runner position = treadmill distance mod 400 along lane 1 (or a chosen lane, scaled).
7. Free Apple developer account for now (7-day reinstall; automate rebuild later). Paid account if it gets annoying.

## Native apps — state as of 12 Nov 2026
- `apple/project.yml` (XcodeGen; run `xcodegen` in `apple/` after adding files — the .xcodeproj is generated and gitignored). Xcode 27.2; `xcode-select` points at CommandLineTools, so CLI builds need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Signing: copy `apple/Config/Local.xcconfig.example` → `Local.xcconfig` (gitignored) with the Personal Team ID.
- `apple/Packages/KicksCore` (iOS/tvOS 26): `KicksCore` (SessionState, Workout, TrackGeometry + tests), `KicksFTMS` (UUIDs only — port from index.html next), `KicksLink` (LinkMessage; Bonjour `_kicksride._tcp` not built yet), `KicksRecording` (relay URL only).
- iPhone app: demo HUD. tvOS app: loads `Arena.reality` if built, runner box laps the arena's lane 1 in a chase cam, HUD across the top. Both verified in simulators.
- **Arena pipeline**: `tools/arena/build_arena.py` (run headless, see its docstring) → `assets/arena/build/` (gitignored): `arena.usdz` + `arena-appletvos.reality` / `arena-appletvsimulator.reality` (realitytool, GPU-compressed). A tvOS build phase copies the matching one in; without it the app draws an exact-spec placeholder.
  - Strips whole elements, never decimates (Jim's call): Net + Pillars (discus cage) gone → 196.5k → 144k verts. Cameras/lights stripped.
  - Textures sized by visibility (Track2.0 atlas BaseColor 4K, Stand/ChainLink/other Track2.0 2K, tiling grass/asphalt/rubber 1K); near-flat roughness maps → constants. Jim may replace textures wholesale later; normal/roughness use to be revisited during look-dev.
  - Gotchas handled: Blender's USDZ packer drops images shared by two materials (so: .usdc + Apple `usdzip`); Track2.0 BaseColor/Roughness get written as .png while referenced as .jpg (converted with sips). ChainLink_BaseColor must stay PNG (alpha).
- **Arena track measured (not to spec)**: real metres, unit scale 1; track centre Blender (−6.420, 4.002), surface z 0.538. Inner kerb radius 35.596 m, straights 82.612 m, 8 lanes × 1.369 m → lane 1 ≈ 390.8 m. Decision: don't rescale; `TrackGeometry.jg3dArena` + `nominalLap = 400` maps 400 m of treadmill onto one lap of the arena's own lane 1.
- Runner: Jim has `assets/free_pack_human_skeleton.fbx`, will rig in Mixamo (Idle / Walking / Running, In Place). Plan: USDZ, crossfade walk↔run by belt speed, scale playback to stop foot slide.
- Pushing: Claude's sandboxed shell can't read the keychain; push via the user's Terminal panel (`gh` is logged in).

## Roadmap (suggested order)
1. iPhone app MVP: FTMS treadmill (port logic from index.html), workouts + builder, live HUD, TCX + Strava upload via the existing relay, HR strap. Usable on its own.
   - **First real test = actually connecting to the treadmill.** Phone setup flow before a run: Devices (scan + pick FTMS treadmill/bike, HR strap, optional footpod for cadence; live readings to confirm; remembered + auto-reconnect) → Route (the track for now, built as a list) → Preferences (units, HUD size, incline mode, more to come) → Start (workout or freestyle). TV shows "waiting for phone" until Start, then the arena.
2. tvOS app: arena in RealityKit, runner lapping the track in sync, big HUD, receives live state from the phone.
3. Look-dev: golden hour, sunset, rain with puddle reflections + splashes, snow; what's beyond the fence (city / countryside / wasteland).
4. Controls: Jim's Bluetooth ring remote (likely media keys → MPRemoteCommandCenter next/prev = ±speed for freestyle fartlek), Siri Remote / game controllers.
5. Later: better runner character (Jim sourcing; image-to-3D with character sheets: Tripo / Magnific / Meshy → remesh → Mixamo), bike mode, BikeErg, iPad, worlds, splats, AI photoreal Strava snapshots (render clean frame → image model → re-overlay exact HUD).

## Working with Jim
- Likes to explore ideas broadly but wants to reach something usable; keep scope tight per milestone and timebox experiments.
- Big, legible HUD numbers. Run metrics: pace (min/km), distance, HR (cadence secondary). Ride: speed, watts, avg watts, HR.
- Commits: end messages with `Co-Authored-By: Claude <noreply@anthropic.com>`.
