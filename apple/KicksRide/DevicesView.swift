import SwiftUI
import CoreBluetooth
import KicksCore
import KicksFTMS

/// Scan, pick a device for each slot, see live readings to confirm it's working, and try the
/// treadmill controls. Chosen devices are remembered and reconnect automatically.
struct DevicesView: View {
    @Environment(BluetoothHub.self) private var hub

    var body: some View {
        List {
            if let warning = bluetoothWarning {
                Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            ForEach(DeviceSlot.allCases) { slot in
                SlotSection(slot: slot)
            }
            if let m = hub.machine, hub.live.machineKind == .treadmill {
                TreadmillTestSection(machine: m)
            }
            Section {
                NavigationLink("Bluetooth log") { LogView() }
            }
        }
        .navigationTitle("Devices")
        .toolbar {
            if hub.isScanning { ProgressView() }
        }
        .onAppear { hub.startScan() }
        .onChange(of: hub.bluetoothState) { if hub.bluetoothState == .poweredOn { hub.startScan() } }
        .onDisappear { hub.stopScan() }
    }

    private var bluetoothWarning: String? {
        switch hub.bluetoothState {
        case .poweredOff: "Bluetooth is off. Turn it on in Control Centre."
        case .unauthorized: "\(AppInfo.name) isn't allowed to use Bluetooth. Allow it in Settings › \(AppInfo.name)."
        case .unsupported: "Bluetooth isn't available on this device (the simulator has none)."
        default: nil
        }
    }
}

private struct SlotSection: View {
    @Environment(BluetoothHub.self) private var hub
    let slot: DeviceSlot

    var body: some View {
        Section {
            if let name = hub.names[slot] {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        Text(hub.state(of: slot).label).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(reading).font(.title3.monospacedDigit().bold())
                }
                Button("Forget", role: .destructive) { hub.forget(slot) }
            }
            ForEach(available) { d in
                Button {
                    hub.connect(d, as: slot)
                } label: {
                    HStack {
                        Text(d.name).foregroundStyle(.primary)
                        Spacer()
                        SignalBars(rssi: d.rssi)
                    }
                }
            }
            if hub.names[slot] == nil, available.isEmpty {
                Text(hub.isScanning ? hint : "None chosen").foregroundStyle(.secondary)
            }
        } header: {
            Text(slot.title)
        }
    }

    /// Devices advertising this slot's profile, excluding the one already in the slot.
    private var available: [DiscoveredDevice] {
        let current = hub.names[slot]
        return hub.discovered
            .filter { $0.slots.contains(slot) && $0.name != current && Date().timeIntervalSince($0.lastSeen) < 30 }
            .sorted { $0.rssi > $1.rssi }
    }

    private var hint: String {
        switch slot {
        case .machine: "Searching… Close Zwift / the Wahoo app — the machine takes one connection at a time."
        case .heartRate: "Searching… Put the strap on (it sleeps when dry) or start a broadcast on your watch."
        case .footpod: "Searching… Wake the footpod by walking a few steps."
        }
    }

    private var reading: String {
        let l = hub.live
        switch slot {
        case .machine:
            if l.machineKind == .bike {
                return l.power.map { "\($0) W" } ?? "—"
            }
            let speed = l.speedKmh.map { String(format: "%.1f km/h", $0) } ?? "—"
            let inc = l.inclinePercent.map { String(format: " · %.1f%%", $0) } ?? ""
            return speed + inc
        case .heartRate: return l.strapHeartRate.map { "\($0) bpm" } ?? "—"
        case .footpod: return l.footpodCadence.map { "\($0) spm" } ?? "—"
        }
    }
}

/// Manual checks for the first hardware test: does the treadmill accept speed and incline?
private struct TreadmillTestSection: View {
    @Environment(BluetoothHub.self) private var hub
    let machine: MachineConnection
    @AppStorage(Prefs.inclineMode) private var inclineMode = InclineMode.off.rawValue

    var body: some View {
        Section {
            LabeledContent("Control", value: machine.hasControl ? "Granted" : (machine.canControl ? "Not granted" : "Display only"))
            if let r = machine.speedRange { LabeledContent("Speed range", value: "\(fmt(r.min))–\(fmt(r.max)) km/h") }
            if let r = machine.inclineRange { LabeledContent("Incline range", value: "\(fmt(r.min))–\(fmt(r.max)) % (\(fmt(r.step)) steps)") }
            HStack {
                Text("Belt speed")
                Spacer()
                nudge("−0.5") { setSpeed(-0.5) }
                Text(hub.live.speedKmh.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.body.monospacedDigit().bold()).frame(minWidth: 44)
                nudge("+0.5") { setSpeed(0.5) }
            }
            .disabled(!hub.live.isBeltMoving || !machine.hasControl)
            HStack {
                Text("Incline")
                Spacer()
                nudge("−0.5") { setIncline(-0.5) }
                Text(hub.live.inclinePercent.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.body.monospacedDigit().bold()).frame(minWidth: 44)
                nudge("+0.5") { setIncline(0.5) }
            }
            .disabled(!machine.hasControl || inclineMode == InclineMode.off.rawValue)
        } header: {
            Text("Test controls")
        } footer: {
            if !hub.live.isBeltMoving {
                Text("Start the belt on the treadmill to test speed. The app never starts it.")
            } else if inclineMode == InclineMode.off.rawValue {
                Text("Incline control is Off in Preferences.")
            }
        }
    }

    private func nudge(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered)
    }
    private func setSpeed(_ delta: Double) {
        // Snap to the nearest 0.5 km/h so repeated taps land on round numbers.
        machine.setSpeed((((hub.live.speedKmh ?? 0) + delta) * 2).rounded() / 2)
    }
    private func setIncline(_ delta: Double) {
        machine.requestIncline((machine.lastInclineSent ?? hub.live.inclinePercent ?? 0) + delta)
    }
    private func fmt(_ v: Double) -> String { String(format: v == v.rounded() ? "%.0f" : "%.1f", v) }
}

private struct SignalBars: View {
    let rssi: Int
    var body: some View {
        let bars = rssi > -60 ? 3 : rssi > -75 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= bars ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(4 + i * 4))
            }
        }
        .accessibilityLabel("Signal \(bars) of 3")
    }
}

struct LogView: View {
    @Environment(BluetoothHub.self) private var hub
    var body: some View {
        List(Array(hub.log.enumerated()), id: \.offset) { _, line in
            Text(line).font(.caption.monospaced())
        }
        .navigationTitle("Bluetooth log")
        .toolbar {
            Button("Copy") { UIPasteboard.general.string = hub.log.joined(separator: "\n") }
        }
    }
}
