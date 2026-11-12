import SwiftUI
import RealityKit
import KicksCore

/// Apple TV app — display + big HUD. Joins the phone over the local network (KicksLink).
/// For now runs a local demo session so the scene and HUD can be developed on their own.
@main
struct KicksRideTVApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup { TVRootView() }
    }
}

@Observable final class TVSession {
    var state = SessionState()

    /// Demo until the phone link exists: stand (idles), walk, jog, run, sprint, walk, so the
    /// runner's clip switching and playback-rate matching can be checked.
    static let demoProgramme: [(seconds: Double, kmh: Double)] = [(20, 0), (10, 5), (12, 10), (12, 12.5), (12, 14), (10, 17), (8, 21), (8, 5)]

    func tick(_ dt: TimeInterval) {
        let total = Self.demoProgramme.reduce(0) { $0 + $1.seconds }
        var t = state.elapsed.truncatingRemainder(dividingBy: total)
        for block in Self.demoProgramme {
            if t < block.seconds { state.speedKmh = block.kmh; break }
            t -= block.seconds
        }
        state.advance(by: dt)
    }
}

struct TVRootView: View {
    @State private var session = TVSession()
    @State private var cameraRig = CameraRig()
    @AppStorage("kr.camera") private var savedCamera = CameraMode.standard.rawValue

    var body: some View {
        // HUD at the top, over the sky, so it never covers the runner.
        ZStack(alignment: .top) {
            ArenaView(session: session, cameraRig: cameraRig)
            HStack(spacing: 80) {
                hud(Format.pace(session.state.paceSecondsPerKm), "min/km")
                hud(Format.distanceKm(session.state.distance), "km")
                hud(Format.duration(session.state.elapsed), "time")
            }
            .padding(40)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 24))
            .padding(60)

            if let banner = cameraRig.banner {
                Text(banner)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(.black.opacity(0.5), in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 80)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: cameraRig.banner)
        .ignoresSafeArea()
        // Siri Remote: swipe or click left/right to change camera.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: cameraRig.previous()
            case .right: cameraRig.next()
            default: break
            }
        }
        .onChange(of: cameraRig.mode) { savedCamera = cameraRig.mode.rawValue }
        .onAppear(perform: configureCamera)
    }

    private func configureCamera() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-kr-camera"), i + 1 < args.count, let m = CameraMode(rawValue: args[i + 1]) {
            cameraRig.mode = m
        } else {
            cameraRig.mode = CameraMode(rawValue: savedCamera) ?? .standard
        }
        cameraRig.tour = args.contains("-kr-camera-tour")
    }

    private func hud(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.title3).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }
}
