// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marcus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MarcusCore"),
        .executableTarget(
            name: "Marcus",
            dependencies: ["MarcusCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embeds Info.plist into the binary so NSDocument's type system
                // works when running the bare executable (swift run / .build).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Marcus/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "MarcusCoreTests", dependencies: ["MarcusCore"]),
    ]
)
