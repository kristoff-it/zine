// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TreeSitterOCaml",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "TreeSitterOCaml", targets: ["TreeSitterOCaml"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.7.1"),
    ],
    targets: [
        .target(
            name: "TreeSitterOCaml",
            path: ".",
            sources: [
                "interface/src/parser.c",
                "interface/src/scanner.c",
                "ocaml/src/parser.c",
                "ocaml/src/scanner.c",
            ],
            resources: [
                .copy("queries")
            ],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("ocaml/src")]
        ),
        .testTarget(
            name: "TreeSitterOCamlTests",
            dependencies: [
                "SwiftTreeSitter",
                "TreeSitterOCaml",
            ],
            path: "bindings/swift/TreeSitterOCamlTests"
        )
    ]
)
