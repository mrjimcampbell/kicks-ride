import RealityKit
import Foundation

/// The runner character: a Mixamo rig with one clip per USDZ (built by tools/runner/build_runner.py,
/// copied into the bundle by a build phase, never committed). Picks walk / run by belt speed with
/// a crossfade, and scales playback so the planted feet match the ground speed (no foot slide).
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

    /// Ordered slowest → fastest. Add "jog" here once a Mixamo jog is downloaded and built.
    static let clips: [Clip] = [
        Clip(name: "walk", naturalSpeed: 1.37, fromSpeed: 0, minRate: 0.5, maxRate: 1.5),
        Clip(name: "run", naturalSpeed: 5.59, fromSpeed: 2.3, minRate: 0.55, maxRate: 1.25),
    ]
    /// Speed band (m/s) either side of a switch point that must be crossed before switching back.
    static let hysteresis = 0.15
    static let crossfade: TimeInterval = 0.35

    let entity: Entity
    private var animations: [String: AnimationResource] = [:]
    private var current: (clip: Clip, controller: AnimationPlaybackController)?

    private init(entity: Entity, animations: [String: AnimationResource]) {
        self.entity = entity
        self.animations = animations
    }

    /// Loads the character from the first clip's file and the other clips' animations.
    /// Returns nil if the runner files aren't in the bundle (app falls back to a placeholder).
    static func load() async -> RunnerAnimator? {
        var character: Entity?
        var anims: [String: AnimationResource] = [:]
        for clip in clips.reversed() {  // "run" file becomes the character
            guard let url = Bundle.main.url(forResource: "runner_\(clip.name)", withExtension: "usdz") else {
                print("RunnerAnimator: runner_\(clip.name).usdz not in bundle — using placeholder")
                return nil
            }
            do {
                let e = try await Entity(contentsOf: url)
                guard let anim = e.availableAnimations.first else {
                    print("RunnerAnimator: no animation in runner_\(clip.name).usdz"); return nil
                }
                anims[clip.name] = anim.repeat()
                if character == nil { character = e }
            } catch {
                print("RunnerAnimator: failed to load runner_\(clip.name).usdz: \(error)"); return nil
            }
        }
        guard let model = character else { return nil }
        // Mixamo faces Blender -Y → USD/RealityKit +Z; our track heading 0 faces +X.
        model.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let root = Entity()
        root.addChild(model)
        return RunnerAnimator(entity: root, animations: anims)
    }

    /// Call every frame with the belt speed in m/s.
    func update(speed: Double) {
        let clip = chooseClip(for: speed)
        if current?.clip.name != clip.name, let anim = animations[clip.name], let model = entity.children.first {
            let controller = model.playAnimation(anim, transitionDuration: current == nil ? 0 : Self.crossfade)
            current = (clip, controller)
        }
        guard let c = current else { return }
        if speed < 0.3 {
            c.controller.speed = 0  // stopped: hold the pose (no idle clip yet)
        } else {
            let rate = Float(speed / c.clip.naturalSpeed)
            c.controller.speed = min(max(rate, c.clip.minRate), c.clip.maxRate)
        }
    }

    private func chooseClip(for speed: Double) -> Clip {
        guard let cur = current?.clip, let i = Self.clips.firstIndex(where: { $0.name == cur.name }) else {
            return Self.clips.last(where: { speed >= $0.fromSpeed }) ?? Self.clips[0]
        }
        // Step up/down only once clear of the switch point by the hysteresis band.
        if i + 1 < Self.clips.count, speed >= Self.clips[i + 1].fromSpeed + Self.hysteresis {
            return Self.clips.last(where: { speed >= $0.fromSpeed + Self.hysteresis }) ?? Self.clips[i + 1]
        }
        if speed < cur.fromSpeed - Self.hysteresis {
            return Self.clips.last(where: { speed >= $0.fromSpeed - Self.hysteresis }) ?? Self.clips[0]
        }
        return cur
    }
}
