import SwiftUI
import KicksCore
import KicksFTMS
import KicksLink

/// A freestyle run: live HUD from the treadmill, strap and footpod; incline per Preferences;
/// speed nudges for fartlek from the phone. (Workouts, recording and Strava come next.)
@MainActor @Observable
final class RunSession {
    private(set) var state = SessionState()
    /// Auto-pauses while the belt is stopped (like the web app), unless the user paused.
    private(set) var userPaused = false
    private var lastMachineDistance: Double?
    private var lastTick: Date?

    func togglePause() { userPaused.toggle() }

    /// This run's incline target. Fixed mode starts it at the Preferences value; in Off mode it
    /// stays nil (incline untouched) until the runner taps an incline button, which takes over
    /// incline for this run only. Never changes the saved preference.
    var inclineTarget: Double?
    /// Set once End is confirmed: no more speed/incline writes.
    var ended = false

    /// Called about once a second.
    func tick(hub: BluetoothHub, inclineMode: InclineMode, inclineFixed: Double) {
        let now = Date()
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        let live = hub.live

        state.speedKmh = live.speedKmh ?? 0
        state.inclinePercent = live.inclinePercent ?? 0
        state.heartRate = live.heartRate
        state.cadence = live.footpodCadence
        state.powerWatts = live.power
        state.activity = live.machineKind == .bike ? .ride : .run

        let moving = live.machineKind == nil ? true : (live.isBeltMoving || (live.power ?? 0) > 0)
        state.isPaused = userPaused || !moving

        if !state.isPaused {
            state.elapsed += dt
            // Integrate belt speed (what the web app did; the FR30z's own distance field didn't
            // advance in the first hardware test). The machine count is only logged for now.
            state.distance += state.speedKmh / 3.6 * dt
        }
        if let d = live.machineDistance, d != lastMachineDistance {
            if lastMachineDistance == nil || Int(d) / 100 != Int(lastMachineDistance!) / 100 {
                hub.record("machine distance field: \(Int(d)) m (app: \(Int(state.distance)) m)")
            }
            lastMachineDistance = d
        }

        // Treadmill control: incline per Preferences (Off never sends anything), speed resends.
        if let m = hub.machine, live.machineKind == .treadmill, !ended {
            if inclineMode == .fixed, inclineTarget == nil { inclineTarget = inclineFixed }
            m.requestIncline(inclineTarget)
            m.tick()
        }
    }
}

struct RunView: View {
    @Environment(BluetoothHub.self) private var hub
    @Environment(LinkHost.self) private var link
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.inclineMode) private var inclineMode = InclineMode.off.rawValue
    @AppStorage(Prefs.inclineFixed) private var inclineFixed = 1.0
    @AppStorage(Prefs.hudSize) private var hudSize = HUDSize.large.rawValue
    @State private var session = RunSession()
    @State private var confirmEnd = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scale: CGFloat { (HUDSize(rawValue: hudSize) ?? .large).scale }

    var body: some View {
        let s = session.state
        VStack(spacing: 24 * scale) {
            HStack {
                Text(s.isPaused ? (session.userPaused ? "PAUSED" : "WAITING FOR BELT") : "RUNNING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(s.isPaused ? .orange : .green)
                Spacer()
                Text(Format.duration(s.elapsed)).font(.system(size: 28 * scale, weight: .bold, design: .rounded))
            }
            Spacer(minLength: 0)
            metric(Format.pace(s.paceSecondsPerKm), "min/km", size: 96)
            HStack(spacing: 32) {
                metric(Format.distanceKm(s.distance), "km", size: 52)
                metric(s.heartRate.map(String.init) ?? "–", "bpm", size: 52)
            }
            HStack(spacing: 32) {
                metric(String(format: "%.1f", s.speedKmh), "km/h", size: 28)
                metric(String(format: "%.1f", s.inclinePercent), "% incline", size: 28)
                metric(s.cadence.map(String.init) ?? "–", "spm", size: 28)
            }
            Spacer(minLength: 0)
            if let m = hub.machine, hub.live.machineKind == .treadmill, m.hasControl {
                HStack(spacing: 16) {
                    nudge("−0.5 km/h") { m.setSpeed(((s.speedKmh - 0.5) * 2).rounded() / 2) }
                    nudge("+0.5 km/h") { m.setSpeed(((s.speedKmh + 0.5) * 2).rounded() / 2) }
                }
                .disabled(!hub.live.isBeltMoving)
                // One press = one treadmill step (the FR30z reports 1 % steps).
                let step = max(m.inclineRange?.step ?? 1, 0.5)
                let label = step.rounded() == step ? String(Int(step)) : String(format: "%.1f", step)
                HStack(spacing: 16) {
                    nudge("−\(label) %") { stepIncline(-step, m) }
                    nudge("+\(label) %") { stepIncline(step, m) }
                }
            }
            HStack(spacing: 16) {
                Button(session.userPaused ? "Resume" : "Pause") { session.togglePause() }
                    .buttonStyle(.bordered).controlSize(.large)
                Button("End", role: .destructive) { confirmEnd = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding()
        .monospacedDigit()
        .onReceive(timer) { _ in
            session.tick(hub: hub, inclineMode: InclineMode(rawValue: inclineMode) ?? .off, inclineFixed: inclineFixed)
            if !session.ended { link.send(.state(session.state)) }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            link.send(.state(session.state))
            link.onCommand = handle
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            link.onCommand = nil
            link.send(.idle)
        }
        .confirmationDialog("End this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End run", role: .destructive) {
                session.ended = true
                hub.machine?.stop()
                link.send(.idle)
                dismiss()
            }
        } message: {
            Text("Stops the belt. Saving and Strava upload come in the next step; this run won't be kept yet.")
        }
    }

    private func metric(_ value: String, _ unit: String, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: size * scale, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(unit).font(.headline).foregroundStyle(.secondary)
        }
    }

    /// Siri Remote presses on a TV. End is deliberately not accepted from the TV.
    private func handle(_ command: LinkMessage.Command) {
        switch command {
        case .pause: if !session.userPaused { session.togglePause() }
        case .resume: if session.userPaused { session.togglePause() }
        case .speedUp, .speedDown:
            guard let m = hub.machine, hub.live.machineKind == .treadmill else { return }
            let v = session.state.speedKmh + (command == .speedUp ? 0.5 : -0.5)
            m.setSpeed((v * 2).rounded() / 2)
        default: break
        }
    }

    private func stepIncline(_ delta: Double, _ m: MachineConnection) {
        let r = m.inclineRange
        // Off mode: start from wherever the treadmill is now.
        let next = (session.inclineTarget ?? hub.live.inclinePercent ?? 0) + delta
        session.inclineTarget = min(max(next, r?.min ?? 0), r?.max ?? 15)
    }

    private func nudge(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).controlSize(.large)
    }
}
