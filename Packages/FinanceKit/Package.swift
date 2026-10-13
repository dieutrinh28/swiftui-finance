// swift-tools-version: 6.0
import PackageDescription

// FinanceKit holds everything that is not SwiftUI:
// - FinanceDomain: pure Swift + Foundation. Money, currencies, calendar policy,
//   financial enums and rules. No SwiftData, so it is fast to test and portable.
// - FinancePersistence: SwiftData schema, container factory, services, seeding,
//   fixtures. Apple platforms only.
// - FinanceFeatures: @Observable screen models (presentation logic without
//   SwiftUI), unit-tested with `swift test`. Apple platforms only.

var products: [Product] = [
    .library(name: "FinanceDomain", targets: ["FinanceDomain"]),
]

var targets: [Target] = [
    .target(name: "FinanceDomain"),
    .testTarget(name: "FinanceDomainTests", dependencies: ["FinanceDomain"]),
]

#if os(macOS)
products += [
    .library(name: "FinancePersistence", targets: ["FinancePersistence"]),
    .library(name: "FinanceFeatures", targets: ["FinanceFeatures"]),
]
targets += [
    .target(name: "FinancePersistence", dependencies: ["FinanceDomain"]),
    .target(name: "FinanceFeatures", dependencies: ["FinancePersistence", "FinanceDomain"]),
    .testTarget(
        name: "FinancePersistenceTests",
        dependencies: ["FinancePersistence", "FinanceDomain"]
    ),
    .testTarget(
        name: "FinanceFeaturesTests",
        dependencies: ["FinanceFeatures", "FinancePersistence", "FinanceDomain"]
    ),
]
#endif

let package = Package(
    name: "FinanceKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: products,
    targets: targets
)
