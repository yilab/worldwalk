# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

worldwalk — the Open World Format's viewer: walk a `.world`. One
product, two platform trees — `apple/` (SwiftUI + RealityKit, one
codebase for macOS/iOS/iPadOS/visionOS) and `android/` (Compose). The
fold is the engine: `apple/` rides the spec repo's Swift package
(manifest at that repo's root, sources in `swift/`) by its bare semver
tags — `from: "0.3.5"`; swap in `.package(path: "../../openworldformat")`
to work against the sibling checkout — and `android/` rides its Kotlin
package through a Gradle composite build
(`includeBuild("../../openworldformat/kotlin")`), which substitutes the
`org.openworldformat:openworldformat` coordinates with local sources
until that package publishes to Maven Central. Flip it to a versioned
dep the day it publishes.

## Rules

- No format semantics in this repo: parsing, folding, history and
  state belong to the spec repo's reference packages. worldwalk loads
  a package folder and draws what the fold says. If a format behavior
  is missing, fix it upstream, not here.
- `android/app/src/main/assets/hello-world/` is the spec repo's
  `examples/hello-world`, copied. Refresh it from there when the
  example changes; never edit it here.
- The Android renderer is a dependency-free painter's-algorithm canvas
  (see `WorldRenderer.kt`); Filament/SceneView is the upgrade path
  when the viewer needs real PBR. The Apple renderer is RealityKit.
  Neither owns format decisions — shapes and materials read exactly as
  the document declares them.
- AGP 9 ships built-in Kotlin: no `org.jetbrains.kotlin.android`
  plugin in `android/` (it conflicts); only
  `org.jetbrains.kotlin.plugin.compose`. The spec repo's `kotlin/`
  package uses the KMP library plugin instead — different animals.
- `apple/worldwalk.xcodeproj` (scheme `worldwalk`) is the app —
  macOS/iOS/iPadOS/visionOS from one target whose synchronized group
  is `Sources/worldwalk/`, so the Xcode target and the SwiftPM
  executable compile the same files (`Assets.xcassets` lives there
  too; SPM excludes it). The fold comes in as a remote package
  reference to the spec repo, the same `0.3.5` floor as Package.swift
  — keep the two in step. Always open the .xcodeproj,
  never the `apple/` folder (that opens as the SwiftPM package).
- Conventional commits, no Co-Authored-By trailers. Green before
  reporting completion: `swift build` in `apple/`,
  `xcodebuild -project apple/worldwalk.xcodeproj -scheme worldwalk
  -destination 'platform=macOS' build` (swap in an iOS Simulator
  destination for the iPhone/iPad check),
  `./gradlew :app:assembleDebug :app:testDebugUnitTest` in `android/`.
- CI (when the org repo exists): two workflows with path filters —
  macOS for `apple/**`, ubuntu for `android/**` (ANDROID_HOME is on
  the runner image).
- License: Apache-2.0.
