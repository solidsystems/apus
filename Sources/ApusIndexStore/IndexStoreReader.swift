import Foundation
import CIndexStore
import ApusCore

/// Error types for IndexStore operations.
public enum IndexStoreError: Error, Sendable {
    case storeCreationFailed(String)
    case unitReaderFailed(String)
    case recordReaderFailed(String)
}

/// Low-level wrapper around the C IndexStore API.
/// Opens an IndexStore at a given path and provides methods to iterate units and records.
///
/// Marked @unchecked Sendable because the underlying C store handle is immutable after init
/// and the C API is safe to call from any thread for read operations.
public final class IndexStoreReader: @unchecked Sendable {
    private nonisolated(unsafe) let store: indexstore_t
    private let storePath: String

    /// Opens an IndexStore at the given path.
    /// - Parameter storePath: Path to the IndexStore directory.
    /// - Throws: `IndexStoreError.storeCreationFailed` if the store cannot be opened.
    public init(storePath: String) throws {
        self.storePath = storePath
        var error: indexstore_error_t?
        guard let store = indexstore_store_create(storePath, &error) else {
            let message: String
            if let error {
                message = String(cString: indexstore_error_get_description(error))
                indexstore_error_dispose(error)
            } else {
                message = "Unknown error"
            }
            throw IndexStoreError.storeCreationFailed(message)
        }
        self.store = store
    }

    deinit {
        indexstore_store_dispose(store)
    }

    /// Returns all unit names in the store.
    public func unitNames() -> [String] {
        var names: [String] = []
        withUnsafeMutablePointer(to: &names) { ptr in
            indexstore_store_units_apply_f(store, 0, ptr) { context, unitName in
                guard let context else { return true }
                let namesPtr = context.assumingMemoryBound(to: [String].self)
                let name = stringFromRef(unitName)
                namesPtr.pointee.append(name)
                return true
            }
        }
        return names
    }

    /// Reads a single unit and returns its record dependency names and source file path.
    public func readUnit(name: String) throws -> UnitInfo {
        var error: indexstore_error_t?
        guard let unitReader = indexstore_unit_reader_create(store, name, &error) else {
            let message: String
            if let error {
                message = String(cString: indexstore_error_get_description(error))
                indexstore_error_dispose(error)
            } else {
                message = "Unknown error"
            }
            throw IndexStoreError.unitReaderFailed(message)
        }
        defer { indexstore_unit_reader_dispose(unitReader) }

        let mainFile = stringFromRef(indexstore_unit_reader_get_main_file(unitReader))
        let moduleName = stringFromRef(indexstore_unit_reader_get_module_name(unitReader))
        let isSystem = indexstore_unit_reader_is_system_unit(unitReader)

        var recordNames: [String] = []
        withUnsafeMutablePointer(to: &recordNames) { ptr in
            indexstore_unit_reader_dependencies_apply_f(unitReader, ptr) { context, dep in
                guard let context else { return true }
                let kind = indexstore_unit_dependency_get_kind(dep)
                guard kind == INDEXSTORE_UNIT_DEPENDENCY_RECORD else { return true }
                let namesPtr = context.assumingMemoryBound(to: [String].self)
                let nameRef = indexstore_unit_dependency_get_name(dep)
                let name = stringFromRef(nameRef)
                namesPtr.pointee.append(name)
                return true
            }
        }

        return UnitInfo(
            mainFile: mainFile,
            moduleName: moduleName,
            isSystem: isSystem,
            recordNames: recordNames
        )
    }

    /// Reads a record and returns all symbol occurrences with their relations.
    public func readRecord(name: String) throws -> [OccurrenceInfo] {
        var error: indexstore_error_t?
        guard let recordReader = indexstore_record_reader_create(store, name, &error) else {
            let message: String
            if let error {
                message = String(cString: indexstore_error_get_description(error))
                indexstore_error_dispose(error)
            } else {
                message = "Unknown error"
            }
            throw IndexStoreError.recordReaderFailed(message)
        }
        defer { indexstore_record_reader_dispose(recordReader) }

        var occurrences: [OccurrenceInfo] = []
        withUnsafeMutablePointer(to: &occurrences) { ptr in
            indexstore_record_reader_occurrences_apply_f(recordReader, ptr) { context, occurrence in
                guard let context else { return true }
                let occsPtr = context.assumingMemoryBound(to: [OccurrenceInfo].self)

                let symbol = indexstore_occurrence_get_symbol(occurrence)
                let roles = indexstore_occurrence_get_roles(occurrence)
                let usr = stringFromRef(indexstore_symbol_get_usr(symbol))
                let name = stringFromRef(indexstore_symbol_get_name(symbol))
                let kind = indexstore_symbol_get_kind(symbol)
                let properties = indexstore_symbol_get_properties(symbol)

                var line: UInt32 = 0
                var column: UInt32 = 0
                indexstore_occurrence_get_line_col(occurrence, &line, &column)

                // Collect relations
                var relations: [RelationInfo] = []
                withUnsafeMutablePointer(to: &relations) { relPtr in
                    indexstore_occurrence_relations_apply_f(occurrence, relPtr) { relContext, rel in
                        guard let relContext else { return true }
                        let relsPtr = relContext.assumingMemoryBound(to: [RelationInfo].self)
                        let relSymbol = indexstore_symbol_relation_get_symbol(rel)
                        let relRoles = indexstore_symbol_relation_get_roles(rel)
                        let relUSR = stringFromRef(indexstore_symbol_get_usr(relSymbol))
                        let relName = stringFromRef(indexstore_symbol_get_name(relSymbol))
                        let relKind = indexstore_symbol_get_kind(relSymbol)
                        relsPtr.pointee.append(RelationInfo(
                            usr: relUSR,
                            name: relName,
                            symbolKind: relKind,
                            roles: relRoles
                        ))
                        return true
                    }
                }

                occsPtr.pointee.append(OccurrenceInfo(
                    usr: usr,
                    name: name,
                    symbolKind: kind,
                    symbolProperties: properties,
                    roles: roles,
                    line: Int(line),
                    column: Int(column),
                    relations: relations
                ))
                return true
            }
        }
        return occurrences
    }
}

// MARK: - Data Types

/// Information about a compilation unit.
public struct UnitInfo: Sendable {
    public let mainFile: String
    public let moduleName: String
    public let isSystem: Bool
    public let recordNames: [String]
}

/// Information about a single symbol occurrence in a record.
public struct OccurrenceInfo: Sendable {
    public let usr: String
    public let name: String
    public let symbolKind: indexstore_symbol_kind_t
    public let symbolProperties: indexstore_symbol_property_t
    public let roles: indexstore_symbol_role_t
    public let line: Int
    public let column: Int
    public let relations: [RelationInfo]
}

/// Information about a relation within an occurrence.
public struct RelationInfo: Sendable {
    public let usr: String
    public let name: String
    public let symbolKind: indexstore_symbol_kind_t
    public let roles: indexstore_symbol_role_t
}

// MARK: - Helpers

/// Converts an indexstore_string_ref_t to a Swift String.
private func stringFromRef(_ ref: indexstore_string_ref_t) -> String {
    guard ref.length > 0, ref.data != nil else { return "" }
    return ref.data.withMemoryRebound(to: UInt8.self, capacity: ref.length) { ptr in
        let buffer = UnsafeBufferPointer(start: ptr, count: ref.length)
        return String(decoding: buffer, as: UTF8.self)
    }
}
