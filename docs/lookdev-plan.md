# Arena look-dev plan (12 Nov 2026)

The Living Room Apple TV 4K (A15) plays the current arena smoothly, so there's headroom.
The new Apple TV (A17 Pro class) has more. The Apple TV HD (A8) is not a target for quality,
only "does it run". All asset work stays in `assets/` (gitignored, paid asset) and goes through
`tools/arena/build_arena.py`.

## 1. Detail on what's there (cheapest wins first)
- **Texture resolution.** We slimmed to 1–2K for tvOS; the 4K A15 can take more on the
  hero surfaces the camera sits on (track, kerb, near infield, near grandstand). Measure
  memory on device before/after.
- **Track wear.** The lane lines are geometry, so wear can't be painted into one map without
  rebaking. Options, best first:
  1. A second UV set across the whole track + one large **wear/dirt mask** (2–4K) multiplied
     over the track surface and line materials: scuffs in lane 1, worn bend apexes, rubber
     marks at starts/exchange zones. One painted map, Jim can paint it.
  2. Tiled **detail maps** (Megascans rubber/asphalt grime, normal + roughness) at a small
     repeat to break up flatness up close, faded by distance.
  3. Decals (alpha cards) for specific marks: start-line scuffs, hurdle marks, puddles.
  RealityKit's ShaderGraphMaterial (built in Reality Composer Pro) can blend the mask with
  the base maps; that's the route for all of the above.
- **Megascans (now free on Fab).** Candidates: grass/turf with clumps, rubber track,
  concrete for stands, metal for rails, dirt/grime atlases, decals (leaves, puddles, cracks).
  Licence note for the public repo: same rule as the arena, never commit them.
- **Hoardings.** Jim's own designs on the advertising boards (fun brands, the app's own
  name once chosen). They're textured planes: swap maps; could even rotate/animate LED boards.

## 2. Sky, background and environment
- An HDRI as the background will likely clash with the low-poly-ish arena and has no depth
  as the camera moves. Better split:
  - **Lighting**: image-based light from an HDRI (RealityKit `ImageBasedLightComponent`),
    a separate small, blurry one per mood. Doesn't need to match the visible sky exactly.
  - **Visible sky**: a sky dome with our own gradient/cloud layers (or a painted panorama),
    so time of day and weather can blend (colour ramps, cloud opacity, sun/moon disc as
    separate elements we place and move).
  - **Horizon**: real geometry beyond the stadium walls: low hills/tree lines/a distant town
    silhouette as cards or simple meshes, like Zwift's hills on every horizon. Gives parallax.
- **Workflow for sky panoramas**: Jim picks a reference HDRI (any good outdoor one, saved as
  a JPG/EXR equirect); I test it as IBL + background to judge the clash; AI variants for
  weather/time-of-day would be generated for the *sky only* (equirect, horizon kept clean)
  with the sun left out so we place it ourselves.

## 3. Moods to test (one scene file, several presets)
| Preset | Sun | Sky | Lights | Extras |
|---|---|---|---|---|
| Clear midday | high, hard shadows | blue gradient, few clouds | off | — |
| Golden hour | low, warm, long shadows | warm gradient | off | haze |
| Overcast | none (soft IBL) | grey cloud layer | off | flat, cool |
| Rain | none | dark cloud | maybe on | wet track (roughness down, reflections), rain particles, puddle decals |
| Night | moon or none | dark, stars | **floodlights on** (spot lights + emissive lamp heads + bloom) | light pools on track |
| Fog/mist | low | white-out | optional | distance fog |

Questions to answer in tests: how many shadow-casting lights the TV takes (floodlights
are the expensive one), whether RealityKit's post effects (bloom, fog) exist on tvOS or must
be faked (fog via material/cards), particle budget for rain.

## 4. Later
- Local weather + time of day driving the preset (WeatherKit on the TV).
- The TV front end picks the preset; phone can too.

## Status
- 12 Nov: test rig built (see CLAUDE.md "Sky rig"). HDRI backdrops actually sit quite well
  with the arena from the chase camera; the horizon line of the pure-sky HDRIs is the giveaway
  (no ground/hills), which the baked-horizon idea would fix. Night with floodlights works.
