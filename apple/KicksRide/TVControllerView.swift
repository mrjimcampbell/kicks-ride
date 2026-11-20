import SwiftUI
import KicksLink

/// TV test controller: switch the TV's look-dev variables from the phone instead of the remote.
/// The page mirrors whatever the TV reports (`tvStatus`), so remote presses on the TV show up
/// here too; each edit sends the whole settings set back (`tvSet`). Works in a run or idle.
struct TVControllerView: View {
    @Environment(LinkHost.self) private var link
    @State private var draft = TVSettings()
    /// While you're dragging a slider the TV's echo would make it jump: ignore status for a moment.
    @State private var editedAt = Date.distantPast
    @State private var wetnessEdited = false

    var body: some View {
        Group {
            if let status = link.tvStatus {
                form(status)
            } else {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(link.displayCount == 0 ? "Looking for Apple TV…" : "Connected, waiting for the TV…")
                        }
                        reconnectButton
                    } footer: {
                        Text(link.displayCount == 0
                             ? "Open Virtual Trainer (Unity) on the Apple TV, on the same Wi-Fi. If it doesn't appear within ~15 s, tap Reconnect."
                             : "Only the Unity TV app reports its settings; the RealityKit one has no test controls.")
                    }
                }
            }
        }
        .navigationTitle("TV controls")
        .onAppear { if let s = link.tvStatus { draft = s.settings } }
        .onChange(of: link.tvStatus) { _, s in
            guard let s, Date().timeIntervalSince(editedAt) > 1.5 else { return }
            draft = s.settings
        }
    }

    private func form(_ status: TVStatus) -> some View {
        Form {
            Section {
                LabeledContent("Frame rate", value: String(format: "%.0f fps", status.fps))
                Picker("Frame cap", selection: bind(\.frameRate)) {
                    ForEach(status.frameRates.sorted(), id: \.self) { Text("\($0) fps").tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("TV output", value: String(format: "%.0f Hz", status.refreshRate))
                Toggle("Show frame rate on TV", isOn: bind(\.showFPS))
                if !status.qualityLevels.isEmpty {
                    Picker("Quality", selection: bind(\.quality)) {
                        ForEach(status.qualityLevels, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("Render scale", selection: bind(\.renderScale)) {
                    Text("Tier default").tag(0.0)
                    ForEach([0.5, 0.67, 0.8, 1.0, 1.25, 1.5, 2.0], id: \.self) { v in
                        Text(v > 1 ? String(format: "%.2g× (supersample)", v) : String(format: "%.2g×", v)).tag(v)
                    }
                }
                if !status.resolution.isEmpty {
                    LabeledContent("Resolution", value: status.resolution)
                }
                reconnectButton
            } header: { Text(status.tvName) } footer: {
                Text("Low / High / Ultra: render scale, shadows (floodlight shadows from High), puddle mirror size, volumetric steps.")
            }

            devSections(status.devControls ?? [])

            Section {
                options("Ambient occlusion", status.ambientOcclusionModes, \.ambientOcclusion)
                options("Anti-aliasing", status.antiAliasingModes, \.antiAliasing)
            } header: { Text("Realism") } footer: {
                Text("Ambient occlusion darkens where things meet (feet, kerbs, under the stands). TAA is best on shimmer (fences, shadows) but can smear; MSAA cleans geometry edges only and costs most at 4K.")
            }

            Section("Lens") {
                Toggle("Lens dirt (shows in bloom)", isOn: bind(\.lensDirt))
                Toggle("Vignette", isOn: bind(\.vignette))
                Toggle("Film grain", isOn: bind(\.filmGrain))
                Toggle("Chromatic aberration", isOn: bind(\.chromaticAberration))
            }

            Section {
                Toggle("Show TV matching card", isOn: bind(\.calibration))
            } footer: {
                Text("Set both TVs to the same picture mode (Filmmaker/Movie), then adjust brightness until 2 % is just visible on black and contrast until 98–99 % still separate from white.")
            }

            Section("Scene") {
                options("Time of day", status.times, \.time)
                options("Weather", status.weathers, \.weather)
                options("Camera", status.cameras, \.camera)
            }

            Section {
                slider("Wetness", \.wetness, 0...1, format: { String(format: "%.0f %%", $0 * 100) })
                Toggle("Hold wetness", isOn: bind(\.holdWetness))
                slider("Volumetric light", \.volumetric, 0...3, format: { String(format: "× %.2f", $0) })
                slider("Fog", \.fog, 0...3, format: { String(format: "× %.2f", $0) })
                Button("Reset multipliers") {
                    draft.volumetric = 1; draft.fog = 1; push()
                }
            } header: { Text("Atmosphere") } footer: {
                Text("Puddles grow while it rains and dry out afterwards unless held. Multipliers scale the mood's own values (× 1 = as designed).")
            }

            Section {
                Toggle("Screensaver run", isOn: bind(\.screensaver))
                    .disabled(status.running)
                slider("Speed", \.screensaverSpeed, 0...22, step: 0.5,
                       format: { $0 == 0 ? "Programme" : String(format: "%.1f km/h", $0) })
                    .disabled(status.running)
            } header: { Text("Runner") } footer: {
                Text(status.running ? "A run is showing: the runner follows the treadmill."
                     : "Speed 0 = the demo programme of changing speeds.")
            }
        }
        .monospacedDigit()
    }

    // MARK: - Dev dashboard (controls defined by the TV)

    /// One section per group, in the order the TV registered them.
    @ViewBuilder private func devSections(_ controls: [DevControl]) -> some View {
        let groups = controls.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        ForEach(groups, id: \.self) { group in
            let items = controls.filter { $0.group == group }
            Section {
                ForEach(items) { devControl($0) }
            } header: { Text(group) } footer: {
                let notes = items.map(\.note).filter { !$0.isEmpty }
                if !notes.isEmpty { Text(notes.joined(separator: " ")) }
            }
        }
    }

    @ViewBuilder private func devControl(_ c: DevControl) -> some View {
        switch c.kind {
        case "choice":
            Picker(c.label, selection: devBind(c.key, c.value)) {
                ForEach(c.options, id: \.self) { Text($0).tag($0) }
            }
        case "toggle":
            Toggle(c.label, isOn: Binding(
                get: { devValue(c.key, c.value) == "true" },
                set: { setDev(c.key, $0 ? "true" : "false") }))
        default:
            let v = Binding<Double>(
                get: { Double(devValue(c.key, c.value)) ?? c.min },
                set: { setDev(c.key, String(format: "%g", $0)) })
            VStack(alignment: .leading) {
                LabeledContent(c.label, value: String(format: c.step < 1 ? "%.2f" : "%.0f", v.wrappedValue))
                Slider(value: v, in: c.min...max(c.max, c.min + 0.001), step: c.step > 0 ? c.step : 0.01)
            }
        }
    }

    private func devValue(_ key: String, _ fallback: String) -> String {
        draft.dev?.first { $0.key == key }?.value ?? fallback
    }

    private func devBind(_ key: String, _ fallback: String) -> Binding<String> {
        Binding(get: { devValue(key, fallback) }, set: { setDev(key, $0) })
    }

    private func setDev(_ key: String, _ value: String) {
        guard devValue(key, "\u{0}") != value else { return }
        var dev = draft.dev ?? []
        if let i = dev.firstIndex(where: { $0.key == key }) { dev[i].value = value } else { dev.append(DevValue(key: key, value: value)) }
        draft.dev = dev
        push()
    }

    // MARK: - Controls

    /// Drops the TV link and advertises the phone afresh; the TV re-finds it within a few seconds.
    private var reconnectButton: some View {
        Button {
            link.reconnect()
        } label: {
            Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func options(_ title: String, _ values: [String], _ key: WritableKeyPath<TVSettings, String>) -> some View {
        Picker(title, selection: bind(key)) {
            ForEach(values, id: \.self) { Text($0).tag($0) }
        }
    }

    private func slider(_ title: String, _ key: WritableKeyPath<TVSettings, Double>, _ range: ClosedRange<Double>,
                        step: Double = 0.05, format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: format(draft[keyPath: key]))
            Slider(value: bind(key), in: range, step: step)
        }
    }

    private func bind<T: Equatable>(_ key: WritableKeyPath<TVSettings, T>) -> Binding<T> {
        Binding(
            get: { draft[keyPath: key] },
            set: { v in
                guard draft[keyPath: key] != v else { return }
                draft[keyPath: key] = v
                if (key as AnyKeyPath) == (\TVSettings.wetness as AnyKeyPath) { wetnessEdited = true }
                push()
            })
    }

    private func push() {
        editedAt = Date()
        var out = draft
        if !wetnessEdited { out.wetness = -1 }     // wetness drifts on the TV: only send it when moved
        wetnessEdited = false
        link.sendToTVs(.tvSet(out))
    }
}
