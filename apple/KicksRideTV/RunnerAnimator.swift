import RealityKit
import Foundation

/// The runner character: a Mixamo rig with one clip per USDZ (built by tools/runner/build_runner.py,
/// copied into the bundle by a build phase, never committed).
///
/// - Moving: picks walk / jog / run by belt speed (with hysteresis and a crossfade) and scales
///   playback so the planted feet match the ground speed (no foot slide), within sensible limits.
/// - Stopped: alternates the idle clips (warming-up stretches), each played through once.
@MainActor
final class RunnerAnimator {
    struct Clip {
        let name: String
        /// Ground speed (m/s) at playback rate 1, measured from foot contact by build_runner.py.
        let naturalSpeed: Double
        /// Use this clip from this belt speed (m/s) upwards.
        let fromSpeed: Double
        /// Playback-rate limits: beyond these the stride looks wrong, so accept some foot slide.
        let minRate: Float, maxRate: Float
    }

    /// Ordered slowest → fastest. Natural speeds come from build_runner.py's output.
    /// The jog → run switch (3.6 m/s ≈ 13 km/h) sits where both are equally far off their natural
    /// speed; a clip that looks right at ~14 km/h would close that gap.
    static let clips: [Clip] = [
        Clip(name: "walk", naturalSpeed: 1.37, fromSpeed: 0,   minRate: 0.5,  maxRate: 1.5),
        Clip(name: "jog",  naturalSpeed: 2.30, fromSpeed: 1.8, minRate: 0.75, maxRate: 1.65),
        Clip(name: "run",  naturalSpeed: 5.59, fromSpeed: 3.6, minRate: 0.6,  maxRate: 1.25),
    ]
    /// Played in turn while stopped. Optional: if missing, the runner holds its pose.
    static let idleClips = ["idle_arms", "idle_neck"]
    /// The file that provides the character mesh and rig.
    static let characterClip = "run"
    /// Below this belt speed (m/s) the runner is standing.
    static let standingSpeed = 0.3
    /// Speed band (m/s) either side of a switch point that must be crossed before switching back.
    static let hysteresis = 0.15
    static let crossfade: TimeInterval = 0.35
    static let idleCrossfade: TimeInterval = 0.8

    let entity: Entity
    private let model: Entity
    private let animations: [String: AnimationResource]

    private enum State {
        case none
        case moving(Clip, AnimationPlaybackController)
        case idle(index: Int, remaining: TimeInterval)
    }
    private var state: State = .none

    private init(entity: Entity, model: Entity, animations: [String: AnimationResource]) {
        self.entity = entity
        self.model = model
        self.animations = animations
    }

    /// Returns nil if the runner files aren't in the bundle (the app falls back to a placeholder).
    static func load() async -> RunnerAnimator? {
        var character: Entity?
        var anims: [String: AnimationResource] = [:]
        let required = clips.map(\.name)
        for name in required + idleClips {
            guard let url = Bundle.main.url(forResource: "runner_\(name)", withExtension: "usdz") else {
                print("RunnerAnimator: runner_\(name).usdz not in bundle")
                if required.contains(name) { return nil } else { continue }
            }
            do {
                let e = try await Entity(contentsOf: url)
                guard let anim = e.availableAnimations.first else {
                    print("RunnerAnimator: no animation in runner_\(name).usdz"); continue
                }
                // Locomotion loops forever; idles play once each and are chained in update().
                anims[name] = required.contains(name) ? anim.repeat() : anim
                if name == characterClip { character = e }
            } catch {
                print("RunnerAnimator: failed to load runner_\(name).usdz: \(error)")
                if required.contains(name) { return nil }
            }
        }
        guard let model = character, required.allSatisfy({ anims[$0] != nil }) else { return nil }
        // Mixamo faces Blender -Y → USD/RealityKit +Z; our track heading 0 faces +X.
        model.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let root = Entity()
        root.addChild(model)
        return RunnerAnimator(entity: root, model: model, animations: anims)
    }

    /// Call every frame with the belt speed (m/s) and the frame time.
    func update(speed: Double, dt: TimeInterval) {
        if speed < Self.standingSpeed {
            updateIdle(dt: dt)
            return
        }
        let clip = chooseClip(for: speed)
        let controller: AnimationPlaybackController
        if case .moving(let cur, let c) = state, cur.name == clip.name {
            controller = c
        } else if let anim = animations[clip.name] {
            controller = model.playAnimation(anim, transitionDuration: isStarting ? 0 : Self.crossfade)
            state = .moving(clip, controller)
            print("RunnerAnimator: \(clip.name) at \(String(format: "%.1f", speed * 3.6)) km/h")
        } else { return }
        let rate = Float(speed / clip.naturalSpeed)
        controller.speed = min(max(rate, clip.minRate), clip.maxRate)
    }

    private var isStarting: Bool { if case .none = state { true } else { false } }

    private func updateIdle(dt: TimeInterval) {
        let idles = Self.idleClips.filter { animations[$0] != nil }
        switch state {
        case .idle(let index, let remaining) where remaining > dt:
            state = .idle(index: index, remaining: remaining - dt)
        case .idle(let index, _):
            playIdle(idles, index: (index + 1) % max(idles.count, 1))
        default:
            if idles.isEmpty {
                // No idle clips: freeze whatever is playing.
                if case .moving(_, let c) = state { c.speed = 0 }
            } else {
                playIdle(idles, index: 0)
            }
        }
    }

    private func playIdle(_ idles: [String], index: Int) {
        guard idles.indices.contains(index), let anim = animations[idles[index]] else { return }
        let fade = isStarting ? 0 : Self.idleCrossfade
        let controller = model.playAnimation(anim, transitionDuration: fade)
        controller.speed = 1
        print("RunnerAnimator: idle → \(idles[index]) (\(String(format: "%.1f", anim.definition.duration)) s)")
        // Start the next idle so its crossfade finishes as this one ends.
        state = .idle(index: index, remaining: max(anim.definition.duration - Self.idleCrossfade, 1))
    }

    private func chooseClip(for speed: Double) -> Clip {
        guard case .moving(let cur, _) = state,
              let i = Self.clips.firstIndex(where: { $0.name == cur.name }) else {
            return Self.clips.last(where: { speed >= $0.fromSpeed }) ?? Self.clips[0]
        }
        // Step up or down only once clear of the switch point by the hysteresis band.
        if i + 1 < Self.clips.count, speed >= Self.clips[i + 1].fromSpeed + Self.hysteresis {
            return Self.clips.last(where: { speed >= $0.fromSpeed + Self.hysteresis }) ?? Self.clips[i + 1]
        }
        if speed < cur.fromSpeed - Self.hysteresis {
            return Self.clips.last(where: { speed >= $0.fromSpeed - Self.hysteresis }) ?? Self.clips[0]
        }
        return cur
    }
}
