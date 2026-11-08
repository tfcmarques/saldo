// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Saldo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Saldo", targets: ["Saldo"])
    ],
    targets: [
        .executableTarget(
            name: "Saldo",
            resources: [.copy("Resources/AppIcon.png")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
