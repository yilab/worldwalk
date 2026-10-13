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
        // The spec repo's Swift package, released on bare semver tags
        // (v0.3.5 on). To work against the sibling checkout instead,
        // swap in `.package(path: "../../openworldformat")` locally.
        .package(url: "https://github.com/openworldformat/openworldformat", from: "0.3.5"),
    ],
    targets: [
        .executableTarget(
            name: "worldwalk",
            dependencies: [
                .product(name: "OpenWorldFormat", package: "openworldformat"),
            ],
            // The app icon/catalog lives with the sources so the Xcode
            // project's synchronized group picks it up as a resource;
            // SwiftPM has no use for it.
            exclude: ["Assets.xcassets"]
        ),
    ]
)
