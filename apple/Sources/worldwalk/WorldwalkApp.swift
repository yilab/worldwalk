// Worldwalk — walk a .world.
//
// The Open World Format's Apple viewer: open a package folder, fold
// it, step in. The fold (through the OpenWorldFormat package) is the
// engine; RealityKit draws what it says; the sidebar shows the
// receipts — branches, edits, state. SwiftUI throughout, one codebase
// for macOS, iOS, iPadOS and visionOS.

import SwiftUI
import RealityKit
import UniformTypeIdentifiers
import OpenWorldFormat

@main
struct WorldwalkApp: App {
    @State private var document = WorldDocument()

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(document)
                .frame(minWidth: 900, minHeight: 600)
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open World…") { NotificationCenter.postOpenWorld() }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// File > Open routed through a notification — the button lives in
/// several places (welcome view, toolbar), and they all funnel here.
extension Notification.Name {
    static let worldwalkOpen = Notification.Name("worldwalk.open")
}

extension NotificationCenter {
    static func postOpenWorld() {
        NotificationCenter.default.post(name: .worldwalkOpen, object: nil)
    }
}

struct ContentView: View {
    @Environment(WorldDocument.self) private var document
    @State private var isPresentingOpen = false
    @State private var loadedLaunchArgument = false

    var body: some View {
        @Bindable var document = document
        Group {
            if let folded = document.folded, let world = document.world {
                main(folded: folded, world: world)
            } else {
                welcome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isPresentingOpen,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                document.load(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .worldwalkOpen)) { _ in
            isPresentingOpen = true
        }
        .onAppear {
            guard !loadedLaunchArgument else { return }
            loadedLaunchArgument = true
            let args = CommandLine.arguments.dropFirst()
            if let path = args.first(where: { !$0.hasPrefix("-") }) {
                document.load(url: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - The world view

    private func main(folded: FoldState, world: WorldPackage) -> some View {
        NavigationSplitView {
            Sidebar(folded: folded, world: world)
        } detail: {
            Worldport()
                .navigationTitle(document.worldName)
                .toolbar {
                    if document.tips.count > 1 {
                        ToolbarItem(placement: .primaryAction) {
                            Picker("Branch", selection: Binding(
                                get: { document.selectedTip ?? document.tips.last ?? "" },
                                set: { document.selectedTip = $0; document.refold() }
                            )) {
                                ForEach(document.tips, id: \.self) { tip in
                                    Text("tip \(tip)").tag(tip)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    if !document.shots.isEmpty {
                        // Look through a shot (ext-cinematography): the
                        // fold's shot list, as the package orders it.
                        ToolbarItem(placement: .primaryAction) {
                            Picker("Shot", selection: Binding(
                                get: { document.selectedShot ?? "" },
                                set: { document.selectedShot = $0.isEmpty ? nil : $0 }
                            )) {
                                Text("Free camera").tag("")
                                ForEach(document.shots, id: \.id) { shot in
                                    Text(shot.name).tag(shot.name)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open…") { isPresentingOpen = true }
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    // MARK: - The welcome view

    private var welcome: some View {
        VStack(spacing: 24) {
            Image(systemName: "globe.americas")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Worldwalk")
                .font(.largeTitle.bold())
            Text("Walk a `.world`.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Open a World…") { isPresentingOpen = true }
                .buttonStyle(.borderedProminent)
            if let error = document.errorText {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            Text("""
                A `.world` is a folder: `manifest.json`, an optional \
                `ops.jsonl` session log, an optional `state.json`. The \
                conformance worlds and examples live in the format's \
                repository — open one and step in.
                """)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - The viewport

/// RealityKit draws the fold; the background color is the one the
/// manifest's environment declares. A selected shot (ext-cinematography)
/// puts a camera at that setup's view, letterboxed to its frame.
struct Worldport: View {
    @Environment(WorldDocument.self) private var document

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let frame = document.selectedCamera.map { frameOf($0.camera) }
            ZStack {
                if let rgb = document.folded?.environment?.backgroundColor,
                   rgb.count >= 3 {
                    Color(red: rgb[0], green: rgb[1], blue: rgb[2])
                        .ignoresSafeArea()
                }
                RealityView { content in
                    if let folded = document.folded,
                       let world = document.world,
                       let scene = try? SceneBuilder.makeRoot(from: folded, manifest: world.manifest) {
                        content.add(scene.root)
                    }
                    Self.syncShotCamera(&content, document: document, size: size)
                } update: { content in
                    Self.syncShotCamera(&content, document: document, size: size)
                }
                .ignoresSafeArea()
                if let frame {
                    Letterbox(aspect: frame.aspect, size: size)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .id(document.foldGeneration)  // a new fold is a new scene
    }

    /// The scene's shot camera follows the selection: placed (or
    /// replaced) when a shot is selected, removed for the free camera.
    /// Its vertical field of view is widened when the window is taller
    /// than the frame, so the letterboxed band still shows exactly the
    /// frame's field of view.
    @MainActor
    private static func syncShotCamera<Content: RealityViewContentProtocol>(
        _ content: inout Content, document: WorldDocument, size: CGSize
    ) {
        #if !os(visionOS)
        if let existing = content.entities.first(where: { $0.name == "shot-camera" }) {
            content.remove(existing)
        }
        guard let folded = document.folded, let selected = document.selectedCamera else { return }
        let built = SceneBuilder.shotCamera(selected.entity, selected.camera, in: folded)
        built.camera.camera.fieldOfViewInDegrees = Float(Letterbox.viewFov(frame: built.frame, size: size))
        content.add(built.camera)
        #endif
    }
}

/// The bars that letterbox a shot's frame into the window: side bars
/// when the window is wider than the frame, top and bottom bars when it
/// is taller — the largest centred rectangle of the frame's aspect, the
/// way the format's web renderer letterboxes its canvas.
struct Letterbox: View {
    let aspect: Double
    let size: CGSize

    var body: some View {
        let (w, h) = (size.width, size.height)
        let frameWidth = min(w, h * aspect)
        let frameHeight = min(h, w / aspect)
        let sideBar = max(0, (w - frameWidth) / 2)
        let topBar = max(0, (h - frameHeight) / 2)
        ZStack {
            HStack(spacing: 0) {
                Color.black.frame(width: sideBar)
                Spacer(minLength: 0)
                Color.black.frame(width: sideBar)
            }
            VStack(spacing: 0) {
                Color.black.frame(height: topBar)
                Spacer(minLength: 0)
                Color.black.frame(height: topBar)
            }
        }
    }

    /// The vertical field of view the window's camera needs so that the
    /// letterboxed frame shows the shot's `vfov`: the frame's own when
    /// the window is wider than the frame (the frame fills the height),
    /// wider by the ratio of window to frame height otherwise.
    static func viewFov(frame: CameraFrame, size: CGSize) -> Double {
        let (w, h) = (Double(size.width), Double(size.height))
        guard w > 0, h > 0, w / h < frame.aspect else { return frame.vfovDegrees }
        let frameHeight = w / frame.aspect
        let half = tan(frame.vfovDegrees / 2 * .pi / 180) * h / frameHeight
        return 2 * atan(half) * 180 / .pi
    }
}

// MARK: - The sidebar: the receipts

/// The fold, itemized — the world, its branches, its state, its
/// entities. A viewer that shows its work.
struct Sidebar: View {
    let folded: FoldState
    let world: WorldPackage

    var body: some View {
        List {
            Section("World") {
                row("name", folded.name)
                row("entities", "\(folded.entities.count)")
                row("edits applied", "\(folded.appliedEdits)")
                row("log entries", "\(world.entries.count)")
            }
            if documentTips.count > 1 {
                Section("Branches") {
                    ForEach(documentTips, id: \.self) { tip in
                        Label(tip, systemImage:
                                tip == (folded.path?.last ?? "") ? "arrow.right.circle.fill" : "arrow.turn.branch")
                    }
                }
            }
            if !document.shots.isEmpty {
                // The shot list (ext-cinematography): name, lens, size —
                // the numbers a board carries; select one to look through it.
                Section("Shots") {
                    ForEach(document.shots, id: \.id) { shot in
                        Button {
                            document.selectedShot = document.selectedShot == shot.name ? nil : shot.name
                        } label: {
                            Label {
                                HStack {
                                    Text(shot.name).font(.body.monospaced())
                                    Spacer()
                                    Text(Self.lens(shot, in: folded))
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: document.selectedShot == shot.name ? "camera.fill" : "camera")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !folded.audioEmitters.isEmpty {
                Section("Audio emitters") {
                    ForEach(folded.audioEmitters.keys.sorted(), id: \.self) { name in
                        Label(name, systemImage: "speaker.wave.2")
                    }
                }
            }
            if !documentValues.isEmpty {
                Section("State") {
                    ForEach(documentValues.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.body.monospaced())
                            Spacer()
                            Text(Self.render(documentValues[key] ?? .null))
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Entities") {
                ForEach(folded.entities, id: \.id) { entity in
                    Label {
                        Text(entity.name)
                    } icon: {
                        Image(systemName: Self.icon(entity))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @Environment(WorldDocument.self) private var document
    private var documentTips: [String] { document.tips }
    private var documentValues: [String: JSONValue] { document.stateValues }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    /// A shot's lens and size, as the package reads them: "50 mm · MCU".
    private static func lens(_ shot: ShotEntry, in folded: FoldState) -> String {
        let camera = folded.entities.first { $0.id == shot.id }
            .flatMap(OpenWorldFormat.CameraComponent.of)
        var parts: [String] = []
        if let camera { parts.append("\(Self.render(.number(camera.focalLengthMm))) mm") }
        if let size = shot.shot["size"]?.string { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    private static func icon(_ entity: WorldEntity) -> String {
        if entity.light != nil { return "sun.max" }
        if OpenWorldFormat.CameraComponent.of(entity) != nil { return "camera" }
        if entity.fields["instance_of"] != nil { return "square.on.square" }
        if entity.parent != nil { return "arrow.down.right" }
        return "cube"
    }

    /// State values as compact literals.
    nonisolated static func render(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15
                ? String(Int(n)) : String(format: "%.3g", n)
        case .string(let s): return "\"\(s)\""
        case .array(let a): return "[\(a.map(render).joined(separator: ", "))]"
        case .object(let o):
            return "{\(o.sorted { $0.key < $1.key }.map { "\($0.key): \(render($0.value))" }.joined(separator: ", ")))}"
        }
    }
}
