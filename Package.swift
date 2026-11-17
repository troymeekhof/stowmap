// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stowmap",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Stowmap",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Stowmap",
            linkerSettings: [
                // Sparkle.framework is embedded in Stowmap.app/Contents/Frameworks by build.sh
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
