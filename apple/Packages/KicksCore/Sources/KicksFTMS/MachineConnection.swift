import CoreBluetooth
import Foundation
import Observation

/// A connected FTMS treadmill or smart bike: data notifications, ranges, and control-point writes.
///
/// Control rules carried over from the web app (index.html), learned on Jim's Reebok FR30z:
/// - Writes are serialised: each waits for the machine's indication reply (2.5 s timeout).
/// - Control is requested on connect, and re-requested if a write is refused as "not permitted".
/// - START is only ever sent to a bike. Never to a treadmill: the runner starts the belt.
/// - Speed is only set while the belt is moving (> 0.3 km/h; the belt reports 0.5 when starting).
///   If the belt isn't within 0.6 km/h of the target after 5 s, resend, up to 3 times in all.
/// - Incline changes: at least 4 s apart, and only when the change is ≥ 0.5 % (or one step).
@MainActor @Observable
public final class MachineConnection: NSObject {
    public enum Kind: String, Sendable { case treadmill, bike }

    public private(set) var kind: Kind?
    public private(set) var hasControl = false
    public private(set) var speedRange: SupportedRange?
    public private(set) var inclineRange: SupportedRange?
    public private(set) var powerRange: SupportedRange?
    /// Last incline we asked for (nil = never), used by the incline rules.
    public private(set) var lastInclineSent: Double?

    @ObservationIgnored let peripheral: CBPeripheral
    @ObservationIgnored private weak var hub: BluetoothHub?
    @ObservationIgnored private var chars: [FTMS: CBCharacteristic] = [:]
    @ObservationIgnored private var dataSeen = false

    // Control-point queue
    @ObservationIgnored private var queue: [(data: Data, done: (Bool) -> Void)] = []
    @ObservationIgnored private var inFlight: (op: ControlPoint.OpCode, done: (Bool) -> Void, timeout: Task<Void, Never>)?
    @ObservationIgnored private var lastInclineAt: Date = .distantPast
    @ObservationIgnored private var speedCheck: (kmh: Double, at: Date, tries: Int)?

    public var isBusy: Bool { inFlight != nil || !queue.isEmpty }
    public var canControl: Bool { chars[.controlPoint] != nil }

    init(peripheral: CBPeripheral, hub: BluetoothHub) {
        self.peripheral = peripheral
        self.hub = hub
        super.init()
        peripheral.delegate = self
    }

    func start() {
        peripheral.discoverServices([FTMS.service.uuid])
    }

    /// Connection dropped: abandon queued writes (they'd be stale on reconnect).
    func reset() {
        inFlight?.timeout.cancel()
        inFlight?.done(false)
        inFlight = nil
        queue.forEach { $0.done(false) }
        queue.removeAll()
        chars.removeAll()
        hasControl = false
        dataSeen = false
        lastInclineSent = nil
        speedCheck = nil
    }

    // MARK: Commands

    /// Set the treadmill belt speed (km/h). Refused unless the belt is already moving.
    @discardableResult
    public func setSpeed(_ kmh: Double) -> Bool {
        guard kind == .treadmill else { log("Speed control is for treadmills"); return false }
        guard canControl else { log("This treadmill isn't accepting control"); return false }
        guard hub?.live.isBeltMoving == true else { log("Start the belt on the treadmill first"); return false }
        let target = speedRange?.clamp(kmh) ?? kmh
        let tries = (speedCheck?.kmh == target) ? (speedCheck!.tries + 1) : 1
        speedCheck = (target, Date(), tries)
        log("Setting belt speed \(String(format: "%.1f", target)) km/h")
        send(ControlPoint.setSpeed(kmh: target))
        return true
    }

    /// Ask for an incline (%). Applies the step rounding, minimum change and spacing rules,
    /// so it's safe to call every second. Pass nil when incline control is Off: nothing is sent.
    public func requestIncline(_ percent: Double?) {
        guard kind == .treadmill, canControl, let percent, !isBusy else { return }
        let step = inclineRange?.step ?? 0.5
        var want = inclineRange?.clamp(percent) ?? min(15, max(0, percent))
        want = (want / step).rounded() * step
        let changeEnough = lastInclineSent.map { abs(want - $0) >= max(step, 0.5) } ?? true
        let spacedEnough = Date().timeIntervalSince(lastInclineAt) > 4
        guard changeEnough, lastInclineSent == nil || spacedEnough else { return }
        lastInclineSent = want
        lastInclineAt = Date()
        log("Setting incline \(String(format: "%.1f", want)) %")
        send(ControlPoint.setIncline(percent: want))
    }

    /// Stop the belt / flywheel (End run). Jumps the queue and drops pending speed/incline
    /// writes and resends, so nothing can speed the belt back up afterwards.
    /// Fallbacks, as treadmills differ: STOP refused → try PAUSE; belt still moving after 2 s →
    /// slow it to the machine's minimum speed (an ordinary speed command). The FR30z (12 Nov)
    /// acknowledges STOP but ignores it, so on it End always ends in the slow-down.
    public func stop() {
        guard canControl else { log("Can't stop the machine from here; use its own stop button"); return }
        queue.forEach { $0.done(false) }
        queue.removeAll()
        speedCheck = nil
        log("Stopping the \(kind?.rawValue ?? "machine")")
        send(ControlPoint.stop()) { [weak self] ok in
            guard let self, !ok else { return }
            log("STOP refused, trying PAUSE")
            send(ControlPoint.pause()) { [weak self] ok in
                if !ok { self?.log("PAUSE refused too") }
            }
        }
        guard kind == .treadmill else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, hub?.live.isBeltMoving == true, let belt = hub?.live.speedKmh, belt > 1.5 else { return }
            let slow = speedRange?.min ?? 1
            log("Belt still at \(String(format: "%.1f", belt)) km/h, slowing to \(String(format: "%.1f", slow))")
            setSpeed(slow)
        }
    }

    public func setTargetPower(_ watts: Int) {
        guard kind == .bike, canControl else { return }
        send(ControlPoint.setTargetPower(watts: watts))
    }

    public func setSimulation(gradePercent: Double, crr: Double = 0.004, cw: Double = 0.51) {
        guard kind == .bike, canControl else { return }
        send(ControlPoint.setSimulation(gradePercent: gradePercent, crr: crr, cw: cw))
    }

    /// Call about once a second: resends a speed the treadmill ignored (it can while ramping).
    public func tick() {
        guard let check = speedCheck, !isBusy, let belt = hub?.live.speedKmh else { return }
        if abs(belt - check.kmh) <= 0.6 { speedCheck = nil; return }
        if Date().timeIntervalSince(check.at) > 5 {
            if check.tries < 3 {
                log("Speed didn't take, resending")
                setSpeed(check.kmh)
            } else {
                log("Treadmill didn't reach \(String(format: "%.1f", check.kmh)) km/h after 3 tries")
                speedCheck = nil
            }
        }
    }

    // MARK: Control-point queue

    private func send(_ data: Data, done: @escaping (Bool) -> Void = { _ in }) {
        queue.append((data, done))
        pump()
    }

    private func pump() {
        guard inFlight == nil, !queue.isEmpty, let cp = chars[.controlPoint],
              let op = queue.first.flatMap({ $0.data.first }).flatMap(ControlPoint.OpCode.init) else { return }
        let next = queue.removeFirst()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.finish(op, ok: false, note: "No reply to \(op.label)")
        }
        inFlight = (op, next.done, timeout)
        peripheral.writeValue(next.data, for: cp, type: .withResponse)
    }

    private func finish(_ op: ControlPoint.OpCode, ok: Bool, note: String? = nil) {
        guard let f = inFlight, f.op == op else { return }
        f.timeout.cancel()
        inFlight = nil
        if let note { log(note) }
        f.done(ok)
        pump()
    }

    private func log(_ s: String) { hub?.record(s) }
}

// MARK: - CBPeripheralDelegate

extension MachineConnection: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let svc = peripheral.services?.first(where: { FTMS.from($0.uuid) == .service }) else {
                log("No fitness-machine service on \(peripheral.name ?? "device")"); return
            }
            peripheral.discoverCharacteristics(nil, for: svc)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                       error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] { if let k = FTMS.from(c.uuid) { chars[k] = c } }
            log("FTMS characteristics: " + chars.keys.map { String($0.rawValue.dropFirst(4).prefix(4)) }.sorted().joined(separator: " "))
            if chars[.treadmillData] != nil { kind = .treadmill } else if chars[.indoorBikeData] != nil { kind = .bike }
            guard let kind else { log("Found the device but no treadmill or bike data on it"); return }
            log(kind == .treadmill ? "Treadmill detected" : "Smart bike detected")
            hub?.update { $0.machineKind = kind }

            if let d = chars[kind == .treadmill ? .treadmillData : .indoorBikeData] { peripheral.setNotifyValue(true, for: d) }
            if let s = chars[.machineStatus] { peripheral.setNotifyValue(true, for: s) }
            for r in [FTMS.speedRange, .inclineRange, .powerRange] { if let c = chars[r] { peripheral.readValue(for: c) } }
            if let cp = chars[.controlPoint] {
                peripheral.setNotifyValue(true, for: cp)  // control requested once indications are on
            } else {
                log("No control access, so display only")
                hub?.connectionReady(.machine)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            guard FTMS.from(characteristic.uuid) == .controlPoint else { return }
            if let error {
                log("Control point unavailable: \(error.localizedDescription)")
                chars[.controlPoint] = nil
                hub?.connectionReady(.machine)
                return
            }
            send(ControlPoint.requestControl()) { [weak self] ok in
                guard let self else { return }
                hasControl = ok
                log(ok ? "Control granted" : "Control request not accepted")
                if ok, kind == .bike { send(ControlPoint.start()) }  // never auto-start a treadmill belt
                hub?.connectionReady(.machine)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        let value = characteristic.value ?? Data()
        let which = FTMS.from(characteristic.uuid)
        MainActor.assumeIsolated {
            switch which {
            case .treadmillData:
                guard let t = TreadmillData.parse(value) else { return }
                if !dataSeen { dataSeen = true; log("Receiving treadmill data") }
                hub?.update { live in
                    if let v = t.speedKmh { live.speedKmh = v }
                    if let v = t.inclinePercent { live.inclinePercent = v }
                    if let v = t.totalDistance { live.machineDistance = v }
                    if let v = t.heartRate { live.machineHeartRate = v }
                }
            case .indoorBikeData:
                guard let b = IndoorBikeData.parse(value) else { return }
                if !dataSeen { dataSeen = true; log("Receiving bike data") }
                hub?.update { live in
                    if let v = b.speedKmh { live.speedKmh = v }
                    if let v = b.power { live.power = v }
                    if let v = b.cadence { live.bikeCadence = v }
                    if let v = b.totalDistance { live.machineDistance = v }
                    if let v = b.heartRate { live.machineHeartRate = v }
                }
            case .controlPoint:
                guard let r = ControlPoint.parseResponse(value) else { return }
                if r.result != .success { log("\(r.request.label): \(r.result.label)") }
                if r.result == .controlNotPermitted, r.request != .requestControl {
                    send(ControlPoint.requestControl())
                }
                finish(r.request, ok: r.result == .success)
            case .machineStatus:
                if MachineStatus.parse(value) == .controlLost { hasControl = false; log("Another app took control") }
            case .speedRange:
                speedRange = SupportedRange.speed(value)
                if let r = speedRange { log("Speed range \(r.min)–\(r.max) km/h") }
            case .inclineRange:
                inclineRange = SupportedRange.incline(value)
                if let r = inclineRange { log("Incline range \(r.min)–\(r.max) % in \(r.step) % steps") }
            case .powerRange:
                powerRange = SupportedRange.power(value)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        guard let error else { return }
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            guard let op = inFlight?.op else { return }
            finish(op, ok: false, note: "Write failed (\(op.label)): \(message)")
        }
    }
}

// MARK: - Heart-rate strap / footpod

/// A heart-rate strap or running footpod (or a device that's both; each slot reads its own profile).
@MainActor
final class SensorConnection: NSObject, @MainActor CBPeripheralDelegate {
    let peripheral: CBPeripheral
    let slot: DeviceSlot
    private weak var hub: BluetoothHub?

    init(peripheral: CBPeripheral, slot: DeviceSlot, hub: BluetoothHub) {
        self.peripheral = peripheral
        self.slot = slot
        self.hub = hub
        super.init()
        peripheral.delegate = self
    }

    func start() { peripheral.discoverServices(slot.services.map(\.uuid)) }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            let want: FTMS = slot == .heartRate ? .heartRateMeasurement : .rscMeasurement
            if let c = service.characteristics?.first(where: { FTMS.from($0.uuid) == want }) {
                peripheral.setNotifyValue(true, for: c)
                hub?.record("\(slot.title) connected: \(peripheral.name ?? "sensor")")
                hub?.connectionReady(slot)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let value = characteristic.value ?? Data()
        let which = FTMS.from(characteristic.uuid)
        MainActor.assumeIsolated {
            switch which {
            case .heartRateMeasurement:
                if let bpm = HeartRateMeasurement.parse(value) { hub?.update { $0.strapHeartRate = bpm } }
            case .rscMeasurement:
                if let m = RSCMeasurement.parse(value) {
                    hub?.update { $0.footpodCadence = m.cadence; $0.footpodSpeedKmh = m.speedKmh }
                }
            default: break
            }
        }
    }
}
