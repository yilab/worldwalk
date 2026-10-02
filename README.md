# worldwalk

**Walk a `.world`.** The Open World Format's viewer for Apple
platforms: open a package folder, fold it, step in. One SwiftUI +
RealityKit codebase for macOS, iOS, iPadOS and visionOS.

The fold is the engine — [the format's Swift package][owf-swift]
parses the manifest, folds the session log, resolves the branch, and
this app draws exactly what the fold says, adding no format semantics
of its own. The sidebar shows the receipts: entity count, edits
applied, the branch tips, the state values at the folded tip.

[owf-swift]: https://github.com/openworldformat/openworldformat/tree/main/swift

## Run

The Apple app lives in [`apple/`](apple/) (SwiftUI + RealityKit, one
codebase for macOS, iOS, iPadOS and visionOS); the Android app lives
in [`android/`](android/) (Compose, riding the format's Kotlin package
through a Gradle composite build). One product, one repo, two platform
trees.

```bash
# Android (needs the Android SDK; bundles the hello-world demo world)
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The Android app opens straight into the bundled demo world (a copy of
the spec repo's `examples/hello-world`); Open… picks any `.world`
folder through the system folder picker. Its v0 renderer is a
dependency-free painter's-algorithm canvas — perspective projection,
lambert shading from the fold's own directional light, orbit by drag —
with Filament/SceneView as the upgrade path. Both platforms show the
same receipts the fold produces: entity count, edits applied, branch
tips, state values.

```bash
# From this checkout, next to the openworldformat clone:
cd apple
swift run worldwalk ../../openworldformat/examples/hello-world
swift run worldwalk /path/to/any/.world/folder
```

Or open `apple/Package.swift` in Xcode and run on a Mac, an
iPhone/iPad simulator, or a Vision Pro simulator — the app is a
SwiftPM executable, no project file. Without an argument it opens
empty: use *File → Open World…* (⌘O) and pick a `.world` folder.

The dependency is a path dep to `../../openworldformat` (whose package
manifest is at the repo root, targeting `swift/`) until the spec
repository cuts its first bare semver tag; then it flips to the URL
form, the way [worldprobe][probe] flips to crates.io.

[probe]: https://github.com/openworldformat/worldprobe

## What it draws (v0)

- **All eleven parametric shapes** — cuboid, sphere, cylinder, cone,
  capsule, torus, plane, pyramid, tetrahedron, icosahedron, wedge.
  RealityKit generates six of them; capsule, torus, pyramid,
  tetrahedron, icosahedron and wedge are built by hand (lathe meshes
  and flat-shaded polyhedra, winding auto-corrected).
- **Materials** — PBR base color, roughness, metallic, emissive.
- **Lights** — directional (lux), point (lumens), spot, with the
  environment's ambient approximated by two soft fills.
- **Hierarchy and transforms** — parenting, position, rotation
  (Euler XYZ degrees), scale, visibility.
- **Instances** — `instance_of` resolves against the manifest's
  `creations`, parts parented, per-part `overrides` patched with the
  fold's own patch semantics (absent = unchanged, null = clear,
  value = set).
- **Branches** — a log with tips gets a branch picker; picking one
  re-folds to that tip. The viewer is the history.
- **State** — the typed state document folds per branch and shows in
  the sidebar, the way a save game would.

## What it doesn't (yet) — the viewer profile's must-ignore

The manifest camera (the default RealityKit camera orbits the
content), textures (`base_color_texture` needs the package's asset
store), double-sided planes, audio and the soundtrack, tours,
behaviors and triggers, `ext-*` components (physics is a static view
here). Each of those is a to-do, not a refusal — this is a v0
scaffold that proves the pipeline: *package → fold → RealityKit*.

## Repository

Part of the [Open World Format](https://openworldformat.org) family:
`openworldformat` (the spec), `worldprobe` (the inspector),
`worldwalk` (this viewer). Apache-2.0.
