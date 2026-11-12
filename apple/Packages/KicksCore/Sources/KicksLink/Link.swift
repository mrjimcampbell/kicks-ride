import Foundation
import Network
import Observation
import KicksCore

/// Phone ⇄ TV transport: the phone advertises `_kicksride._tcp` on the home network
/// (Bonjour) and listens; each TV browses, connects to the first phone it finds and
/// reconnects on its own. Messages are JSON in WebSocket frames over TCP, so framing is
/// handled by Network.framework. Several TVs can watch one phone at once.
enum LinkParameters {
    static func make() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true          // notice a vanished peer within ~10 s
        tcp.keepaliveIdle = 4
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        p.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        return p
    }

    static func send(_ data: Data, on c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        c.send(content: data, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in })
    }

    /// Read messages until the connection ends.
    static func receive(on c: NWConnection, _ handle: @escaping @MainActor (LinkMessage) -> Void) {
        c.receiveMessage { data, _, _, error in
            MainActor.assumeIsolated {
                if let data, !data.isEmpty, let m = try? LinkMessage.decode(data) { handle(m) }
                if error == nil, c.state == .ready { receive(on: c, handle) }
            }
        }
    }
}

// MARK: - Phone side

@MainActor @Observable
public final class LinkHost {
    /// TVs currently connected.
    public private(set) var displayCount = 0
    /// Remote presses from a TV (pause/resume, speed up/down…).
    @ObservationIgnored public var onCommand: ((LinkMessage.Command) -> Void)?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [NWConnection] = []
    @ObservationIgnored private var last: Data?

    public init() {}

    public func start() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: LinkParameters.make())
            l.service = NWListener.Service(type: kicksBonjourType)   // name = the phone's name
            l.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if case .failed = state { self.restart() }
                }
            }
            l.newConnectionHandler = { [weak self] c in
                MainActor.assumeIsolated { self?.accept(c) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            print("[link] listener failed: \(error)")
        }
    }

    /// Send to every connected TV. The latest message is also replayed to TVs that join later.
    public func send(_ message: LinkMessage) {
        guard let data = try? message.encoded() else { return }
        last = data
        for c in connections { LinkParameters.send(data, on: c) }
    }

    private func restart() {
        listener?.cancel()
        listener = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.start()
        }
    }

    private func accept(_ c: NWConnection) {
        c.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if let last = self.last { LinkParameters.send(last, on: c) }
                case .failed, .cancelled:
                    c.cancel()
                    self.connections.removeAll { $0 === c }
                    self.displayCount = self.connections.count
                default: break
                }
            }
        }
        connections.append(c)
        displayCount = connections.count
        c.start(queue: .main)
        LinkParameters.receive(on: c) { [weak self] m in
            if case .command(let cmd) = m { self?.onCommand?(cmd) }
        }
    }
}

// MARK: - TV side

@MainActor @Observable
public final class LinkClient {
    /// Name of the phone we're connected to, nil while searching.
    public private(set) var phoneName: String?
    @ObservationIgnored public var onMessage: ((LinkMessage) -> Void)?
    /// Called when the phone goes away (treat as idle).
    @ObservationIgnored public var onDisconnect: (() -> Void)?

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var results: Set<NWBrowser.Result> = []
    @ObservationIgnored private var connection: NWConnection?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: kicksBonjourType, domain: nil), using: LinkParameters.make())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.results = results
                self?.connectIfNeeded()
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state {
                    self?.browser?.cancel(); self?.browser = nil
                    Task { try? await Task.sleep(for: .seconds(2)); self?.start() }
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    public func send(_ command: LinkMessage.Command) {
        guard let connection, let data = try? LinkMessage.command(command).encoded() else { return }
        LinkParameters.send(data, on: connection)
    }

    private func connectIfNeeded() {
        guard connection == nil, let result = results.first else { return }
        var name = "iPhone"
        if case .service(let n, _, _, _) = result.endpoint { name = n }
        let c = NWConnection(to: result.endpoint, using: LinkParameters.make())
        c.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.connection === c else { return }
                switch state {
                case .ready:
                    self.phoneName = name
                case .failed, .cancelled, .waiting:
                    c.cancel()
                    self.connection = nil
                    if self.phoneName != nil { self.phoneName = nil; self.onDisconnect?() }
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        self?.connectIfNeeded()
                    }
                default: break
                }
            }
        }
        connection = c
        c.start(queue: .main)
        LinkParameters.receive(on: c) { [weak self] m in self?.onMessage?(m) }
    }
}
