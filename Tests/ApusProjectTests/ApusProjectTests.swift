import Testing
import Foundation
@testable import ApusProject

@Suite("ApusProject Tests")
struct ApusProjectTests {

    // MARK: - SPMParser Tests

    @Test("SPMParser parses this project's Package.swift")
    func spmParserParsesThisPackage() throws {
        let parser = SPMParser()
        // Use the Apus project itself as a test fixture
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ApusProjectTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // root
            .path

        let descriptor = try parser.parse(at: projectRoot)

        #expect(descriptor.name == "Apus")
        #expect(descriptor.type == .swiftPackage)
        #expect(!descriptor.targets.isEmpty)

        // Verify known targets exist
        let targetNames = descriptor.targets.map(\.name)
        #expect(targetNames.contains("ApusCore"))
        #expect(targetNames.contains("ApusProject"))
        #expect(targetNames.contains("ApusCLI"))
    }

    @Test("SPMParser extracts target dependencies")
    func spmParserExtractsDependencies() throws {
        let parser = SPMParser()
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let descriptor = try parser.parse(at: projectRoot)

        // ApusProject should depend on ApusCore
        let apusProject = descriptor.targets.first { $0.name == "ApusProject" }
        #expect(apusProject != nil)
        #expect(apusProject?.dependencies.contains("ApusCore") == true)
    }

    @Test("SPMParser assigns correct product types")
    func spmParserAssignsProductTypes() throws {
        let parser = SPMParser()
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let descriptor = try parser.parse(at: projectRoot)

        let cliTarget = descriptor.targets.first { $0.name == "ApusCLI" }
        #expect(cliTarget?.productType == .commandLineTool)

        let testTarget = descriptor.targets.first { $0.name == "ApusProjectTests" }
        #expect(testTarget?.productType == .unitTestBundle)
    }

    // MARK: - DerivedDataLocator Tests

    @Test("DerivedDataLocator returns expected path format")
    func derivedDataLocatorExpectedPath() {
        let locator = DerivedDataLocator(derivedDataPath: "/tmp/FakeDerivedData")
        let expected = locator.expectedIndexStorePath(forProject: "MyApp")
        #expect(expected == "/tmp/FakeDerivedData/MyApp/Index.noindex/DataStore")
    }

    @Test("DerivedDataLocator returns nil for nonexistent project")
    func derivedDataLocatorReturnsNilForMissing() {
        let locator = DerivedDataLocator(derivedDataPath: "/tmp/NonexistentDerivedData_\(UUID().uuidString)")
        let result = locator.locateIndexStore(forProject: "NonexistentProject")
        #expect(result == nil)
    }

    @Test("DerivedDataLocator returns empty array for nonexistent path")
    func derivedDataLocatorAllPathsEmpty() {
        let locator = DerivedDataLocator(derivedDataPath: "/tmp/NonexistentDerivedData_\(UUID().uuidString)")
        let result = locator.allIndexStorePaths()
        #expect(result.isEmpty)
    }

    // MARK: - ProjectDescriptor Tests

    @Test("ProjectDescriptor stores all fields")
    func projectDescriptorFields() {
        let target = TargetDescriptor(
            name: "MyTarget",
            productType: .application,
            sourceFiles: ["main.swift"],
            dependencies: ["CoreLib"],
            buildSettings: ["SWIFT_VERSION": "6.0"]
        )

        let descriptor = ProjectDescriptor(
            name: "MyProject",
            type: .xcodeproj,
            rootPath: "/path/to/project",
            targets: [target]
        )

        #expect(descriptor.name == "MyProject")
        #expect(descriptor.type == .xcodeproj)
        #expect(descriptor.rootPath == "/path/to/project")
        #expect(descriptor.targets.count == 1)
        #expect(descriptor.targets[0].name == "MyTarget")
        #expect(descriptor.targets[0].productType == .application)
        #expect(descriptor.targets[0].sourceFiles == ["main.swift"])
        #expect(descriptor.targets[0].dependencies == ["CoreLib"])
        #expect(descriptor.targets[0].buildSettings["SWIFT_VERSION"] == "6.0")
    }

    // MARK: - ProjectDiscovery Tests

    @Test("ProjectDiscovery finds this SPM project")
    func projectDiscoveryFindsThisProject() throws {
        let discovery = ProjectDiscovery()
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let result = try discovery.discoverSingle(at: projectRoot)
        #expect(result != nil)
        #expect(result?.name == "Apus")
        #expect(result?.type == .swiftPackage)
    }

    // MARK: - XcodeGenParser Tests

    @Test("XcodeGenParser parses a simple project.yml")
    func xcodeGenParserParsesYaml() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("apus-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let yamlContent = """
        name: TestProject
        targets:
          MyApp:
            type: application
            sources:
              - Sources
            dependencies:
              - target: MyLib
          MyLib:
            type: library.static
            sources:
              - Lib
        """

        let yamlPath = tmpDir.appendingPathComponent("project.yml")
        try yamlContent.write(to: yamlPath, atomically: true, encoding: .utf8)

        let parser = XcodeGenParser()
        let descriptor = try parser.parse(at: yamlPath.path)

        #expect(descriptor.name == "TestProject")
        #expect(descriptor.type == .xcodeGen)
        #expect(descriptor.targets.count == 2)

        let app = descriptor.targets.first { $0.name == "MyApp" }
        #expect(app?.productType == .application)
        #expect(app?.dependencies.contains("MyLib") == true)
        #expect(app?.sourceFiles.contains("Sources") == true)

        let lib = descriptor.targets.first { $0.name == "MyLib" }
        #expect(lib?.productType == .staticLibrary)
    }
}
