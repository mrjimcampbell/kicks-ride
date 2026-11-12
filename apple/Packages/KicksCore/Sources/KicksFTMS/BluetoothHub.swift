import CoreBluetooth
import Foundation
import Observation

/// What a device is used for. A device can advertise several profiles (e.g. a chest strap that
/// also sends running cadence); the slot is the user's choice.
public enum DeviceSlot: String, CaseIterable, Sendable, Identifiable {
    case machine, heartRate, footpod
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .machine: "Treadmill or bike"
        case .heartRate: "Heart rate"
        case .footpod: "Footpod (cadence)"
        }
    }
    var services: [FTMS] {
        switch self {
        case .machine: [.service]
        case .heartRate: [.heartRateService]
        case .footpod: [.rscService]
        }
    }
    var defaultsKey: String { "kr.device.\(rawValue)" }
}

public struct DiscoveredDevice: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var slots: Set<DeviceSlot>
    public var rssi: Int
    public var lastSeen: Date
}

/// Latest readings from all connected devices. Heart rate prefers the strap over the machine.
public struct LiveReadings: Sendable, Equatable {
    public var machineKind: MachineConnection.Kind?
    public var speedKmh: Double?          // belt speed (treadmill) or trainer speed (bike)
    public var inclinePercent: Double?
    public var machineDistance: Double?   // metres, as counted by the machine
    public var power: Int?
    public var bikeCadence: Double?
    public var machineHeartRate: Int?
    public var strapHeartRate: Int?
    public var footpodCadence: Int?
    public var footpodSpeedKmh: Double?

    public var heartRate: Int? { strapHeartRate ?? machineHeartRate }
    public var isBeltMoving: Bool { (speedKmh ?? 0) > FTMS.movingThresholdKmh }
    public init() {}
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected, connecting, connected, reconnecting
    public var label: String {
        switch self {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        }
    }
}

/// Owns the CoreBluetooth central: scanning, the three device slots, remembered devices and
/// automatic reconnection. Runs on the main queue; everything (delegate callbacks included) is main-actor isolated.
@MainActor @Observable
public final class BluetoothHub: NSObject {
    public private(set) var bluetoothState: CBManagerState = .unknown
    public private(set) var isScanning = false
    public private(set) var discovered: [DiscoveredDevice] = []
    public private(set) var live = LiveReadings()
    /// Kept across launches (iOS may quit the app in the background between a test and reading it).
    public private(set) var log: [String] = UserDefaults.standard.stringArray(forKey: "kr.bleLog") ?? [] {
        didSet { UserDefaults.standard.set(log, forKey: "kr.bleLog") }
    }

    public private(set) var names: [DeviceSlot: String] = [:]
    public private(set) var states: [DeviceSlot: ConnectionState] = [:]
    public private(set) var machine: MachineConnection?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripherals: [DeviceSlot: CBPeripheral] = [:]
    @ObservationIgnored private var sensors: [DeviceSlot: SensorConnection] = [:]
    @ObservationIgnored private var seen: [UUID: CBPeripheral] = [:]

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Public API

    public func startScan() {
        guard bluetoothState == .poweredOn, !isScanning else { return }
        let services = DeviceSlot.allCases.flatMap(\.services).map(\.uuid)
        central.scanForPeripherals(withServices: services,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    public func stopScan() {
        central.stopScan()
        isScanning = false
    }

    /// Connect a discovered device into a slot, replacing (and forgetting) any previous one.
    public func connect(_ device: DiscoveredDevice, as slot: DeviceSlot) {
        guard let p = seen[device.id] else { return }
        forget(slot)
        UserDefaults.standard.set(p.identifier.uuidString, forKey: slot.defaultsKey)
        names[slot] = device.name
        UserDefaults.standard.set(device.name, forKey: slot.defaultsKey + ".name")
        attach(p, to: slot)
    }

    /// Disconnect and stop remembering the slot's device.
    public func forget(_ slot: DeviceSlot) {
        if let p = peripherals[slot] { central.cancelPeripheralConnection(p) }
        peripherals[slot] = nil
        sensors[slot] = nil
        if slot == .machine { machine = nil; clearMachineReadings() }
        if slot == .heartRate { live.strapHeartRate = nil }
        if slot == .footpod { live.footpodCadence = nil; live.footpodSpeedKmh = nil }
        states[slot] = .disconnected
        names[slot] = nil
        UserDefaults.standard.removeObject(forKey: slot.defaultsKey)
        UserDefaults.standard.removeObject(forKey: slot.defaultsKey + ".name")
    }

    public func state(of slot: DeviceSlot) -> ConnectionState { states[slot] ?? .disconnected }

    public func record(_ message: String) {
        let t = Date().formatted(.dateTime.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        log.insert("\(t)  \(message)", at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
        print("[ble] \(message)")
    }

    // MARK: Internals

    private func attach(_ p: CBPeripheral, to slot: DeviceSlot) {
        peripherals[slot] = p
        states[slot] = .connecting
        if slot == .machine {
            let m = MachineConnection(peripheral: p, hub: self)
            machine = m
        } else {
            sensors[slot] = SensorConnection(peripheral: p, slot: slot, hub: self)
        }
        // CoreBluetooth keeps this request pending until the device is in range, so it doubles
        // as auto-reconnect: no timeout, no polling.
        central.connect(p)
        record("Connecting \(slot.title.lowercased()): \(p.name ?? "device")")
    }

    private func restoreRemembered() {
        for slot in DeviceSlot.allCases where peripherals[slot] == nil {
            guard let s = UserDefaults.standard.string(forKey: slot.defaultsKey),
                  let id = UUID(uuidString: s),
                  let p = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            names[slot] = UserDefaults.standard.string(forKey: slot.defaultsKey + ".name") ?? p.name
            attach(p, to: slot)
        }
    }

    private func slot(for p: CBPeripheral) -> DeviceSlot? {
        peripherals.first { $0.value.identifier == p.identifier }?.key
    }

    private func clearMachineReadings() {
        live.machineKind = nil; live.speedKmh = nil; live.inclinePercent = nil
        live.machineDistance = nil; live.power = nil; live.bikeCadence = nil; live.machineHeartRate = nil
    }

    // Called by the connections
    func connectionReady(_ slot: DeviceSlot) { states[slot] = .connected }
    func update(_ change: (inout LiveReadings) -> Void) { change(&live) }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothHub: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                record("Bluetooth on")
                restoreRemembered()
            case .unauthorized: record("Bluetooth permission not granted")
            case .poweredOff: record("Bluetooth is off")
            default: break
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            seen[peripheral.identifier] = peripheral
            var slots = Set<DeviceSlot>()
            for u in advertised {
                switch FTMS.from(u) {
                case .service: slots.insert(.machine)
                case .heartRateService: slots.insert(.heartRate)
                case .rscService: slots.insert(.footpod)
                default: break
                }
            }
            let d = DiscoveredDevice(id: peripheral.identifier, name: localName ?? peripheral.name ?? "Unnamed",
                                     slots: slots, rssi: rssi, lastSeen: Date())
            if let i = discovered.firstIndex(where: { $0.id == d.id }) {
                // Keep the strongest-known name and merge profiles (advertising can be split).
                var old = discovered[i]
                old.slots.formUnion(slots); old.rssi = rssi; old.lastSeen = d.lastSeen
                if old.name == "Unnamed" { old.name = d.name }
                discovered[i] = old
            } else {
                discovered.append(d)
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let slot = slot(for: peripheral) else { return }
            record("Connected \(peripheral.name ?? "device"), discovering services")
            if slot == .machine { machine?.start() } else { sensors[slot]?.start() }
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated {
            guard let slot = slot(for: peripheral) else { return }
            record("Couldn't connect \(peripheral.name ?? "device"): \(error?.localizedDescription ?? "unknown")")
            states[slot] = .reconnecting
            central.connect(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated {
            guard let slot = slot(for: peripheral) else { return }  // forgotten: stay disconnected
            record("Lost \(peripheral.name ?? "device"); will reconnect when it's back")
            states[slot] = .reconnecting
            if slot == .machine { machine?.reset(); clearMachineReadings() }
            central.connect(peripheral)  // pending until it's back in range
        }
    }
}
