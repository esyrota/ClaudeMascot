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
            // Info.plist and AppIcon.icns are copied into the bundle by make-app.sh,
            // not by SwiftPM. Excluding them silences the "unhandled file" warning.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
            resources: [.copy("Resources/Animations")]
        ),
        .testTarget(
            name: "ClaudeMascotTests",
            dependencies: ["ClaudeMascot"]
        )
    ]
)
