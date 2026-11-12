import RealityKit
import Foundation
import CoreGraphics
import ImageIO
import Observation

/// Look-dev test rig for sky, light and mood. Each preset pairs:
/// - an HDRI for image-based lighting (1K .hdr, never seen directly),
/// - a visible backdrop: the same HDRI's tonemapped panorama on an unlit dome that follows the
///   camera (or a plain gradient, to compare against),
/// - a sun (directional light with shadows) placed where the HDRI's brightest spot is,
/// - optionally floodlights on the six masts.
/// Files come from tools/sky/fetch_skies.sh (Poly Haven, CC0) and are copied in by a build phase.
/// Siri Remote while idle: swipe up/down to cycle presets. Launch arg: `-kr-sky <preset>`.
enum SkyPreset: String, CaseIterable, Identifiable {
    case midday, middayGradient, morning, golden, dusk, overcast, night
    var id: String { rawValue }

    var title: String {
        switch self {
        case .midday: "Midday"
        case .middayGradient: "Midday · plain gradient sky"
        case .morning: "Morning"
        case .golden: "Golden hour"
        case .dusk: "Dusk"
        case .overcast: "Overcast"
        case .night: "Night · floodlights"
        }
    }

    /// Bundle file stem (sky_<file>.hdr / .jpg).
    var file: String { self == .middayGradient ? "midday" : rawValue }

    struct Look {
        var sunLux: Float           // 0 = no directional sun (overcast)
        var iblExposure: Float      // ImageBasedLightComponent.intensityExponent
        var backdropTint: Float     // brightness of the visible panorama
        var yawDegrees: Float = 0   // turn the whole sky so the sun sits well against the arena
        var floodlights = false
        var gradient: (zenith: SIMD3<Float>, horizon: SIMD3<Float>)? = nil
    }

    var look: Look {
        switch self {
        case .midday:   Look(sunLux: 5000, iblExposure: 0.5, backdropTint: 1, yawDegrees: 40)
        case .middayGradient:
            Look(sunLux: 5000, iblExposure: 0.5, backdropTint: 1, yawDegrees: 40,
                 gradient: ([0.22, 0.45, 0.85], [0.75, 0.85, 0.95]))
        case .morning:  Look(sunLux: 4000, iblExposure: 0.4, backdropTint: 1, yawDegrees: 120)
        case .golden:   Look(sunLux: 3000, iblExposure: 0.3, backdropTint: 1, yawDegrees: 200)
        case .dusk:     Look(sunLux: 800, iblExposure: 0.2, backdropTint: 1, yawDegrees: 200)
        case .overcast: Look(sunLux: 0, iblExposure: 1.0, backdropTint: 1)
        case .night:    Look(sunLux: 0, iblExposure: -1.5, backdropTint: 0.8, floodlights: true)
        }
    }
}

@MainActor @Observable
final class SkyRig {
    var preset: SkyPreset = .midday {
        didSet { if preset != oldValue { announce(); Task { await apply() } } }
    }
    private(set) var banner: String?

    /// Add this to the scene; then call `addReceivers(to:)` on the scene root once loaded.
    @ObservationIgnored let root = Entity()
    @ObservationIgnored private let ibl = Entity()
    @ObservationIgnored private let dome: ModelEntity
    @ObservationIgnored private let sun = DirectionalLight()
    @ObservationIgnored private var floods: [SpotLight] = []
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var applied: SkyPreset?

    /// Floodlight heads (RealityKit coordinates, track centre at origin), from the six
    /// Lamps_n objects in the arena .blend (top at ~24.6 m).
    static let mastHeads: [SIMD3<Float>] = [
        (75.8, -42.0), (75.7, 53.6), (-90.5, 53.6), (-91.1, -42.0), (-6.0, -54.8), (-5.9, 53.7),
    ].map { bx, by in SIMD3<Float>(bx + 6.420, 24.0 - 0.538, -by - 4.002) }

    init() {
        dome = ModelEntity(mesh: Self.domeMesh(radius: 900), materials: [UnlitMaterial(color: .black)])
        root.addChild(dome)
        root.addChild(ibl)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 120, depthBias: 3)
        root.addChild(sun)
        for head in Self.mastHeads {
            let s = SpotLight()
            s.light.color = .init(red: 1, green: 0.96, blue: 0.9, alpha: 1)
            s.light.intensity = 0
            s.light.innerAngleInDegrees = 35
            s.light.outerAngleInDegrees = 65
            s.light.attenuationRadius = 260
            s.shadow = SpotLightComponent.Shadow()
            // Aim inwards and down, at the near side of the track rather than the centre spot.
            let target = SIMD3<Float>(head.x * 0.35, 0, head.z * 0.35)
            s.look(at: target, from: head, relativeTo: nil)
            floods.append(s)
            root.addChild(s)
        }
    }

    /// Every model in the scene lights from our HDRI rather than RealityKit's default.
    func addReceivers(to entity: Entity, inGrass: Bool = false) {
        let grass = inGrass || entity.name.lowercased().contains("grass")
        if var model = entity.components[ModelComponent.self], entity !== dome {
            entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
            // The arena's grass is far too glossy under a real sky (mirror-like sun glare).
            if grass {
                model.materials = model.materials.map { m in
                    guard var pbr = m as? PhysicallyBasedMaterial else { return m }
                    pbr.roughness = .init(floatLiteral: 0.95)
                    pbr.specular = .init(floatLiteral: 0.15)
                    return pbr
                }
                entity.components.set(model)
            }
        }
        for child in entity.children { addReceivers(to: child, inGrass: grass) }
    }

    /// Keep the dome centred on the camera so the sky never shows parallax.
    func follow(camera: Entity) { dome.position = camera.position(relativeTo: nil) }

    func next() { step(1) }
    func previous() { step(-1) }
    private func step(_ d: Int) {
        let all = SkyPreset.allCases
        preset = all[((all.firstIndex(of: preset) ?? 0) + d + all.count) % all.count]
    }

    private func announce() {
        banner = preset.title
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    func apply() async {
        let p = preset
        guard applied != p else { return }
        applied = p
        let look = p.look
        let yaw = simd_quatf(angle: look.yawDegrees * .pi / 180, axis: [0, 1, 0])

        // Load everything first, then swap in one go (a newer preset may arrive meanwhile).
        var sunDir = SIMD3<Float>(0.4, 0.8, 0.3)
        var sunColour = SIMD3<Float>(1, 1, 1)
        var env: EnvironmentResource?
        if let url = Bundle.main.url(forResource: "sky_\(p.file)", withExtension: "hdr"),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            if let peak = Self.brightestDirection(image) { sunDir = peak.direction; sunColour = peak.colour }
            env = try? await EnvironmentResource(equirectangular: image, withName: "sky_\(p.file)")
        } else {
            print("SkyRig: sky_\(p.file).hdr missing — run tools/sky/fetch_skies.sh")
        }
        var material = UnlitMaterial()
        if let g = look.gradient, let tex = try? await TextureResource(image: Self.gradientImage(g), options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(tex))
        } else if let url = Bundle.main.url(forResource: "sky_\(p.file)", withExtension: "jpg"),
                  let tex = await Self.loadBackdrop(url) {
            let t = CGFloat(look.backdropTint)
            material.color = .init(tint: .init(red: t, green: t, blue: t, alpha: 1), texture: .init(tex))
        }
        guard preset == p else { return }

        if let env {
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: look.iblExposure))
        }
        ibl.orientation = yaw
        dome.model?.materials = [material]
        dome.orientation = yaw

        // Sun: from the sky's brightest point, turned with the sky.
        let dir = yaw.act(sunDir)
        sun.light.intensity = look.sunLux
        sun.light.color = .init(red: CGFloat(sunColour.x), green: CGFloat(sunColour.y), blue: CGFloat(sunColour.z), alpha: 1)
        sun.isEnabled = look.sunLux > 0
        sun.look(at: .zero, from: dir * 100, relativeTo: nil)

        for f in floods { f.light.intensity = look.floodlights ? 25_000_000 : 0; f.isEnabled = look.floodlights }
        print("SkyRig: \(p.rawValue) sun dir \(dir) colour \(sunColour)")
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

    static func gradientImage(_ g: (zenith: SIMD3<Float>, horizon: SIMD3<Float>)) -> CGImage {
        let w = 4, h = 512
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let lat = 1 - Float(y) / Float(h - 1) * 2        // 1 top … -1 bottom
            let t = max(0, min(1, pow(max(lat, 0), 0.5)))
            let c = lat >= 0 ? g.horizon + (g.zenith - g.horizon) * t : g.horizon * 0.6
            for x in 0..<w {
                let i = (y * w + x) * 4
                px[i] = UInt8(c.x * 255); px[i + 1] = UInt8(c.y * 255); px[i + 2] = UInt8(c.z * 255)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
}
