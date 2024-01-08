// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "TreeSitterVerilog",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "TreeSitterVerilog", targets: ["TreeSitterVerilog"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TreeSitterVerilog",
                path: ".",
                exclude: [
                    "binding.gyp",
                    "bindings",
                    "Cargo.toml",
                    "corpus",
                    "examples",
                    "grammar.js",
                    "LICENSE",
                    "package.json",
                    "README.md",
                    "src/grammar.json",
                    "src/node-types.json",
                ],
                sources: [
                    "src/parser.c",
                ],
                publicHeadersPath: "bindings/swift",
                cSettings: [.headerSearchPath("src")])
    ]
)
