import XCTest
import SwiftTreeSitter
import TreeSitterOCaml

final class TreeSitterOCamlTests: XCTestCase {

    func testOCaml() throws {
        let language = Language(language: tree_sitter_ocaml())

        let parser = Parser()
        try parser.setLanguage(language)

        let source = """
        module M = struct
            let x = 0
        end
        """

        let tree = try XCTUnwrap(parser.parse(source))
        let root = try XCTUnwrap(tree.rootNode)

        XCTAssertFalse(root.hasError)
    }

    func testOCamlInterface() throws {
        let language = Language(language: tree_sitter_ocaml_interface())

        let parser = Parser()
        try parser.setLanguage(language)

        let source = """
        module M : sig
            val x : int
        end
        """

        let tree = try XCTUnwrap(parser.parse(source))
        let root = try XCTUnwrap(tree.rootNode)

        XCTAssertFalse(root.hasError)
    }

}
