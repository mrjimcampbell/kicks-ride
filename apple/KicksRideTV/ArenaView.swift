import SwiftUI
import RealityKit
import KicksCore

/// RealityKit scene. Placeholder geometry is built from the exact-spec TrackGeometry;
/// the slimmed JG3D arena USDZ will replace it (loaded from the gitignored assets build,
/// never committed). Track plane: RealityKit x = track x, RealityKit z = -track y.
struct ArenaView: View {
    let session: TVSession
    private let track = TrackGeometry.standard

    var body: some View {
        RealityView { content in
            let root = Entity()

            let outerR = Float(track.kerbRadius + Double(track.laneCount) * track.laneWidth)
            let innerR = Float(track.kerbRadius)
            let straight = Float(track.straightLength)

            // Track surface (stadium shape = plane with corner radius of half its depth).
            let surface = ModelEntity(
                mesh: .generatePlane(width: straight + 2 * outerR, depth: 2 * outerR, cornerRadius: outerR),
                materials: [SimpleMaterial(color: .init(red: 0.72, green: 0.25, blue: 0.18, alpha: 1), isMetallic: false)])
            root.addChild(surface)

            let infield = ModelEntity(
                mesh: .generatePlane(width: straight + 2 * innerR, depth: 2 * innerR, cornerRadius: innerR),
                materials: [SimpleMaterial(color: .init(red: 0.22, green: 0.5, blue: 0.22, alpha: 1), isMetallic: false)])
            infield.position.y = 0.01
            root.addChild(infield)

            let runner = ModelEntity(
                mesh: .generateBox(width: 0.45, height: 1.8, depth: 0.3, cornerRadius: 0.1),
                materials: [SimpleMaterial(color: .white, isMetallic: false)])
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
                session.state.advance(by: event.deltaTime)
                let p = track.pose(distance: session.state.distance)
                let pos = SIMD3<Float>(Float(p.x), 0.9, Float(-p.y))
                let forward = SIMD3<Float>(Float(cos(p.heading)), 0, Float(-sin(p.heading)))
                runner.position = pos
                runner.orientation = simd_quatf(angle: Float(p.heading), axis: [0, 1, 0])
                // Chase camera: behind and above, looking just ahead of the runner.
                camera.look(at: pos + forward * 4, from: pos - forward * 7 + [0, 3, 0], relativeTo: nil)
            }
        }
    }
}
