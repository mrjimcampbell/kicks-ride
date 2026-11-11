import Testing
@testable import KicksCore
@testable import KicksLink

@Suite struct TrackGeometryTests {
    let t = TrackGeometry.standard

    @Test func lane1IsFourHundredMetres() {
        #expect(abs(t.lapLength(lane: 1) - 400) < 0.01)
    }

    @Test func outerLanesAreLonger() {
        #expect(t.lapLength(lane: 2) > t.lapLength(lane: 1))
        #expect(abs(t.lapLength(lane: 8) - 453.03) < 0.05)
    }

    @Test func poseIsContinuousAndWrapsAtOneLap() {
        let start = t.pose(distance: 0)
        let lap = t.pose(distance: 400)
        // Spec figures are rounded: lane 1 is 400.001 m, so allow 1 cm.
        #expect(abs(start.x - lap.x) < 0.01 && abs(start.y - lap.y) < 0.01)
        var prev = t.pose(distance: 0)
        for d in stride(from: 0.5, through: 800, by: 0.5) {
            let p = t.pose(distance: d)
            let step = ((p.x - prev.x) * (p.x - prev.x) + (p.y - prev.y) * (p.y - prev.y)).squareRoot()
            #expect(step < 0.51)
            prev = p
        }
    }

    @Test func halfLapIsOnBackStraight() {
        let p = t.pose(distance: 200)
        #expect(abs(p.y - t.runningRadius(lane: 1)) < 1e-6)
    }

    @Test func linkMessageRoundTrips() throws {
        var s = SessionState(); s.distance = 1234; s.speedKmh = 14.4; s.heartRate = 151
        let m = LinkMessage.state(s)
        #expect(try LinkMessage.decode(m.encoded()) == m)
    }
}
