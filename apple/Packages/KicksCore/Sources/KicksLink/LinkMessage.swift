import Foundation
import KicksCore

/// Bonjour service type advertised by the phone and browsed by the TV.
/// Must match NSBonjourServices in both apps' Info.plist.
public let kicksBonjourType = "_kicksride._tcp"

/// Messages exchanged between phone and TV. JSON, one per framed message.
public enum LinkMessage: Codable, Sendable, Equatable {
    /// Phone → TV, about once a second during a run (the TV smooths in between).
    case state(SessionState)
    /// Phone → TV: no run in progress (app open, or the run just ended). TV goes back to idle.
    case idle
    /// TV → phone (Siri Remote / ring remote presses on the TV side).
    case command(Command)

    public enum Command: String, Codable, Sendable {
        case pause, resume, skipBlock, snapshot, speedUp, speedDown, end
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> LinkMessage {
        try JSONDecoder().decode(LinkMessage.self, from: data)
    }
}
