import SwiftUI
import RealityKit
import KicksCore

/// RealityKit scene.
///
/// If the app bundle contains Arena.reality (the slimmed JG3D arena, built by
/// tools/arena/build_arena.py and copied in by a build phase; never committed), it's shown and
/// the runner follows the arena's own lane 1. Otherwise an exact-spec placeholder track is drawn.
///
/// Track plane coordinates: RealityKit x = track x, RealityKit z = -track y, surface at y = 0.
struct ArenaView: View {
    let session: TVSession

    /// Arena track centre and surface height in the USD scene's coordinates (Blender x, z, -y),
    /// measured from the inner kerb of Track_Lanes in Blender.
    private static let arenaTrackCentre = SIMD3<Float>(-6.420, 0.538, -4.002)

    var body: some View {
        RealityView { content in
            let root = Entity()
            let track: TrackGeometry

            if let arena = await Self.loadArena() {
                arena.position = -Self.arenaTrackCentre
                root.addChild(arena)
                track = .jg3dArena
            } else {
                root.addChild(Self.placeholderTrack(.standard))
                track = .standard
            }

            // Runner: animated Mixamo character if built, else a placeholder box. Origin at the feet.
            let animator = await RunnerAnimator.load()
            let runner: Entity
            if let animator {
                runner = animator.entity
            } else {
                let box = ModelEntity(
                    mesh: .generateBox(width: 0.45, height: 1.8, depth: 0.3, cornerRadius: 0.1),
                    materials: [SimpleMaterial(color: .white, isMetallic: false)])
                box.position.y = 0.9
                runner = Entity()
                runner.addChild(box)
            }
            root.addChild(runner)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 50
            root.addChild(camera)

            let sun = DirectionalLight()
            sun.light.intensity = 4000
            sun.look(at: .zero, from: [30, 60, 20], relativeTo: nil)
            root.addChild(sun)

            content.add(root)

            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                session.tick(event.deltaTime)
                let p = track.pose(distance: session.state.distance)
                let feet = SIMD3<Float>(Float(p.x), 0, Float(-p.y))
                let forward = SIMD3<Float>(Float(cos(p.heading)), 0, Float(-sin(p.heading)))
                runner.position = feet
                runner.orientation = simd_quatf(angle: Float(p.heading), axis: [0, 1, 0])
                animator?.update(speed: session.state.isPaused ? 0 : session.state.speedKmh / 3.6)
                // Chase camera: behind and above, looking just ahead of the runner's waist.
                let waist = feet + [0, 0.9, 0]
                camera.look(at: waist + forward * 4, from: waist - forward * 7 + [0, 3, 0], relativeTo: nil)
            }
        }
    }

    private static func loadArena() async -> Entity? {
        guard let url = Bundle.main.url(forResource: "Arena", withExtension: "reality") else {
            print("ArenaView: Arena.reality not in bundle — using placeholder track")
            return nil
        }
        do {
            return try await Entity(contentsOf: url)
        } catch {
            print("ArenaView: failed to load Arena.reality: \(error)")
            return nil
        }
    }

    private static func placeholderTrack(_ track: TrackGeometry) -> Entity {
        let e = Entity()
        let outerR = Float(track.kerbRadius + Double(track.laneCount) * track.laneWidth)
        let innerR = Float(track.kerbRadius)
        let straight = Float(track.straightLength)

        // Stadium shape = plane with corner radius of half its depth.
        e.addChild(ModelEntity(
            mesh: .generatePlane(width: straight + 2 * outerR, depth: 2 * outerR, cornerRadius: outerR),
            materials: [SimpleMaterial(color: .init(red: 0.72, green: 0.25, blue: 0.18, alpha: 1), isMetallic: false)]))
        let infield = ModelEntity(
            mesh: .generatePlane(width: straight + 2 * innerR, depth: 2 * innerR, cornerRadius: innerR),
            materials: [SimpleMaterial(color: .init(red: 0.22, green: 0.5, blue: 0.22, alpha: 1), isMetallic: false)])
        infield.position.y = 0.01
        e.addChild(infield)
        return e
    }
}
