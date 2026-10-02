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
/// manifest's environment declares.
struct Worldport: View {
    @Environment(WorldDocument.self) private var document

    var body: some View {
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
            }
            .ignoresSafeArea()
        }
        .id(document.foldGeneration)  // a new fold is a new scene
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

    private static func icon(_ entity: WorldEntity) -> String {
        if entity.light != nil { return "sun.max" }
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
