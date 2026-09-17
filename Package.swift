// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AuthMock",
    platforms: [
        .macOS(.v13), .iOS(.v16)
    ],
    products: [
        .library(name: "AuthMockServer", targets: ["AuthMockServer"]),
        .executable(name: "AuthMock", targets: ["AuthMock"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "AuthMockServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            resources: [.copy("Fixtures")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .executableTarget(
            name: "AuthMock",
            dependencies: [
                "AuthMockServer"
            ],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(
            name: "AuthMockTests",
            dependencies: [
                .target(name: "AuthMockServer"),
                .target(name: "AuthMock"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
