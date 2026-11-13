import SwiftUI
import KicksCore
import KicksFTMS
import KicksLink

/// iPhone app — the brain. Owns the treadmill connection, workouts, recording and Strava,
/// and broadcasts live state to any Apple TVs on the network. Must work fully on its own (no TV).
@main
struct KicksRideApp: App {
    @State private var hub = BluetoothHub()
    @State private var link = LinkHost()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(hub)
                .environment(link)
                .task {
                    link.start()
                    link.send(.idle)
                }
        }
    }
}

/// Settings that persist on the phone.
enum Prefs {
    static let inclineMode = "kr.inclineMode"      // InclineMode raw value
    static let inclineFixed = "kr.inclineFixed"    // %
    static let hudSize = "kr.hudSize"              // HUDSize raw value
    static let weightKg = "kr.weightKg"
    static let ftp = "kr.ftp"
    static let route = "kr.route"
}

enum InclineMode: String, CaseIterable, Identifiable {
    case off, fixed
    var id: String { rawValue }
    var label: String { self == .off ? "Off (never touch incline)" : "Fixed" }
}

enum HUDSize: String, CaseIterable, Identifiable {
    case normal, large, extraLarge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: "Normal"
        case .large: "Large"
        case .extraLarge: "Extra large"
        }
    }
    var scale: CGFloat {
        switch self {
        case .normal: 1
        case .large: 1.25
        case .extraLarge: 1.5
        }
    }
}

struct Route: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    static let all = [Route(id: "track400", name: "Athletics track", detail: "400 m, lane 1")]
}

// MARK: - Home

enum Screen: String, Hashable { case devices, route, preferences, tv }

struct HomeView: View {
    @Environment(BluetoothHub.self) private var hub
    @Environment(LinkHost.self) private var link
    @AppStorage(Prefs.route) private var routeID = Route.all[0].id
    @State private var running = false
    @State private var path: [Screen] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Screen.devices) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Devices").font(.headline)
                            ForEach(DeviceSlot.allCases) { slot in
                                DeviceSummary(slot: slot)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    NavigationLink(value: Screen.route) {
                        LabeledContent("Route", value: Route.all.first { $0.id == routeID }?.name ?? "—")
                    }
                    NavigationLink(value: Screen.preferences) {
                        Text("Preferences")
                    }
                    NavigationLink(value: Screen.tv) {
                        LabeledContent("Apple TV", value: link.displayCount == 0 ? "Not connected"
                                       : link.displayCount == 1 ? "Connected" : "\(link.displayCount) connected")
                    }
                }

                Section {
                    Button {
                        running = true
                    } label: {
                        Text("Start run")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    if hub.machine == nil {
                        Text("No treadmill connected: the run will be timed but distance won't move.")
                    } else if hub.live.machineKind == .treadmill {
                        Text("Start the belt on the treadmill. The app never starts it.")
                    }
                }
            }
            .navigationTitle(AppInfo.name)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .devices: DevicesView()
                case .route: RouteView()
                case .preferences: PreferencesView()
                case .tv: TVControllerView()
                }
            }
            .fullScreenCover(isPresented: $running) { RunView() }
            .onAppear(perform: openFromLaunchArguments)
        }
    }

    /// Debug/screenshot hook: launch with `-kr-screen devices|route|preferences|tv|run`.
    private func openFromLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-kr-screen"), i + 1 < args.count else { return }
        if args[i + 1] == "run" { running = true } else if let s = Screen(rawValue: args[i + 1]) { path = [s] }
    }
}

struct DeviceSummary: View {
    @Environment(BluetoothHub.self) private var hub
    let slot: DeviceSlot

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(hub.names[slot] ?? "No \(slot.title.lowercased())")
                .foregroundStyle(hub.names[slot] == nil ? .secondary : .primary)
            Spacer()
            if hub.names[slot] != nil { Text(hub.state(of: slot).label).foregroundStyle(.secondary) }
        }
        .font(.subheadline)
    }

    private var colour: Color {
        switch hub.state(of: slot) {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .gray.opacity(0.4)
        }
    }
}

// MARK: - Route & preferences

struct RouteView: View {
    @AppStorage(Prefs.route) private var routeID = Route.all[0].id

    var body: some View {
        List(Route.all) { route in
            Button {
                routeID = route.id
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(route.name).foregroundStyle(.primary)
                        Text(route.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if route.id == routeID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
        }
        .navigationTitle("Route")
    }
}

struct PreferencesView: View {
    @AppStorage(Prefs.inclineMode) private var inclineMode = InclineMode.off.rawValue
    @AppStorage(Prefs.inclineFixed) private var inclineFixed = 1.0
    @AppStorage(Prefs.hudSize) private var hudSize = HUDSize.large.rawValue
    @AppStorage(Prefs.weightKg) private var weightKg = 69.0
    @AppStorage(Prefs.ftp) private var ftp = 200

    var body: some View {
        Form {
            Section {
                Picker("Incline", selection: $inclineMode) {
                    ForEach(InclineMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if inclineMode == InclineMode.fixed.rawValue {
                    Stepper(value: $inclineFixed, in: 0...15, step: 0.5) {
                        LabeledContent("Fixed incline", value: String(format: "%.1f %%", inclineFixed))
                    }
                }
            } header: { Text("Treadmill") } footer: {
                Text("The track is flat, so incline is Off or a fixed value. Off never sends incline commands, workouts included.")
            }
            Section("Display") {
                Picker("HUD text size", selection: $hudSize) {
                    ForEach(HUDSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("You") {
                Stepper(value: $weightKg, in: 30...150, step: 0.5) {
                    LabeledContent("Weight", value: String(format: "%.1f kg", weightKg))
                }
                Stepper(value: $ftp, in: 50...500, step: 5) {
                    LabeledContent("FTP (bike)", value: "\(ftp) W")
                }
            }
        }
        .navigationTitle("Preferences")
    }
}

/// The app's shown name comes from CFBundleDisplayName in project.yml — rename it there only.
enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Trainer"
}
