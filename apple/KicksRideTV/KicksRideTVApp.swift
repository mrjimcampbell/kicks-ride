import SwiftUI
import RealityKit
import KicksCore
import KicksLink

/// Apple TV app — display + big HUD. Joins the phone over the local network (KicksLink).
/// Until the phone link exists the runner just stands and stretches at 0:00. Launch with
/// `-kr-demo` for the old looping demo speeds (for checking clip switching).
@main
struct KicksRideTVApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup { TVRootView() }
    }
}

@MainActor @Observable final class TVSession {
    /// Latest state from the phone (or the demo). The HUD shows this.
    var state = SessionState()
    /// True while the phone is in a run.
    private(set) var running = false
    /// Where the runner is drawn. Moves smoothly every frame from the belt speed and is pulled
    /// gently towards the phone's distance, which only arrives about once a second.
    @ObservationIgnored private(set) var runnerDistance: Double = 0
    var demo = ProcessInfo.processInfo.arguments.contains("-kr-demo")

    func receive(_ message: LinkMessage) {
        switch message {
        case .state(let s):
            if !running || s.distance + 50 < state.distance { runnerDistance = s.distance }  // new run
            running = true
            state = s
        case .idle:
            running = false
            state = SessionState()
            runnerDistance = 0
        case .command: break
        }
    }

    /// Demo until the phone link exists: stand (idles), walk, jog, run, sprint, walk, so the
    /// runner's clip switching and playback-rate matching can be checked.
    static let demoProgramme: [(seconds: Double, kmh: Double)] = [(20, 0), (10, 5), (12, 10), (12, 12.5), (12, 14), (10, 17), (8, 21), (8, 5)]

    func tick(_ dt: TimeInterval) {
        guard demo else {
            guard running else { return }   // idle: no time, no distance, idle clips
            if !state.isPaused { runnerDistance += state.speedKmh / 3.6 * dt }
            let error = state.distance - runnerDistance
            if abs(error) > 25 { runnerDistance = state.distance }      // big jump: snap
            else { runnerDistance += error * min(1, dt * 0.8) }         // otherwise ease in
            return
        }
        let total = Self.demoProgramme.reduce(0) { $0 + $1.seconds }
        var t = state.elapsed.truncatingRemainder(dividingBy: total)
        for block in Self.demoProgramme {
            if t < block.seconds { state.speedKmh = block.kmh; break }
            t -= block.seconds
        }
        state.advance(by: dt)
        runnerDistance = state.distance
    }
}

struct TVRootView: View {
    @State private var session = TVSession()
    @State private var cameraRig = CameraRig()
    @State private var link = LinkClient()
    @State private var skyRig = SkyRig()
    @AppStorage("kr.sky") private var savedSky = TimeOfDay.night.rawValue
    @AppStorage("kr.weather") private var savedWeather = Weather.clear.rawValue
    @AppStorage("kr.camera") private var savedCamera = CameraMode.standard.rawValue

    var body: some View {
        // HUD at the top, over the sky, so it never covers the runner.
        ZStack(alignment: .top) {
            ArenaView(session: session, cameraRig: cameraRig, skyRig: skyRig)
            HStack(spacing: 80) {
                hud(Format.pace(session.state.paceSecondsPerKm), "min/km")
                hud(Format.distanceKm(session.state.distance), "km")
                hud(Format.duration(session.state.elapsed), "time")
            }
            .padding(40)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 24))
            .padding(60)

            if !session.running && !session.demo {
                Text(link.phoneName.map { "Connected to \($0) · start a run on the phone" }
                     ?? "Looking for the iPhone… open Virtual Trainer on the phone")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(.black.opacity(0.45), in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 160)
            }

            if let banner = cameraRig.banner ?? skyRig.banner {
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
        .animation(.easeInOut(duration: 0.3), value: skyRig.banner)
        .ignoresSafeArea()
        // Siri Remote: swipe or click left/right to change camera.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: cameraRig.previous()
            case .right: cameraRig.next()
            // Up/down: belt speed during a run; time of day (look-dev) while idle.
            case .up: if session.running { link.send(.speedUp) } else { skyRig.previousTime() }
            case .down: if session.running { link.send(.speedDown) } else { skyRig.nextTime() }
            default: break
            }
        }
        .onPlayPauseCommand {
            if session.running { link.send(session.state.isPaused ? .resume : .pause) }
        }
        .onChange(of: cameraRig.mode) { savedCamera = cameraRig.mode.rawValue }
        .onChange(of: skyRig.time) { savedSky = skyRig.time.rawValue }
        .onChange(of: skyRig.weather) { savedWeather = skyRig.weather.rawValue }
        // Click while idle: next weather.
        .onTapGesture { if !session.running { skyRig.nextWeather() } }
        .onAppear {
            configureCamera()
            link.onMessage = { session.receive($0) }
            link.onDisconnect = { session.receive(.idle) }
            link.start()
        }
    }

    private func configureCamera() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-kr-camera"), i + 1 < args.count, let m = CameraMode(rawValue: args[i + 1]) {
            cameraRig.mode = m
        } else {
            cameraRig.mode = CameraMode(rawValue: savedCamera) ?? .standard
        }
        cameraRig.tour = args.contains("-kr-camera-tour")
        func arg(_ name: String) -> String? {
            args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        skyRig.time = arg("-kr-sky").flatMap(TimeOfDay.init) ?? TimeOfDay(rawValue: savedSky) ?? .night
        skyRig.weather = arg("-kr-weather").flatMap(Weather.init) ?? Weather(rawValue: savedWeather) ?? .clear
    }

    private func hud(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 110, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.title3).foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }
}
