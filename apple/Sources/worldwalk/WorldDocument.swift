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

    /// The shot the viewport looks through (an `ext-cinematography`
    /// camera entity's name), or nil for the free camera.
    var selectedShot: String?

    /// Bumped on every successful fold — the view rebuilds the scene
    /// when it changes.
    var foldGeneration = 0

    var worldName: String { world?.manifest.name ?? folded?.name ?? "" }

    /// The fold's shot list (`ext-cinematography`): the cameras carrying
    /// a shot, in order — read through the package, never derived here.
    var shots: [ShotEntry] {
        folded.map { shotList($0.entities) } ?? []
    }

    /// The selected shot's camera entity and component, when both exist
    /// in the fold on screen.
    var selectedCamera: (entity: WorldEntity, camera: OpenWorldFormat.CameraComponent)? {
        guard let folded, let shot = selectedShot,
              let entity = folded.entities.first(where: { $0.name == shot }),
              let camera = OpenWorldFormat.CameraComponent.of(entity) else { return nil }
        return (entity, camera)
    }

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
            selectedShot = nil
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
            // A shot that this tip doesn't hold falls back to the free camera.
            if let shot = selectedShot, !state.entities.contains(where: { $0.name == shot }) {
                selectedShot = nil
            }
            foldGeneration += 1
        } catch {
            errorText = "\(error.localizedDescription)"
        }
    }
}
