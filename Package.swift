// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AuthMock",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "AuthMock",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(
            name: "AuthMockTests",
            dependencies: [
                .target(name: "AuthMock"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
