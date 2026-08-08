// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuietPaper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuietPaper", targets: ["QuietPaper"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/mysql-kit.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/postgres-kit.git", from: "2.9.1"),
        .package(url: "https://github.com/swift-server/RediStack.git", from: "1.6.3"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "QuietPaper",
            dependencies: [
                "CSQLite",
                .product(name: "MySQLKit", package: "mysql-kit"),
                .product(name: "PostgresKit", package: "postgres-kit"),
                .product(name: "RediStack", package: "RediStack"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "Sources/QuietPaper",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        )
    ]
)
