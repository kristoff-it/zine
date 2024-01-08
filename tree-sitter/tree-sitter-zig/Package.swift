// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TreeSitterZig",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "TreeSitterZig", targets: ["TreeSitterZig"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TreeSitterZig",
                path: ".",
                exclude: [
                    "assets",
                    "binding.gyp",
                    "bindings",
                    "Cargo.lock",
                    "Cargo.toml",
                    "grammar.js",
                    "grammar.y",
                    "LICENSE",
                    "package.json",
                    "README.md",
                    "src/grammar.json",
                    "src/node-types.json",
                ],
                sources: [
                    "src/parser.c",
                ],
                resources: [
                    .copy("queries")
                ],
                publicHeadersPath: "bindings/swift",
                cSettings: [.headerSearchPath("src")])
    ]
)
