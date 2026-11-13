import Foundation
import Testing
@testable import KicksLink

/// The Unity TV app decodes these with JsonUtility, so the wire shape matters:
/// `{"tvSet":{"_0":{…flat fields…}}}` and `{"tvStatus":{"_0":{…, "settings":{…}}}}`.
@Suite struct LinkMessageTests {
    @Test func tvSetRoundTripsAndKeepsItsShape() throws {
        let s = TVSettings(time: "Dusk", weather: "Rain", camera: "Low", screensaver: true,
                           screensaverSpeed: 12.5, quality: "PC", wetness: -1, holdWetness: true,
                           volumetric: 1.5, fog: 0.5, showFPS: true)
        let data = try LinkMessage.tvSet(s).encoded()
        let json = String(decoding: data, as: UTF8.self)
        print("tvSet JSON:", json)
        #expect(json.hasPrefix("{\"tvSet\":{\"_0\":{"))
        #expect(try LinkMessage.decode(data) == .tvSet(s))
    }

    /// What the Unity app's JsonUtility.ToJson writes (doubles as 1.0, arrays inline).
    @Test func decodesUnityStatus() throws {
        let unity = #"{"tvStatus":{"_0":{"tvName":"Living Room","settings":{"time":"Night","weather":"Clear","camera":"Orbit","quality":"PC","screensaver":false,"holdWetness":false,"showFPS":false,"frameRate":60,"screensaverSpeed":0.0,"wetness":0.25,"volumetric":1.0,"fog":1.0},"times":["Midday","Night"],"weathers":["Clear","Rain"],"cameras":["Orbit","Standard"],"qualityLevels":["Mobile","PC"],"fps":59.8,"running":false,"resolution":"3840×2160 · 3D 3072×1728"}}}"#
        guard case .tvStatus(let st) = try LinkMessage.decode(Data(unity.utf8)) else {
            Issue.record("not a tvStatus"); return
        }
        #expect(st.tvName == "Living Room")
        #expect(st.settings.wetness == 0.25)
        #expect(st.qualityLevels == ["Mobile", "PC"])
    }
}
