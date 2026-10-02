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
        // Path dep until the spec repo publishes its first Swift tag;
        // then flip to the URL, the way worldprobe flips to crates.io.
        .package(path: "../openworldformat/swift"),
    ],
    targets: [
        .executableTarget(
            name: "worldwalk",
            dependencies: [
                // "swift" is the path dependency's identity (SwiftPM
                // names local packages by their directory); it becomes
                // "openworldformat" when this flips to the URL form.
                .product(name: "OpenWorldFormat", package: "swift"),
            ]
        ),
    ]
)
