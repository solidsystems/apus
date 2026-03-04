import Foundation

/// Sections available in an analysis report.
public enum AnalysisSection: String, CaseIterable, Sendable {
    case overview
    case architecture
    case typesystem
    case api
    case dependencies
    case hotspots
    case patterns
}

/// A single rendered section of the analysis report.
public struct SectionResult: Sendable {
    public let section: AnalysisSection
    public let title: String
    public let content: String

    public init(section: AnalysisSection, title: String, content: String) {
        self.section = section
        self.title = title
        self.content = content
    }
}

/// A complete codebase analysis report rendered as markdown.
public struct AnalysisReport: Sendable {
    public let projectName: String
    public let sections: [SectionResult]

    public init(projectName: String, sections: [SectionResult]) {
        self.projectName = projectName
        self.sections = sections
    }

    public func renderMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Codebase Analysis: \(projectName)")
        lines.append("")

        if sections.count > 1 {
            lines.append("## Table of Contents")
            lines.append("")
            for (i, section) in sections.enumerated() {
                let anchor = section.title.lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "&", with: "")
                    .replacingOccurrences(of: "  ", with: "-")
                lines.append("\(i + 1). [\(section.title)](#\(anchor))")
            }
            lines.append("")
        }

        for section in sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
