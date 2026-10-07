// swift-tools-version: 5.10
// BedoonZahmaKit — كل منطق المنتج خارج هدف التطبيق، بلا اعتماد على Google SDKs
// حتى يُختبر على أي منصة (macOS/Linux/Windows) ويبقى قابلاً لتبديل المزوّد.
//
// الأهداف المعتمدة على SwiftUI/CoreLocation (DesignSystem, Features, Location) تُستثنى على
// المنصات غير Apple؛ محركات المنطق والاختبارات الأربعة تُبنى في كل مكان.
import PackageDescription

var products: [Product] = [
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "TrafficEngine", targets: ["TrafficEngine"]),
    .library(name: "PlaceRanking", targets: ["PlaceRanking"]),
    .library(name: "NearbyDiscovery", targets: ["NearbyDiscovery"]),
    .library(name: "Networking", targets: ["Networking"]),
    .library(name: "BackendClient", targets: ["BackendClient"]),
    .library(name: "GoogleProviders", targets: ["GoogleProviders"]),
    .library(name: "DevMocks", targets: ["DevMocks"]),
    .library(name: "Storage", targets: ["Storage"]),
    .library(name: "Analytics", targets: ["Analytics"]),
    .library(name: "RemoteConfig", targets: ["RemoteConfig"]),
]

var targets: [Target] = [
    .target(name: "Domain"),
    .target(name: "TrafficEngine", dependencies: ["Domain"]),
    .target(name: "PlaceRanking", dependencies: ["Domain"]),
    .target(name: "Networking", dependencies: ["Domain"]),
    .target(name: "BackendClient", dependencies: ["Domain", "Networking"]),
    .target(name: "GoogleProviders", dependencies: ["Domain", "BackendClient", "Networking"]),
    .target(name: "NearbyDiscovery", dependencies: ["Domain", "PlaceRanking"]),
    .target(name: "DevMocks", dependencies: ["Domain"]),
    .target(name: "Storage", dependencies: ["Domain"]),
    .target(name: "Analytics", dependencies: ["Domain", "BackendClient"]),
    .target(name: "RemoteConfig", dependencies: ["Domain", "BackendClient", "TrafficEngine", "PlaceRanking"]),
    .testTarget(name: "TrafficEngineTests", dependencies: ["TrafficEngine", "Domain"]),
    .testTarget(name: "PlaceRankingTests", dependencies: ["PlaceRanking", "Domain"]),
    .testTarget(name: "NearbyDiscoveryTests", dependencies: ["NearbyDiscovery", "DevMocks", "Domain"]),
    .testTarget(
        name: "GoogleProvidersTests",
        dependencies: ["GoogleProviders", "BackendClient", "Domain"],
        resources: [.copy("Fixtures")]
    ),
]

#if canImport(Darwin)
products += [
    .library(name: "Location", targets: ["Location"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Features", targets: ["Features"]),
]
targets += [
    .target(name: "Location", dependencies: ["Domain"]),
    .target(name: "DesignSystem", dependencies: ["Domain"]),
    .target(
        name: "Features",
        dependencies: [
            "Domain", "DesignSystem", "TrafficEngine", "PlaceRanking", "NearbyDiscovery",
            "Storage", "Analytics", "RemoteConfig", "Location", "BackendClient",
        ],
        resources: [.process("Resources")]
    ),
]
#endif

let package = Package(
    name: "BedoonZahmaKit",
    defaultLocalization: "ar",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: products,
    targets: targets
)
