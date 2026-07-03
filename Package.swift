// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marcus",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Preview/export parser (ROADMAP D5). Never touched on the editing path.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .target(name: "MarcusCore"),
        .target(
            name: "MarcusPreview",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .executableTarget(
            name: "Marcus",
            dependencies: ["MarcusCore", "MarcusPreview"],
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
        .testTarget(name: "MarcusPreviewTests", dependencies: ["MarcusPreview"]),
    ]
)
