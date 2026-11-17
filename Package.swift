// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsteraDMXMidiBridge",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AsteraDMXMidiBridge", targets: ["AsteraDMXMidiBridge"])],
    targets: [
        .target(name: "AX1Core"),
        .target(name: "AX1FTDI", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "AsteraDMXMidiBridge", dependencies: ["AX1Core", "AX1FTDI"]),
        .testTarget(name: "AX1CoreTests", dependencies: ["AX1Core"])
    ]
)
