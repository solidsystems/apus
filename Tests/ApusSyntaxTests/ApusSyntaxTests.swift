import Testing
@testable import ApusSyntax
import ApusCore

@Suite("ApusSyntax Tests")
struct ApusSyntaxTests {

    let parser = SwiftFileParser()

    // MARK: - Class/Struct/Enum Extraction

    @Test("Extracts class declaration")
    func extractsClass() {
        let source = """
        public class MyViewModel {
            var name: String = ""
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let classNodes = result.nodes.filter { $0.kind == .class_ }
        #expect(classNodes.count == 1)
        #expect(classNodes[0].name == "MyViewModel")
        #expect(classNodes[0].accessLevel == .public_)
    }

    @Test("Extracts struct declaration")
    func extractsStruct() {
        let source = """
        struct Point {
            let x: Double
            let y: Double
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let structNodes = result.nodes.filter { $0.kind == .struct_ }
        #expect(structNodes.count == 1)
        #expect(structNodes[0].name == "Point")
    }

    @Test("Extracts enum declaration")
    func extractsEnum() {
        let source = """
        enum Direction {
            case north, south, east, west
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let enumNodes = result.nodes.filter { $0.kind == .enum_ }
        #expect(enumNodes.count == 1)
        #expect(enumNodes[0].name == "Direction")
    }

    // MARK: - Protocol/Actor/Extension

    @Test("Extracts protocol declaration")
    func extractsProtocol() {
        let source = """
        protocol Drawable {
            func draw()
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let protoNodes = result.nodes.filter { $0.kind == .protocol_ }
        #expect(protoNodes.count == 1)
        #expect(protoNodes[0].name == "Drawable")

        // Should also extract the method
        let methods = result.nodes.filter { $0.kind == .method }
        #expect(methods.count == 1)
        #expect(methods[0].name == "draw")
    }

    @Test("Extracts actor declaration")
    func extractsActor() {
        let source = """
        actor DataStore {
            var items: [String] = []
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let actorNodes = result.nodes.filter { $0.kind == .actor }
        #expect(actorNodes.count == 1)
        #expect(actorNodes[0].name == "DataStore")
    }

    @Test("Extracts extension with conformance")
    func extractsExtension() {
        let source = """
        extension String: CustomStringConvertible {
            public var description: String { self }
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let extNodes = result.nodes.filter { $0.kind == .extension_ }
        #expect(extNodes.count == 1)
        #expect(extNodes[0].name == "String")

        // Should have an extends edge
        let extendsEdges = result.edges.filter { $0.kind == .extends }
        #expect(extendsEdges.count == 1)
        #expect(extendsEdges[0].metadata["targetName"] == "String")

        // Should have a conformsTo edge
        let conformsEdges = result.edges.filter { $0.kind == .conformsTo }
        #expect(conformsEdges.count == 1)
        #expect(conformsEdges[0].metadata["targetName"] == "CustomStringConvertible")
    }

    // MARK: - Functions and Properties

    @Test("Distinguishes top-level functions from methods")
    func functionVsMethod() {
        let source = """
        func topLevel() {}
        struct Foo {
            func memberFunc() {}
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let functions = result.nodes.filter { $0.kind == .function }
        #expect(functions.count == 1)
        #expect(functions[0].name == "topLevel")

        let methods = result.nodes.filter { $0.kind == .method }
        #expect(methods.count == 1)
        #expect(methods[0].name == "memberFunc")
    }

    @Test("Distinguishes top-level variables from properties")
    func variableVsProperty() {
        let source = """
        var globalFlag = true
        class Config {
            var setting: Int = 0
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let variables = result.nodes.filter { $0.kind == .variable }
        #expect(variables.count == 1)
        #expect(variables[0].name == "globalFlag")

        let properties = result.nodes.filter { $0.kind == .property }
        #expect(properties.count == 1)
        #expect(properties[0].name == "setting")
    }

    // MARK: - Access Control

    @Test("Extracts all access levels")
    func accessLevels() {
        let source = """
        open class A {}
        public class B {}
        internal class C {}
        fileprivate class D {}
        private class E {}
        class F {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let classes = result.nodes.filter { $0.kind == .class_ }.sorted { $0.name < $1.name }
        #expect(classes.count == 6)
        #expect(classes[0].accessLevel == .open)       // A
        #expect(classes[1].accessLevel == .public_)     // B
        #expect(classes[2].accessLevel == .internal_)   // C
        #expect(classes[3].accessLevel == .fileprivate_) // D
        #expect(classes[4].accessLevel == .private_)    // E
        #expect(classes[5].accessLevel == nil)          // F (implicit)
    }

    // MARK: - Doc Comments

    @Test("Extracts line doc comments")
    func lineDocComments() {
        let source = """
        /// A simple greeter.
        /// It says hello.
        struct Greeter {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let structNode = result.nodes.first { $0.kind == .struct_ }
        #expect(structNode?.docComment == "A simple greeter.\nIt says hello.")
    }

    @Test("Extracts block doc comments")
    func blockDocComments() {
        let source = """
        /**
         * A block-documented class.
         */
        class Documented {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let classNode = result.nodes.first { $0.kind == .class_ }
        #expect(classNode?.docComment != nil)
        #expect(classNode!.docComment!.contains("block-documented"))
    }

    // MARK: - Attributes

    @Test("Extracts attributes")
    func extractsAttributes() {
        let source = """
        @available(iOS 15, *)
        @MainActor
        public class ViewModel {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let classNode = result.nodes.first { $0.kind == .class_ }
        #expect(classNode != nil)
        #expect(classNode!.attributes.contains("@available"))
        #expect(classNode!.attributes.contains("@MainActor"))
    }

    // MARK: - Imports

    @Test("Extracts imports")
    func extractsImports() {
        let source = """
        import Foundation
        import SwiftUI

        struct MyView {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        #expect(result.imports.count == 2)
        #expect(result.imports.contains("Foundation"))
        #expect(result.imports.contains("SwiftUI"))
    }

    // MARK: - Conformances

    @Test("Extracts conformances from inheritance clause")
    func extractsConformances() {
        let source = """
        struct MyType: Codable, Sendable, Hashable {}
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let conformsEdges = result.edges.filter { $0.kind == .conformsTo }
        let targetNames = conformsEdges.compactMap { $0.metadata["targetName"] }
        #expect(targetNames.contains("Codable"))
        #expect(targetNames.contains("Sendable"))
        #expect(targetNames.contains("Hashable"))
    }

    // MARK: - Nested Types

    @Test("Handles nested type declarations")
    func nestedTypes() {
        let source = """
        struct Outer {
            struct Inner {
                var value: Int = 0
            }
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let structs = result.nodes.filter { $0.kind == .struct_ }
        #expect(structs.count == 2)

        let inner = structs.first { $0.name == "Inner" }
        #expect(inner != nil)
        #expect(inner!.qualifiedName == "Outer.Inner")

        // Should have containment edge from Outer to Inner
        let containsEdges = result.edges.filter { $0.kind == .contains }
        let outerNode = structs.first { $0.name == "Outer" }
        let hasContainment = containsEdges.contains { $0.sourceID == outerNode?.id && $0.targetID == inner?.id }
        #expect(hasContainment)
    }

    // MARK: - Other Declarations

    @Test("Extracts initializer")
    func extractsInit() {
        let source = """
        struct Foo {
            init(value: Int) {}
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let inits = result.nodes.filter { $0.kind == .constructor }
        #expect(inits.count == 1)
        #expect(inits[0].name == "init")
    }

    @Test("Extracts subscript")
    func extractsSubscript() {
        let source = """
        struct Matrix {
            subscript(row: Int, col: Int) -> Double { 0 }
        }
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let subscripts = result.nodes.filter { $0.kind == .subscript_ }
        #expect(subscripts.count == 1)
    }

    @Test("Extracts typealias")
    func extractsTypealias() {
        let source = """
        typealias StringDict = [String: String]
        """
        let result = parser.parse(source: source, filePath: "test.swift")

        let aliases = result.nodes.filter { $0.kind == .typeAlias }
        #expect(aliases.count == 1)
        #expect(aliases[0].name == "StringDict")
    }

    // MARK: - File Node

    @Test("Creates file node")
    func createsFileNode() {
        let source = "struct X {}"
        let result = parser.parse(source: source, filePath: "/path/to/File.swift")

        let fileNodes = result.nodes.filter { $0.kind == .file }
        #expect(fileNodes.count == 1)
        #expect(fileNodes[0].name == "File.swift")
        #expect(fileNodes[0].id == "file:/path/to/File.swift")
    }

    // MARK: - Synthetic IDs

    @Test("Generates synthetic IDs in filepath:line:name format")
    func syntheticIDs() {
        let source = "struct Hello {}"
        let result = parser.parse(source: source, filePath: "test.swift")

        let structNode = result.nodes.first { $0.kind == .struct_ }
        #expect(structNode != nil)
        #expect(structNode!.id.hasPrefix("test.swift:"))
        #expect(structNode!.id.hasSuffix(":Hello"))
    }
}
