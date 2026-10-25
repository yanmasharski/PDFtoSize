// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PDFtoSize",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFtoSizeCore", targets: ["PDFtoSizeCore"]),
        .executable(name: "pdftosize", targets: ["pdftosize"]),
    ],
    targets: [
        .target(name: "PDFtoSizeCore"),
        .executableTarget(name: "pdftosize", dependencies: ["PDFtoSizeCore"]),
        .executableTarget(name: "PDFtoSizeApp", dependencies: ["PDFtoSizeCore"]),
        .testTarget(name: "PDFtoSizeCoreTests", dependencies: ["PDFtoSizeCore"]),
    ],
    // CoreGraphics types are not Sendable; the core shares them only inside one worker.
    swiftLanguageModes: [.v5]
)
