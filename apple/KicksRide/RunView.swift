import SwiftUI
import KicksCore
import KicksFTMS

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

    /// This run's incline target (Fixed mode only). Starts at the Preferences value; the
    /// in-run buttons change it for this run without touching the saved preference.
    var inclineTarget: Double?

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
        if let m = hub.machine, live.machineKind == .treadmill {
            if inclineMode == .fixed, inclineTarget == nil { inclineTarget = inclineFixed }
            m.requestIncline(inclineMode == .fixed ? inclineTarget : nil)
            m.tick()
        }
    }
}

struct RunView: View {
    @Environment(BluetoothHub.self) private var hub
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
                if inclineMode == InclineMode.fixed.rawValue {
                    HStack(spacing: 16) {
                        nudge("−0.5 %") { stepIncline(-0.5, m) }
                        nudge("+0.5 %") { stepIncline(0.5, m) }
                    }
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
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("End this run?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End run", role: .destructive) { dismiss() }
        } message: {
            Text("Saving and Strava upload come in the next step; this run won't be kept yet.")
        }
    }

    private func metric(_ value: String, _ unit: String, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: size * scale, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(unit).font(.headline).foregroundStyle(.secondary)
        }
    }

    private func stepIncline(_ delta: Double, _ m: MachineConnection) {
        let r = m.inclineRange
        let next = (session.inclineTarget ?? inclineFixed) + delta
        session.inclineTarget = min(max(next, r?.min ?? 0), r?.max ?? 15)
    }

    private func nudge(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).controlSize(.large)
    }
}
