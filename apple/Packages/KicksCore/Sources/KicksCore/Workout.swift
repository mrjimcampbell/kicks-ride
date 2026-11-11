import Foundation

/// A structured workout, mirroring the web prototype's model (index.html).
/// Placeholder shape — to be fleshed out when porting the builder and player.
public struct Workout: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var blocks: [Block]

    public init(name: String, blocks: [Block]) {
        self.name = name
        self.blocks = blocks
    }

    public struct Block: Codable, Sendable, Equatable {
        public enum Length: Codable, Sendable, Equatable {
            case distance(metres: Double)
            case time(seconds: TimeInterval)
        }
        public enum Target: Codable, Sendable, Equatable {
            case pace(secondsPerKm: Double)   // run reps
            case speed(kmh: Double)           // run recoveries
            case ftpPercent(Double)           // ride ERG
        }
        public var title: String
        public var length: Length
        public var target: Target
        public var inclinePercent: Double?

        public init(title: String, length: Length, target: Target, inclinePercent: Double? = nil) {
            self.title = title
            self.length = length
            self.target = target
            self.inclinePercent = inclinePercent
        }
    }
}
