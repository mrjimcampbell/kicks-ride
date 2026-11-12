# HUD research — first written pass (12 Nov 2026)

A starting map for the screenshot hunt (Mobbin / Refero), not a design. The aim: a HUD read at a
glance, mid-rep, a couple of metres away, without glasses — on a TV first, phone second.

## The requirement we already know
- **Pace** is the mental gauge (biggest), **speed** echoes the treadmill display (secondary, but
  real-time so you can see the belt respond), then distance, HR, time; cadence lowest.
- **Interval strip**: a flat horizontal element along the bottom showing every block of the
  workout, with the **current block highlighted** (Jim loses count otherwise). More important on
  the TV than the phone. Should answer "which rep am I on, how many left, how far through this one".

## How others show intervals

| App | What it does | Worth stealing | Watch out for |
|---|---|---|---|
| **Zwift** (workout mode) | Block chart of the whole workout along the bottom (height = target, colour = zone), progress marker moving across; current/next block + countdown top-centre. HUD refreshed in 2026 with 4 user-chosen centre fields, workout-only. | The bottom block chart is exactly the "strip". Colour by intensity reads instantly. | Users complained target text got too small after the 2026 refresh. No per-interval averages natively (a common request). |
| **TrainingPeaks Virtual** | Interval *list* down the left **and** a workout graph along the bottom. | List = exact numbers; graph = shape/position. Two views of one thing. | Busy; the list costs a whole column. |
| **Garmin watches** | One step at a time: pace **gauge** (slow / on target / fast, red-green-red) on top, step time/distance remaining in the middle, elapsed below. | The **target gauge** answers "am I on pace?" without reading a number. "Remaining in this step" as the hero number during reps. | Users find it confusing whether the number is instant or step-average pace — label it clearly. |
| **Peloton Tread** | Pace-target shortcuts appear above the speed readout when a new target is cued; splits pop up ~10 s then hide; a **400 m virtual track** display for Just Run with 200 m / lap notifications. | Transient pop-ups for events (new block, split, lap) instead of permanent clutter. The 400 m track mini-map — same idea as ours. | Lots of on-screen chrome. |
| **FiT** | Dual progress ring: current interval + whole workout. | Two-level progress (this rep / whole session) in one compact element. | Rings suit a watch more than a wide TV. |
| **Apple Fitness+** | Metrics top corners (time, HR, calories), Burn Bar ranking, editable metrics. | Restraint: few metrics, corner-anchored, the video stays the hero. | Pedestrian type; calorie focus irrelevant here. |
| **F1 broadcast graphics** | Permanent left timing tower; event animations (flash when something changes). | TV-distance typography, permanent anchor + transient event graphics. | Fans say position numbers are too thin on HD sets — go bolder than looks necessary. |

## Patterns to look for in screenshots
1. **One hero number per mode.** Freestyle: pace. Rep: distance/time *remaining*. Recovery: time remaining + next rep's target.
2. **Target vs actual as a shape, not two numbers** (Garmin gauge, Zwift bar height).
3. **The strip**: blocks sized by duration/distance, height or colour by intensity, current block highlighted, done blocks dimmed, rep counter ("4 / 8") next to it.
4. **Transient events**: 3-2-1 countdown, new block, lap complete, split — big for 2–3 s, then gone.
5. **Calm dashboards** (Whoop, Oura, Bevel): one accent colour, dark backgrounds, big numerals with small caps labels, generous spacing. Good for the type/colour language even though they're not live screens.
6. **TV-specific**: safe margins (tvOS overscan), heavy weights, high contrast over a moving 3D scene (scrims/blur behind text).

## Sources
- [Zwift workout mode (DC Rainmaker, 2015)](https://dcrainmaker.com/2015/10/zwifts-workout-mode.html)
- [Zwift support: Workout Mode for Cycling](https://support.zwift.com/en_us/workout-mode-for-cycling-HkhS0S0F.md)
- [Zwift forum: Customizable Workout HUD (May 2026)](https://forums.zwift.com/t/customizable-workout-hud-may-2026/668331)
- [Zwift Insider: Companion workout tips](https://zwiftinsider.com/5-companion-workout-tips)
- [TrainingPeaks Virtual workout mode](https://help.trainingpeaks.com/hc/en-us/articles/31340918973965-TrainingPeaks-Virtual-Workout-Mode)
- [Running app screen design examples (screensdesign)](https://screensdesign.com/articles/running-app-screen-design-examples/)
- [Garmin forum: pace gauge on Forerunner 955](https://forums.garmin.com/sports-fitness/running-multisport/f/forerunner-955-series/376927/effort-data-fields-gauges)
- [Garmin forum: target pace during an interval](https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-7-series/383969/how-to-show-target-pace-during-an-interval-time-distance-remaining-in-that-interval)
- [Peloton pace targets](https://www.onepeloton.com/en-GB/blog/pace-targets)
- [Peloton Tread instructor-guided shortcuts (The Clip Out)](https://theclipout.com/peloton-tread-instructor-guided-shortcuts/)
- [Peloton split times (Pelobuddy)](https://www.pelobuddy.com/split-times-work-out/)
- [Peloton Tread 400 m track display (Pelobuddy)](https://www.pelobuddy.com/?p=31131)
- [Apple Fitness+: change onscreen metrics](https://support.apple.com/guide/fitness-plus/apdf8a229f34/ios)
- [Apple: How to use Fitness+](https://support.apple.com/108761)
- [GPFans: F1 2026 timing tower change](https://www.gpfans.com/en/f1-news/1078428/f1-2026-tv-broadcast-new-timing-tower-graphic/)
- [Motorsport Magazine: F1's TV graphic balancing act](https://www.motorsportmagazine.com/articles/single-seaters/f1/formula-1s-tv-graphic-balancing-act)
