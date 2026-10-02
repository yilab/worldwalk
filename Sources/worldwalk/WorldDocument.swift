// One loaded .world package, folded — the document behind the app.
//
// The fold is the app's engine: load, fold at a tip, expose the
// summary and the scene. No format semantics live here.

import Foundation
import Observation
import OpenWorldFormat

@MainActor
@Observable
final class WorldDocument {
    var world: WorldPackage?
    var folded: FoldState?
    var selectedTip: String?
    var tips: [String] = []
    var stateValues: [String: JSONValue] = [:]
    var undeclaredKeys: [String] = []
    var errorText: String?

    /// Bumped on every successful fold — the view rebuilds the scene
    /// when it changes.
    var foldGeneration = 0

    var worldName: String { world?.manifest.name ?? folded?.name ?? "" }

    /// Load a package folder and fold it at its default tip (the last
    /// entry in file order).
    func load(url: URL) {
        do {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let package = try WorldPackage(directory: url)
            world = package
            tips = try package.history().tips
            selectedTip = nil  // default tip: last in file order
            refold()
            errorText = nil
        } catch {
            errorText = "\(error.localizedDescription)"
        }
    }

    /// Fold at the selected tip (nil = the default).
    func refold() {
        guard let world else { return }
        do {
            let state = try foldPath(world.manifest, world.entries, tip: selectedTip)
            folded = state
            let chain = state.path?.compactMap { id in
                world.entries.first { $0.id == id }
            } ?? world.entries
            let result = foldState(world.stateDocument, chain)
            stateValues = result.values
            undeclaredKeys = result.undeclared
            foldGeneration += 1
        } catch {
            errorText = "\(error.localizedDescription)"
        }
    }
}
