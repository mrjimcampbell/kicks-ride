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
        let unity = #"{"tvStatus":{"_0":{"tvName":"Living Room","settings":{"time":"Night","weather":"Clear","camera":"Orbit","quality":"PC","screensaver":false,"holdWetness":false,"showFPS":false,"frameRate":60,"ambientOcclusion":"Subtle","antiAliasing":"SMAA","lensDirt":false,"vignette":true,"filmGrain":false,"chromaticAberration":false,"calibration":false,"renderScale":0.0,"screensaverSpeed":0.0,"wetness":0.25,"volumetric":1.0,"fog":1.0},"times":["Midday","Night"],"weathers":["Clear","Rain"],"cameras":["Orbit","Standard"],"qualityLevels":["Mobile","PC"],"ambientOcclusionModes":["Off","Subtle","Strong"],"antiAliasingModes":["Off","SMAA"],"fps":59.8,"running":false,"resolution":"3840×2160 · 3D 3072×1728","frameRates":[50,25],"refreshRate":50.0}}}"#
        guard case .tvStatus(let st) = try LinkMessage.decode(Data(unity.utf8)) else {
            Issue.record("not a tvStatus"); return
        }
        #expect(st.tvName == "Living Room")
        #expect(st.settings.wetness == 0.25)
        #expect(st.qualityLevels == ["Mobile", "PC"])
        #expect(st.settings.antiAliasing == "SMAA")
        #expect(st.frameRates == [50, 25])
    }

    /// Dev dashboard: the TV lists controls (JsonUtility writes every field, empty arrays included).
    @Test func decodesUnityDevControls() throws {
        let unity = #"{"tvStatus":{"_0":{"tvName":"TV","settings":{"time":"Night","weather":"Clear","camera":"Orbit","quality":"PC","screensaver":false,"holdWetness":false,"showFPS":false,"frameRate":60,"ambientOcclusion":"Subtle","antiAliasing":"SMAA","lensDirt":false,"vignette":true,"filmGrain":false,"chromaticAberration":false,"calibration":false,"renderScale":0.0,"screensaverSpeed":0.0,"wetness":0.25,"volumetric":1.0,"fog":1.0,"dev":[{"key":"track","value":"Current"},{"key":"trackTile","value":"2"}]},"times":[],"weathers":[],"cameras":[],"qualityLevels":[],"ambientOcclusionModes":[],"antiAliasingModes":[],"fps":60.0,"running":false,"resolution":"","frameRates":[60,30],"refreshRate":60.0,"devControls":[{"key":"track","label":"Surface","group":"Track surface","kind":"choice","value":"Current","note":"","options":["Current","B"],"min":0.0,"max":0.0,"step":0.0},{"key":"trackTile","label":"Tile size (m)","group":"Track surface","kind":"slider","value":"2","note":"","options":[],"min":0.5,"max":8.0,"step":0.25}]}}}"#
        guard case .tvStatus(let st) = try LinkMessage.decode(Data(unity.utf8)) else {
            Issue.record("not a tvStatus"); return
        }
        #expect(st.devControls?.count == 2)
        #expect(st.devControls?[1].max == 8)
        #expect(st.settings.dev?.first == DevValue(key: "track", value: "Current"))
    }
}
