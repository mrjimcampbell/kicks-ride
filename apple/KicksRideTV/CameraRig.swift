import RealityKit
import Foundation
import Observation

/// Zwift-style camera views. Swipe left/right on the Siri Remote to switch; the camera eases into
/// each new view (and follows the runner through the bends) rather than cutting.
enum CameraMode: String, CaseIterable, Identifiable {
    case standard, close, low, firstPerson, front, side, helicopter, dynamic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard rear"
        case .close: "Close rear"
        case .low: "Low rear"
        case .firstPerson: "First person"
        case .front: "Front"
        case .side: "Side"
        case .helicopter: "Helicopter"
        case .dynamic: "Dynamic"
        }
    }

    /// Eye and look-at offsets in the runner's frame: (back→forward, left→right outwards, up), metres.
    fileprivate var shot: (eye: SIMD3<Float>, look: SIMD3<Float>, fov: Float) {
        switch self {
        case .standard:    ([-4.5, 0, 2.0],  [5, 0, 0.9],    45)
        case .close:       ([-2.6, 0, 1.6],  [4, 0, 1.1],    45)
        case .low:         ([-3.2, 0.4, 0.45], [3, 0, 1.2],  50)
        case .firstPerson: ([0.15, 0, 1.65], [12, 0, 1.5],   60)
        case .front:       ([4.5, 0, 1.6],   [0, 0, 1.0],    45)
        case .side:        ([0, 4.5, 1.3],   [0.5, 0, 1.0],  45)
        case .helicopter:  ([-10, 0, 12],    [4, 0, 0],      40)
        case .dynamic:     CameraMode.standard.shot
        }
    }
}

@MainActor @Observable
final class CameraRig {
    var mode: CameraMode = .standard {
        didSet { if mode != oldValue { announce() } }
    }
    /// Shown briefly after a switch.
    private(set) var banner: String?

    /// Current eye / look-at offsets in the runner's frame (eased towards the active shot).
    @ObservationIgnored private var eyeOffset: SIMD3<Float>?
    @ObservationIgnored private var lookOffset: SIMD3<Float>?
    @ObservationIgnored private var fov: Float = 45
    @ObservationIgnored private var dynamicShot: CameraMode = .standard
    @ObservationIgnored private var dynamicTimer: TimeInterval = 0
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    /// Debug: cycle every view every few seconds (launch argument -kr-camera-tour).
    @ObservationIgnored var tour = false
    @ObservationIgnored private var tourTimer: TimeInterval = 0

    static let dynamicSequence: [CameraMode] = [.standard, .side, .front, .low, .helicopter, .close]
    static let dynamicHold: TimeInterval = 15

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ d: Int) {
        let all = CameraMode.allCases
        let i = all.firstIndex(of: mode) ?? 0
        mode = all[(i + d + all.count) % all.count]
    }

    private func announce() {
        banner = mode.title
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    /// Place the camera for this frame. `feet` is the runner's ground position, `heading` the
    /// direction of travel (radians, RealityKit yaw convention used by ArenaView).
    func update(camera: PerspectiveCamera, runner: Entity, feet: SIMD3<Float>, heading: Float, dt: TimeInterval) {
        if tour {
            tourTimer += dt
            if tourTimer > 4 { tourTimer = 0; next() }
        }
        var shotMode = mode
        if mode == .dynamic {
            dynamicTimer += dt
            if dynamicTimer > Self.dynamicHold {
                dynamicTimer = 0
                let seq = Self.dynamicSequence
                dynamicShot = seq[((seq.firstIndex(of: dynamicShot) ?? 0) + 1) % seq.count]
            }
            shotMode = dynamicShot
        }
        let shot = shotMode.shot
        // Ease the offsets *relative to the runner*, not world positions: no trailing lag while
        // running (so first person sits exactly at the eyes), but still a glide between views.
        let k = Float(1 - exp(-dt * 4))
        eyeOffset = eyeOffset.map { $0 + (shot.eye - $0) * k } ?? shot.eye
        lookOffset = lookOffset.map { $0 + (shot.look - $0) * k } ?? shot.look
        fov += (shot.fov - fov) * k

        let forward = SIMD3<Float>(cos(heading), 0, -sin(heading))
        let outward = SIMD3<Float>(sin(heading), 0, cos(heading))
        let up = SIMD3<Float>(0, 1, 0)
        func world(_ o: SIMD3<Float>) -> SIMD3<Float> { feet + forward * o.x + outward * o.y + up * o.z }

        camera.camera.fieldOfViewInDegrees = fov
        camera.look(at: world(lookOffset!), from: world(eyeOffset!), relativeTo: nil)
        // Hide the runner once the camera is effectively inside its head.
        runner.isEnabled = !(shotMode == .firstPerson && simd_distance(eyeOffset!, shot.eye) < 0.6)
    }
}
