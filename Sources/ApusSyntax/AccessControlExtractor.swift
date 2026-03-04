import SwiftSyntax
import ApusCore

/// Extracts access level from a declaration's modifier list.
enum AccessControlExtractor: Sendable {
    static func extract(from modifiers: DeclModifierListSyntax) -> AccessLevel? {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.open):
                return .open
            case .keyword(.public):
                return .public_
            case .keyword(.package):
                return .package_
            case .keyword(.internal):
                return .internal_
            case .keyword(.fileprivate):
                return .fileprivate_
            case .keyword(.private):
                return .private_
            default:
                continue
            }
        }
        return nil
    }
}
