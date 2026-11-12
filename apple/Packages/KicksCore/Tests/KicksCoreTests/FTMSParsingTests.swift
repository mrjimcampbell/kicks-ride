import Testing
import Foundation
@testable import KicksFTMS

/// Byte packets built per the Bluetooth FTMS / HRS / RSCS specs (little-endian).
@Suite struct FTMSParsingTests {
    @Test func treadmillSpeedOnly() {
        // flags 0x0000 → speed present; 10.50 km/h = 1050 = 0x041A
        let t = TreadmillData.parse(Data([0x00, 0x00, 0x1A, 0x04]))
        #expect(t?.speedKmh == 10.5)
        #expect(t?.inclinePercent == nil)
    }

    @Test func treadmillDistanceInclineHeartRateElapsed() {
        // flags: distance 0x04 | incline 0x08 | HR 0x100 | elapsed 0x400 = 0x050C
        let bytes: [UInt8] = [0x0C, 0x05,
                              0xDC, 0x05,             // speed 15.00 km/h
                              0x90, 0x01, 0x00,       // distance 400 m
                              0x0F, 0x00, 0x00, 0x00, // incline 1.5 %, ramp angle
                              0x9B,                   // HR 155
                              0x5A, 0x00]             // elapsed 90 s
        let t = TreadmillData.parse(Data(bytes))
        #expect(t == TreadmillData(speedKmh: 15, totalDistance: 400, inclinePercent: 1.5, heartRate: 155, elapsed: 90))
    }

    @Test func treadmillSkipsFieldsWeDontUse() {
        // avg speed 0x02, elevation 0x10, inst pace 0x20, avg pace 0x40, energy 0x80, then HR 0x100
        let bytes: [UInt8] = [0xF2, 0x01,
                              0x32, 0x00,                   // speed 0.50 km/h (belt starting)
                              0x00, 0x00,                   // avg speed
                              0x00, 0x00, 0x00, 0x00,       // elevation gain +/-
                              0x00, 0x00,                   // paces
                              0x00, 0x00, 0x00, 0x00, 0x00, // energy
                              0x78]                         // HR 120
        let t = TreadmillData.parse(Data(bytes))
        #expect(t?.speedKmh == 0.5)
        #expect(t?.heartRate == 120)
    }

    @Test func treadmillShortPacketKeepsWhatItHas() {
        let t = TreadmillData.parse(Data([0x08, 0x00, 0xE8, 0x03, 0x0A]))  // incline truncated
        #expect(t?.speedKmh == 10)
        #expect(t?.inclinePercent == nil)
    }

    @Test func bikePowerCadenceHeartRate() {
        // flags: cadence 0x04 | power 0x40 | HR 0x200 = 0x0244
        let bytes: [UInt8] = [0x44, 0x02,
                              0x4C, 0x0D,   // speed 34.04 km/h
                              0xB4, 0x00,   // cadence 90 rpm (×0.5)
                              0xC8, 0x00,   // 200 W
                              0x8C]         // HR 140
        let b = IndoorBikeData.parse(Data(bytes))
        #expect(b?.speedKmh == 34.04)
        #expect(b?.cadence == 90)
        #expect(b?.power == 200)
        #expect(b?.heartRate == 140)
    }

    @Test func heartRate8And16Bit() {
        #expect(HeartRateMeasurement.parse(Data([0x00, 0x96])) == 150)
        #expect(HeartRateMeasurement.parse(Data([0x01, 0x2C, 0x01])) == 300)
        #expect(HeartRateMeasurement.parse(Data([0x00, 0x00])) == nil)
    }

    @Test func footpodDoublesStrideCadenceWhenRunning() {
        // 3.33 m/s ≈ 12 km/h (853/256), 85 strides/min → 170 steps/min
        let m = RSCMeasurement.parse(Data([0x04, 0x55, 0x03, 85]))
        #expect(m?.cadence == 170)
        #expect(abs((m?.speedKmh ?? 0) - 12.0) < 0.05)
        // already steps/min: left alone
        #expect(RSCMeasurement.parse(Data([0x04, 0x55, 0x03, 172]))?.cadence == 172)
    }

    @Test func ranges() {
        #expect(SupportedRange.speed(Data([0x64, 0x00, 0xD0, 0x07, 0x0A, 0x00]))
                == SupportedRange(min: 1, max: 20, step: 0.1))
        #expect(SupportedRange.incline(Data([0x00, 0x00, 0x96, 0x00, 0x05, 0x00]))
                == SupportedRange(min: 0, max: 15, step: 0.5))
    }

    @Test func controlPointEncoding() {
        #expect(ControlPoint.setSpeed(kmh: 14.5) == Data([0x02, 0xAA, 0x05]))     // 1450
        #expect(ControlPoint.setIncline(percent: 1.5) == Data([0x03, 0x0F, 0x00]))
        #expect(ControlPoint.stop() == Data([0x08, 0x01]))
        #expect(ControlPoint.setIncline(percent: -2) == Data([0x03, 0xEC, 0xFF]))
        #expect(ControlPoint.setTargetPower(watts: 250) == Data([0x05, 0xFA, 0x00]))
        #expect(ControlPoint.setSimulation(gradePercent: 4, crr: 0.004, cw: 0.51)
                == Data([0x11, 0, 0, 0x90, 0x01, 40, 51]))
    }

    @Test func controlPointResponse() {
        #expect(ControlPoint.parseResponse(Data([0x80, 0x02, 0x01]))
                == .init(request: .setSpeed, result: .success))
        #expect(ControlPoint.parseResponse(Data([0x80, 0x03, 0x05]))?.result == .controlNotPermitted)
        #expect(ControlPoint.parseResponse(Data([0x02, 0x01])) == nil)
    }
}
