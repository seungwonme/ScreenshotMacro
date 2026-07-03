// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "smacro",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SMacroCore", path: "Sources/SMacroCore"),
        .executableTarget(
            name: "smacro-proto", dependencies: ["SMacroCore"], path: "Sources/smacro-proto"),
        .executableTarget(
            name: "smacro-gui", dependencies: ["SMacroCore"], path: "Sources/smacro-gui"),
    ]
)
