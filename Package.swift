// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ClaudeMascot",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ClaudeMascot", targets: ["ClaudeMascot"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMascot",
            dependencies: [],
            // Info.plist is copied into the bundle by make-app.sh, not by SwiftPM.
            // Excluding it silences the "unhandled file" build warning.
            exclude: ["Resources/Info.plist"],
            resources: [.copy("Resources/Animations")]
        ),
        .testTarget(
            name: "ClaudeMascotTests",
            dependencies: ["ClaudeMascot"]
        )
    ]
)
