import RealityKit
import Foundation
import CoreGraphics
import ImageIO
import Observation
import UIKit
import KicksCore

/// Look-dev rig for sky, light and mood: a time of day × a weather.
/// - Sky: an HDRI for image-based lighting (1K .hdr, never seen directly) plus the same HDRI's
///   tonemapped panorama on an unlit dome that follows the camera.
/// - Sun: a directional light with shadows at the HDRI's brightest point (clear weather only).
/// - Floodlights on the six masts at night and dusk (spot lights with shadows + glow sprites).
/// - Rain: falling streaks + ground splashes around the camera, a wet (glossy, darker) track,
///   puddles, dimmer sky. Fog: layered mist shells round the camera (a cheap fake; no
///   real volumetrics in RealityKit). Light beams from the masts in rain/fog after dark.
/// - Bloom (tvOS 27+) on the emissive lamp faces when the floodlights are on.
/// Skies come from tools/sky/fetch_skies.sh (Poly Haven, CC0), copied in by a build phase.
/// Remote while idle: up/down = time of day, click = weather.
/// Launch args: `-kr-sky <time>` and `-kr-weather <weather>`.
enum TimeOfDay: String, CaseIterable, Identifiable {
    case midday, morning, golden, dusk, night
    var id: String { rawValue }
    var title: String {
        switch self {
        case .midday: "Midday"
        case .morning: "Dawn"
        case .golden: "Golden hour"
        case .dusk: "Dusk"
        case .night: "Night"
        }
    }
    var isDark: Bool { self == .night }
    /// Floodlights on.
    var lightsOn: Bool { self == .night || self == .dusk }

    struct Look {
        var sunLux: Float           // directional sun in clear weather (0 = none)
        var iblExposure: Float      // ImageBasedLightComponent.intensityExponent
        var yawDegrees: Float = 0   // turn the whole sky so the sun sits well against the arena
    }
    var look: Look {
        switch self {
        case .midday:  Look(sunLux: 6000, iblExposure: 0.3, yawDegrees: 40)
        case .morning: Look(sunLux: 1500, iblExposure: 0.2, yawDegrees: 150)
        case .golden:  Look(sunLux: 4000, iblExposure: 0.2, yawDegrees: 200)
        case .dusk:    Look(sunLux: 0, iblExposure: -0.6, yawDegrees: 160)
        case .night:   Look(sunLux: 0, iblExposure: -1.5)
        }
    }
}

enum Weather: String, CaseIterable, Identifiable {
    case clear, overcast, rain, fog
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor @Observable
final class SkyRig {
    var time: TimeOfDay = .night {
        didSet { if time != oldValue { changed() } }
    }
    var weather: Weather = .clear {
        didSet { if weather != oldValue { changed() } }
    }
    private(set) var banner: String?
    var title: String { weather == .clear ? time.title : "\(time.title) · \(weather.title)" }

    /// Add this to the scene; then call `addReceivers(to:)` on the scene root once loaded.
    @ObservationIgnored let root = Entity()
    @ObservationIgnored private let ibl = Entity()
    @ObservationIgnored private let dome: ModelEntity
    @ObservationIgnored private let sun = DirectionalLight()
    @ObservationIgnored private var floods: [SpotLight] = []
    @ObservationIgnored private var glows: [Entity] = []
    @ObservationIgnored private let rain = Entity()
    @ObservationIgnored private let splashes = Entity()
    @ObservationIgnored private let puddles = Entity()
    @ObservationIgnored private let fog = Entity()
    @ObservationIgnored private var fogShells: [ModelEntity] = []
    @ObservationIgnored private var beams: [Entity] = []
    @ObservationIgnored private var lampFaces: [Entity] = []
    /// Set by ArenaView before `addReceivers`, so puddles land on the lanes.
    @ObservationIgnored var track: TrackGeometry?
    @ObservationIgnored private var wetSurfaces: [(entity: ModelEntity, dry: [any RealityKit.Material])] = []
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var applied: String?

    /// Floodlight heads (RealityKit coordinates, track centre at origin), from the six
    /// Lamps_n objects in the arena .blend (top at ~24.6 m).
    static let mastHeads: [SIMD3<Float>] = [
        (75.8, -42.0), (75.7, 53.6), (-90.5, 53.6), (-91.1, -42.0), (-6.0, -54.8), (-5.9, 53.7),
    ].map { bx, by in SIMD3<Float>(bx + 6.420, 24.0 - 0.538, -by - 4.002) }

    init() {
        dome = ModelEntity(mesh: Self.domeMesh(radius: 900), materials: [UnlitMaterial(color: .black)])
        root.addChild(dome)
        root.addChild(ibl)
        // tvOS ignores the old maximumDistance property; the projection must be set this way.
        sun.shadow = DirectionalLightComponent.Shadow(shadowProjection: .automatic(maximumDistance: 150), depthBias: 1)
        root.addChild(sun)

        let glowTexture = try? TextureResource(image: Self.radialGlowImage(), options: .init(semantic: .color))
        for head in Self.mastHeads {
            let s = SpotLight()
            s.light.color = .init(red: 1, green: 0.95, blue: 0.85, alpha: 1)
            s.light.innerAngleInDegrees = 35
            s.light.outerAngleInDegrees = 65
            s.light.attenuationRadius = 260
            s.shadow = SpotLightComponent.Shadow()
            // Aim inwards and down, at the near side of the track rather than the centre spot.
            s.look(at: SIMD3<Float>(head.x * 0.35, 0, head.z * 0.35), from: head, relativeTo: nil)
            floods.append(s)
            root.addChild(s)

            // Glow: a camera-facing soft disc over the lamp bank (a fake bloom).
            let glow = Entity()
            glow.position = head + [0, 1.2, 0]
            glow.components.set(BillboardComponent())
            var m = UnlitMaterial()
            if let glowTexture { m.color = .init(tint: .white, texture: .init(glowTexture)) }
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            let disc = ModelEntity(mesh: .generatePlane(width: 14, height: 14), materials: [m])
            glow.addChild(disc)
            glows.append(glow)

            // Lamp face: a bright emissive panel facing the track (what bloom catches).
            var face = PhysicallyBasedMaterial()
            face.baseColor = .init(tint: .white)
            face.emissiveColor = .init(color: .init(red: 1, green: 0.95, blue: 0.85, alpha: 1))
            face.emissiveIntensity = 12
            let panel = ModelEntity(mesh: .generateBox(width: 3.2, height: 2.6, depth: 0.1), materials: [face])
            panel.transform = s.transform
            panel.position = head + [0, 0.3, 0]
            lampFaces.append(panel)
            root.addChild(panel)

            // Beam: a soft cone of light down the spot's axis, only in rain/fog after dark.
            let beam = ModelEntity(mesh: Self.coneMesh(length: 70, radius: 26), materials: [Self.beamMaterial])
            beam.transform = s.transform
            beams.append(beam)
            root.addChild(beam)
            root.addChild(glow)
        }

        rain.components.set(Self.rainEmitter())
        root.addChild(rain)
        splashes.components.set(Self.splashEmitter())
        root.addChild(splashes)
        root.addChild(puddles)

        // Fog: camera-centred open cylinders; each hides a little more of what lies beyond it,
        // so distant things fade (in steps — a cheap stand-in for real distance fog).
        for r: Float in [12, 18, 26, 38, 55, 80, 115, 165, 240, 350] {
            let shell = ModelEntity(mesh: Self.shellMesh(radius: r, height: 70), materials: [UnlitMaterial()])
            fogShells.append(shell)
            fog.addChild(shell)
        }
        root.addChild(fog)
    }

    /// Every model in the scene lights from our HDRI rather than RealityKit's default. Also
    /// fixes the arena's over-glossy grass and remembers the track surfaces for wet weather.
    func addReceivers(to entity: Entity) {
        if var model = entity.components[ModelComponent.self], entity !== dome, !isRigPart(entity) {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
            // Meshes sit under an entity named after their Blender object; everything else in
            // the arena is parented under TF_GrassField, so match the direct parent only.
            let object = entity.parent?.name ?? ""
            if ProcessInfo.processInfo.arguments.contains("-kr-dump") { print("model: \(entity.name) in \(object)") }
            if object == "TF_GrassField" {
                model.materials = model.materials.map { m in
                    guard var pbr = m as? PhysicallyBasedMaterial else { return m }
                    pbr.roughness = .init(floatLiteral: 0.95)
                    pbr.specular = .init(floatLiteral: 0.15)
                    return pbr
                }
                entity.components.set(model)
            } else if object == "Track_Lanes", let me = entity as? ModelEntity {
                wetSurfaces.append((me, model.materials))
            }
        }
        for child in entity.children { addReceivers(to: child) }
    }

    private func isRigPart(_ e: Entity) -> Bool {
        var p: Entity? = e
        while let x = p { if x === root { return true }; p = x.parent }
        return false
    }

    /// Keep the dome centred on the camera so the sky never shows parallax; rain falls around it.
    func follow(camera: Entity) {
        let p = camera.position(relativeTo: nil)
        dome.position = p
        rain.position = p + [0, 14, 0]
        splashes.position = [p.x, 0.03, p.z]
        fog.position = [p.x, 0, p.z]
    }

    func nextTime() { time = Self.step(time, 1) }
    func previousTime() { time = Self.step(time, -1) }
    func nextWeather() { weather = Self.step(weather, 1) }
    private static func step<T: CaseIterable & Equatable>(_ v: T, _ d: Int) -> T {
        let all = Array(T.allCases)
        return all[((all.firstIndex(of: v) ?? 0) + d + all.count) % all.count]
    }

    private func changed() {
        banner = title
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
        Task { await apply() }
    }

    /// Scatter puddles over the lanes (fixed seed, so they're always in the same places).
    private func buildPuddles() {
        guard puddles.children.isEmpty, let track else { return }
        var rng = SplitMix(seed: 7)
        let tex = try? TextureResource(image: Self.puddleImage(), options: .init(semantic: .raw))
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .init(white: 0.05, alpha: 1))
        m.roughness = .init(floatLiteral: 0.02)
        m.metallic = .init(floatLiteral: 0)
        m.specular = .init(floatLiteral: 1)
        if let tex { m.blending = .transparent(opacity: .init(scale: 0.85, texture: .init(tex))) }
        for _ in 0..<70 {
            let d = Double(rng.next() % 400)
            let lane = 1 + Int(rng.next() % 8)
            let p = track.displayPose(distance: d, lane: lane)
            let w = 0.6 + Float(rng.next() % 100) / 100 * 1.6
            let puddle = ModelEntity(mesh: .generatePlane(width: w, depth: w * 0.7), materials: [m])
            puddle.position = [Float(p.x), 0.006, Float(-p.y)]
            puddle.orientation = simd_quatf(angle: Float(rng.next() % 628) / 100, axis: [0, 1, 0])
            puddle.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
            puddles.addChild(puddle)
        }
    }

    func apply() async {
        let t = time, w = weather
        let key = "\(t.rawValue).\(w.rawValue)"
        guard applied != key else { return }
        applied = key
        let look = t.look
        let yaw = simd_quatf(angle: look.yawDegrees * .pi / 180, axis: [0, 1, 0])
        // Grey skies by day come from the overcast HDRI; at night the night sky, dimmed.
        let file = (w == .clear || t.isDark) ? t.rawValue : "overcast"
        let gloom: Float = w == .clear ? 1 : (w == .rain ? 0.5 : 0.75)
        var iblExposure = file == "overcast" ? (w == .rain ? 0.4 : 0.9) : look.iblExposure
        if t.isDark && w != .clear { iblExposure -= 0.7 }
        if t == .dusk && w != .clear { iblExposure = -0.8 }

        // Load first, then swap in one go (a newer choice may arrive meanwhile).
        var sunDir = SIMD3<Float>(0.4, 0.8, 0.3)
        var sunColour = SIMD3<Float>(1, 1, 1)
        var env: EnvironmentResource?
        if let url = Bundle.main.url(forResource: "sky_\(file)", withExtension: "hdr"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            if let peak = Self.brightestDirection(image) { sunDir = peak.direction; sunColour = peak.colour }
            env = try? await EnvironmentResource(equirectangular: image, withName: "sky_\(file)")
        } else {
            print("SkyRig: sky_\(file).hdr missing — run tools/sky/fetch_skies.sh")
        }
        var material = UnlitMaterial()
        if let url = Bundle.main.url(forResource: "sky_\(file)", withExtension: "jpg"),
           let tex = await Self.loadBackdrop(url) {
            let g = CGFloat(gloom * (t.isDark ? 0.8 : 1))
            material.color = .init(tint: .init(red: g, green: g, blue: g * 1.02, alpha: 1), texture: .init(tex))
        }
        guard time == t, weather == w else { return }

        if let env {
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: iblExposure))
        }
        ibl.orientation = yaw
        dome.model?.materials = [material]
        dome.orientation = yaw

        let dir = yaw.act(sunDir)
        let sunOn = w == .clear && look.sunLux > 0
        sun.isEnabled = sunOn
        sun.light.intensity = look.sunLux
        sun.light.color = .init(red: CGFloat(sunColour.x), green: CGFloat(sunColour.y), blue: CGFloat(sunColour.z), alpha: 1)
        sun.look(at: .zero, from: dir * 100, relativeTo: nil)

        let lumens: Float = t.isDark ? 25_000_000 : 10_000_000
        for f in floods { f.isEnabled = t.lightsOn; f.light.intensity = t.lightsOn ? lumens : 0 }
        for g in glows { g.isEnabled = t.lightsOn }
        for f in lampFaces { f.isEnabled = t.lightsOn }
        for b in beams { b.isEnabled = t.lightsOn && (w == .rain || w == .fog) }
        if #available(tvOS 27.0, *) {
            if t.lightsOn {
                root.components.set(BloomComponent(scope: .unbounded))
                var o = BloomOptionsComponent()
                o.strength = 0.6; o.threshold = 1.0; o.blurRadius = 24
                root.components.set(o)
            } else {
                root.components.remove(BloomComponent.self)
            }
        }

        // Mist: thick in fog, a light haze in rain, none otherwise. Colour follows the light.
        let mistAlpha: Float = w == .fog ? 0.17 : (w == .rain ? 0.045 : 0)   // per layer (10 layers)
        fog.isEnabled = mistAlpha > 0
        if mistAlpha > 0 {
            // Night mist is lighter than the sky: it glows in the floodlights.
            let c: SIMD3<Float> = t.isDark ? [0.30, 0.31, 0.34] : t == .dusk ? [0.40, 0.36, 0.42]
                : t == .golden ? [0.85, 0.75, 0.6] : [0.78, 0.80, 0.83]
            let tex = try? await TextureResource(image: Self.mistImage(colour: c, alpha: mistAlpha), options: .init(semantic: .color))
            var m = UnlitMaterial()
            if let tex { m.color = .init(tint: .white, texture: .init(tex)); m.blending = .transparent(opacity: .init(floatLiteral: 1)) }
            for shell in fogShells { shell.model?.materials = [m] }
        }

        // Rain: streaks on, track wet (glossier and darker).
        rain.isEnabled = w == .rain
        splashes.isEnabled = w == .rain
        buildPuddles()
        puddles.isEnabled = w == .rain
        for s in wetSurfaces {
            s.entity.model?.materials = w == .rain ? s.dry.map(Self.wet) : s.dry
        }
        print("SkyRig: \(key) sky \(file) sun \(sunOn ? "\(dir)" : "off"), \(wetSurfaces.count) wet-able surfaces")
    }

    private static func wet(_ m: any RealityKit.Material) -> any RealityKit.Material {
        guard var pbr = m as? PhysicallyBasedMaterial else { return m }
        pbr.roughness = .init(floatLiteral: 0.12)
        pbr.specular = .init(floatLiteral: 0.8)
        pbr.baseColor.tint = .init(white: 0.7, alpha: 1)
        return pbr
    }

    private static func splashEmitter() -> ParticleEmitterComponent {
        var e = ParticleEmitterComponent()
        e.emitterShape = .box
        e.emitterShapeSize = [40, 0.01, 40]
        e.birthLocation = .volume
        e.birthDirection = .world
        e.emissionDirection = [0, 1, 0]
        e.speed = 1.4
        e.speedVariation = 0.6
        e.fieldSimulationSpace = .global
        e.particlesInheritTransform = false
        var p = e.mainEmitter
        p.birthRate = 5000
        p.lifeSpan = 0.22
        p.spreadingAngle = 0.7
        p.size = 0.014
        p.acceleration = [0, -9.8, 0]
        p.isLightingEnabled = false
        p.blendMode = .alpha
        p.color = .constant(.single(UIColor(white: 0.9, alpha: 0.45)))
        e.mainEmitter = p
        return e
    }

    private static func rainEmitter() -> ParticleEmitterComponent {
        var e = ParticleEmitterComponent()
        e.emitterShape = .box
        e.emitterShapeSize = [60, 1, 60]
        e.birthLocation = .volume
        e.birthDirection = .world
        e.emissionDirection = [0.05, -1, 0]
        e.speed = 14
        e.speedVariation = 2
        e.fieldSimulationSpace = .global
        e.particlesInheritTransform = false
        var p = e.mainEmitter
        p.birthRate = 9000
        p.lifeSpan = 1.4
        p.size = 0.02
        p.stretchFactor = 6
        p.acceleration = [0, -6, 0]
        p.isLightingEnabled = false
        p.blendMode = .alpha
        p.color = .constant(.single(UIColor(white: 0.9, alpha: 0.5)))
        e.mainEmitter = p
        return e
    }

    static func radialGlowImage(size: Int = 128) -> CGImage {
        var px = [UInt8](repeating: 0, count: size * size * 4)
        let c = Float(size - 1) / 2
        for y in 0..<size {
            for x in 0..<size {
                let d = min(1, hypot(Float(x) - c, Float(y) - c) / c)
                let a = pow(1 - d, 2.4)                       // soft falloff
                let i = (y * size + x) * 4
                let v = UInt8(255 * a)
                px[i] = v; px[i + 1] = UInt8(Float(v) * 0.96); px[i + 2] = UInt8(Float(v) * 0.88); px[i + 3] = v
            }
        }
        let ctx = CGContext(data: &px, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    // MARK: - Helpers

    /// Inward-facing sphere with equirectangular UVs: u = longitude (0 at -Z, increasing
    /// towards +X), v = latitude (top of the image = straight up).
    static func domeMesh(radius: Float, segments: Int = 96, rings: Int = 48) -> MeshResource {
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for r in 0...rings {
            let v = Float(r) / Float(rings)                 // 0 = top
            let lat = Float.pi / 2 - v * .pi
            for s in 0...segments {
                let u = Float(s) / Float(segments)
                positions.append(direction(u: u, lat: lat) * radius)
                uvs.append([u, 1 - v])                      // RealityKit textures: v = 1 at the top
            }
        }
        let row = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = r * row + s, b = a + row
                indices += [a, b, a + 1, a + 1, b, b + 1]   // wound to face inwards
            }
        }
        var d = MeshDescriptor(name: "skyDome")
        d.positions = .init(positions)
        d.textureCoordinates = .init(uvs)
        d.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [d])
    }

    static func direction(u: Float, lat: Float) -> SIMD3<Float> {
        let lon = u * 2 * .pi
        return [cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon)]
    }

    /// Brightest pixel of the HDRI (the sun, or the moon at night), as a direction in the
    /// dome's convention, with its colour normalised to max 1.
    static func brightestDirection(_ image: CGImage) -> (direction: SIMD3<Float>, colour: SIMD3<Float>)? {
        let w = 256, h = 128
        var px = [Float](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 32, bytesPerRow: w * 16, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var best = 0, bestLum: Float = -1
        for i in 0..<(w * h / 2) {                           // upper half only (memory row 0 = top)
            let lum = 0.2126 * px[i * 4] + 0.7152 * px[i * 4 + 1] + 0.0722 * px[i * 4 + 2]
            if lum > bestLum { bestLum = lum; best = i }
        }
        let x = best % w, y = best / w
        let lat = Float.pi / 2 - (Float(y) + 0.5) / Float(h) * .pi
        let c = SIMD3<Float>(px[best * 4], px[best * 4 + 1], px[best * 4 + 2])
        let m = max(c.x, c.y, c.z, 1e-6)
        return (direction(u: (Float(x) + 0.5) / Float(w), lat: lat), c / m)
    }

    /// 8K panorama on a 4 GB+ Apple TV, 4K on older ones (the Apple TV HD has 2 GB).
    static func loadBackdrop(_ url: URL) async -> TextureResource? {
        let big = ProcessInfo.processInfo.physicalMemory > 3_000_000_000
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let image: CGImage? = big
            ? CGImageSourceCreateImageAtIndex(src, 0, nil)
            : CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                           kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary)
        guard let image else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: .color))
    }

    static let beamMaterial: UnlitMaterial = {
        var m = UnlitMaterial()
        if let tex = try? TextureResource(image: beamImage(), options: .init(semantic: .color)) {
            m.color = .init(tint: .white, texture: .init(tex))
        }
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        return m
    }()

    /// Open cone along -Z from the origin (both sides), v = 0 at the apex … 1 at the far end.
    static func coneMesh(length: Float, radius: Float, segments: Int = 32) -> MeshResource {
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for ring in 0...1 {
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                let r = ring == 0 ? 0.6 : radius
                pos.append([cos(a) * r, sin(a) * r, ring == 0 ? 0 : -length])
                uv.append([Float(s) / Float(segments), Float(ring)])
            }
        }
        let row = UInt32(segments + 1)
        for s in 0..<UInt32(segments) {
            let a = s, b = s + row
            idx += [a, b, a + 1, a + 1, b, b + 1]      // one side
            idx += [a, a + 1, b, a + 1, b + 1, b]      // and the other
        }
        var d = MeshDescriptor(name: "beam")
        d.positions = .init(pos); d.textureCoordinates = .init(uv); d.primitives = .triangles(idx)
        return try! MeshResource.generate(from: [d])
    }

    /// Open vertical cylinder round the origin, sitting on the ground, both sides.
    static func shellMesh(radius: Float, height: Float, segments: Int = 64) -> MeshResource {
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for ring in 0...1 {
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                pos.append([cos(a) * radius, ring == 0 ? -2 : height, sin(a) * radius])
                uv.append([Float(s) / Float(segments), Float(ring)])
            }
        }
        let row = UInt32(segments + 1)
        for s in 0..<UInt32(segments) {
            let a = s, b = s + row
            idx += [a, b, a + 1, a + 1, b, b + 1]
            idx += [a, a + 1, b, a + 1, b + 1, b]
        }
        var d = MeshDescriptor(name: "fogShell")
        d.positions = .init(pos); d.textureCoordinates = .init(uv); d.primitives = .triangles(idx)
        return try! MeshResource.generate(from: [d])
    }

    /// Vertical strip: mist colour, alpha thickest at the ground and thinning upwards.
    static func mistImage(colour c: SIMD3<Float>, alpha: Float) -> CGImage {
        rgbaImage(width: 4, height: 128) { _, y in
            let up = Float(y) / 127                           // image row 0 = top (v = 1)
            let a = alpha * (0.45 + 0.55 * pow(up, 1.2))
            return [c.x * a, c.y * a, c.z * a, a]
        }
    }

    /// Beam: brightest near the lamp, fading out along its length.
    static func beamImage() -> CGImage {
        rgbaImage(width: 4, height: 128) { _, y in
            let along = 1 - Float(y) / 127                    // 0 at the lamp (v = 0 is the bottom row)
            let a = 0.10 * pow(1 - along, 2.2)
            return [1 * a, 0.96 * a, 0.88 * a, a]
        }
    }

    /// Puddle opacity: an irregular blob with soft edges.
    static func puddleImage(size: Int = 128) -> CGImage {
        rgbaImage(width: size, height: size) { x, y in
            let c = Float(size - 1) / 2
            let dx = (Float(x) - c) / c, dy = (Float(y) - c) / c
            let th = atan2(dy, dx), r = hypot(dx, dy)
            let edge = 0.72 + 0.12 * sin(3 * th + 1.3) + 0.07 * sin(7 * th + 0.4) + 0.04 * sin(13 * th)
            let a = max(0, min(1, (edge - r) / 0.12))
            return [a, a, a, a]
        }
    }

    static func rgbaImage(width w: Int, height h: Int, _ f: (Int, Int) -> SIMD4<Float>) -> CGImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = f(x, y), i = (y * w + x) * 4
                px[i] = UInt8(max(0, min(1, v.x)) * 255); px[i + 1] = UInt8(max(0, min(1, v.y)) * 255)
                px[i + 2] = UInt8(max(0, min(1, v.z)) * 255); px[i + 3] = UInt8(max(0, min(1, v.w)) * 255)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}

/// Small deterministic RNG (puddle layout).
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
