import Testing
import CIndexStore
import ApusCore
@testable import ApusIndexStore

@Suite("ApusIndexStore Tests")
struct ApusIndexStoreTests {

    // MARK: - SymbolMapper Tests

    @Suite("SymbolMapper")
    struct SymbolMapperTests {
        @Test("Maps class symbol kind")
        func mapClass() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_CLASS) == .class_)
        }

        @Test("Maps struct symbol kind")
        func mapStruct() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_STRUCT) == .struct_)
        }

        @Test("Maps enum symbol kind")
        func mapEnum() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_ENUM) == .enum_)
        }

        @Test("Maps protocol symbol kind")
        func mapProtocol() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_PROTOCOL) == .protocol_)
        }

        @Test("Maps extension symbol kind")
        func mapExtension() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_EXTENSION) == .extension_)
        }

        @Test("Maps function symbol kind")
        func mapFunction() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_FUNCTION) == .function)
        }

        @Test("Maps instance method to method")
        func mapInstanceMethod() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_INSTANCEMETHOD) == .method)
        }

        @Test("Maps class method to method")
        func mapClassMethod() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_CLASSMETHOD) == .method)
        }

        @Test("Maps static method to method")
        func mapStaticMethod() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_STATICMETHOD) == .method)
        }

        @Test("Maps instance property to property")
        func mapInstanceProperty() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_INSTANCEPROPERTY) == .property)
        }

        @Test("Maps class property to property")
        func mapClassProperty() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_CLASSPROPERTY) == .property)
        }

        @Test("Maps static property to property")
        func mapStaticProperty() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_STATICPROPERTY) == .property)
        }

        @Test("Maps variable symbol kind")
        func mapVariable() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_VARIABLE) == .variable)
        }

        @Test("Maps constructor symbol kind")
        func mapConstructor() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_CONSTRUCTOR) == .constructor)
        }

        @Test("Maps typealias symbol kind")
        func mapTypeAlias() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_TYPEALIAS) == .typeAlias)
        }

        @Test("Maps macro symbol kind")
        func mapMacro() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_MACRO) == .macro)
        }

        @Test("Maps module symbol kind")
        func mapModule() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_MODULE) == .module)
        }

        @Test("Maps enum constant to variable")
        func mapEnumConstant() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_ENUMCONSTANT) == .variable)
        }

        @Test("Maps field to property")
        func mapField() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_FIELD) == .property)
        }

        @Test("Returns nil for unknown symbol kind")
        func mapUnknown() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_UNKNOWN) == nil)
        }

        @Test("Returns nil for comment tag")
        func mapCommentTag() {
            #expect(SymbolMapper.mapKind(INDEXSTORE_SYMBOL_KIND_COMMENTTAG) == nil)
        }

        @Test("Maps public access level")
        func mapPublicAccess() {
            // public = bit 19 | bit 18
            let props = indexstore_symbol_property_t(rawValue: (1 << 19) | (1 << 18))
            #expect(SymbolMapper.mapAccessLevel(props) == .public_)
        }

        @Test("Maps internal access level")
        func mapInternalAccess() {
            // internal = bit 18 | bit 17
            let props = indexstore_symbol_property_t(rawValue: (1 << 18) | (1 << 17))
            #expect(SymbolMapper.mapAccessLevel(props) == .internal_)
        }

        @Test("Maps fileprivate access level")
        func mapFileprivateAccess() {
            // fileprivate = bit 18 only
            let props = indexstore_symbol_property_t(rawValue: (1 << 18))
            #expect(SymbolMapper.mapAccessLevel(props) == .fileprivate_)
        }

        @Test("Maps private access level")
        func mapPrivateAccess() {
            // private = bit 17 only
            let props = indexstore_symbol_property_t(rawValue: (1 << 17))
            #expect(SymbolMapper.mapAccessLevel(props) == .private_)
        }

        @Test("Maps package access level")
        func mapPackageAccess() {
            // package = bit 19 only
            let props = indexstore_symbol_property_t(rawValue: (1 << 19))
            #expect(SymbolMapper.mapAccessLevel(props) == .package_)
        }

        @Test("Returns nil for no access level bits")
        func mapNoAccess() {
            let props = indexstore_symbol_property_t(rawValue: 0)
            #expect(SymbolMapper.mapAccessLevel(props) == nil)
        }
    }

    // MARK: - RelationMapper Tests

    // Relation role bit values from indexstore.h
    private static let relChildOf: UInt64     = 1 << 9
    private static let relBaseOf: UInt64      = 1 << 10
    private static let relOverrideOf: UInt64  = 1 << 11
    private static let relCalledBy: UInt64    = 1 << 13
    private static let relExtendedBy: UInt64  = 1 << 14
    private static let relAccessorOf: UInt64  = 1 << 15
    private static let relContainedBy: UInt64 = 1 << 16
    private static let relSpecializationOf: UInt64 = 1 << 18

    // Non-relation role bit values
    private static let roleDeclaration: UInt64 = 1 << 0
    private static let roleDefinition: UInt64  = 1 << 1

    @Suite("RelationMapper")
    struct RelationMapperTests {
        @Test("Maps CALLEDBY role to calls")
        func mapCalledBy() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relCalledBy)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.calls])
        }

        @Test("Maps BASEOF role to conformsTo")
        func mapBaseOf() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relBaseOf)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.conformsTo])
        }

        @Test("Maps OVERRIDEOF role to overrides")
        func mapOverrideOf() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relOverrideOf)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.overrides])
        }

        @Test("Maps EXTENDEDBY role to extends")
        func mapExtendedBy() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relExtendedBy)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.extends])
        }

        @Test("Maps CHILDOF role to memberOf")
        func mapChildOf() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relChildOf)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.memberOf])
        }

        @Test("Maps CONTAINEDBY role to contains")
        func mapContainedBy() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relContainedBy)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.contains])
        }

        @Test("Maps ACCESSOROF role to associatedWith")
        func mapAccessorOf() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relAccessorOf)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.associatedWith])
        }

        @Test("Maps SPECIALIZATIONOF role to dependsOn")
        func mapSpecializationOf() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relSpecializationOf)
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds == [EdgeKind.dependsOn])
        }

        @Test("Maps combined roles to multiple edge kinds")
        func mapCombinedRoles() {
            let roles = indexstore_symbol_role_t(
                rawValue: ApusIndexStoreTests.relCalledBy | ApusIndexStoreTests.relChildOf
            )
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds.contains(EdgeKind.calls))
            #expect(edgeKinds.contains(EdgeKind.memberOf))
            #expect(edgeKinds.count == 2)
        }

        @Test("Returns empty for non-relation roles")
        func mapNonRelationRoles() {
            let roles = indexstore_symbol_role_t(
                rawValue: ApusIndexStoreTests.roleDeclaration | ApusIndexStoreTests.roleDefinition
            )
            let edgeKinds = RelationMapper.mapRoles(roles)
            #expect(edgeKinds.isEmpty)
        }

        @Test("hasRelationRoles returns true for relation roles")
        func hasRelationRolesTrue() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.relCalledBy)
            #expect(RelationMapper.hasRelationRoles(roles) == true)
        }

        @Test("hasRelationRoles returns false for non-relation roles")
        func hasRelationRolesFalse() {
            let roles = indexstore_symbol_role_t(rawValue: ApusIndexStoreTests.roleDeclaration)
            #expect(RelationMapper.hasRelationRoles(roles) == false)
        }

        @Test("hasRelationRoles returns false for zero")
        func hasRelationRolesZero() {
            let roles = indexstore_symbol_role_t(rawValue: 0)
            #expect(RelationMapper.hasRelationRoles(roles) == false)
        }
    }

    // MARK: - IndexStoreGraphBuilder Tests

    @Suite("IndexStoreGraphBuilder")
    struct IndexStoreGraphBuilderTests {
        @Test("Build with nonexistent store returns empty result")
        func buildNonexistentStore() async throws {
            let builder = IndexStoreGraphBuilder()
            let graph = InMemoryGraph()
            let result = try await builder.build(
                storePath: "/nonexistent/path/to/IndexStore",
                into: graph
            )
            #expect(result.nodes.isEmpty)
            #expect(result.edges.isEmpty)
            #expect(result.unitCount == 0)
            #expect(result.recordCount == 0)
        }

        @Test("findIndexStorePaths with nonexistent DerivedData returns empty")
        func findNonexistentDerivedData() {
            let paths = IndexStoreGraphBuilder.findIndexStorePaths(
                derivedDataPath: "/nonexistent/DerivedData"
            )
            #expect(paths.isEmpty)
        }
    }
}
