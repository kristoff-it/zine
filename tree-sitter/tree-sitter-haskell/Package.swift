// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "TreeSitterHaskell",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "TreeSitterHaskell", targets: ["TreeSitterHaskell"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TreeSitterHaskell",
                path: ".",
                exclude: [
                    "binding.gyp",
                    "bindings",
                    "Cargo.toml",
                    "Cargo.lock",
                    "examples",
                    "grammar",
                    "grammar.js",
                    "LICENSE",
                    "Makefile",
                    "package.json",
                    "README.md",
                    "script",
                    "src/grammar.json",
                    "src/node-types.json",
                    "test",
                ],
                sources: [
                    "src/parser.c",
                    "src/scanner.c",
                    "src/unicode.h",
                ],
                resources: [
                    .copy("queries")
                ],
                publicHeadersPath: "bindings/swift",
                cSettings: [.headerSearchPath("src")])
    ]
)
