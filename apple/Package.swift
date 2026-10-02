// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "worldwalk",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
    ],
    dependencies: [
        // Path dep until the first bare semver tag (v0.1.0) is cut;
        // then flip to the URL form, the way worldprobe flips to
        // crates.io.
        .package(path: "../../openworldformat"),
    ],
    targets: [
        .executableTarget(
            name: "worldwalk",
            dependencies: [
                .product(name: "OpenWorldFormat", package: "openworldformat"),
            ]
        ),
    ]
)
