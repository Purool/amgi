import AnkiKit
import Foundation

// Client-side template pre-flight. The engine's `check_templates` is still the
// authority; these rules exist so the obvious mistakes are caught before a
// round trip. Ported from the main app's `TemplatesFeature/TemplateValidation`.

private enum TemplateValidationIssue {
    case noFrontField(templateName: String)
    case noSuchField(templateName: String, fieldName: String)
    case missingCloze
}

private struct TemplateReference {
    let fieldName: String
    let filters: [String]
}

private let templateReferenceRegex = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)

/// Fields the renderer supplies itself; they never need a matching notetype
/// field.
private let specialTemplateFieldNames: Set<String> = [
    "FrontSide",
    "Card",
    "CardFlag",
    "Deck",
    "Subdeck",
    "Tags",
    "Type",
    "CardID",
]

func templateValidationMessage(for notetype: Notetype) -> String? {
    switch templateValidationIssue(for: notetype) {
    case .noFrontField:
        return "The front template must reference at least one field."
    case .noSuchField(_, let fieldName):
        return "Field \"\(fieldName)\" doesn't exist on this notetype."
    case .missingCloze:
        return "This template needs a {{cloze:...}} field."
    case .none:
        return nil
    }
}

private func templateValidationIssue(for notetype: Notetype) -> TemplateValidationIssue? {
    let availableFieldNames = Set(notetype.fields.map(\.name))

    for template in notetype.templates {
        let frontReferences = extractTemplateReferences(from: template.config.qFormat)
        let backReferences = extractTemplateReferences(from: template.config.aFormat)

        if frontReferences.isEmpty {
            return .noFrontField(templateName: template.name)
        }

        if let unknownField = (frontReferences + backReferences)
            .map(\.fieldName)
            .first(where: { fieldName in
                !fieldName.isEmpty
                    && !specialTemplateFieldNames.contains(fieldName)
                    && !availableFieldNames.contains(fieldName)
            }) {
            return .noSuchField(templateName: template.name, fieldName: unknownField)
        }
    }

    if notetype.config.kind == .cloze {
        guard let firstTemplate = notetype.templates.first else {
            return .missingCloze
        }

        let frontHasCloze = extractTemplateReferences(from: firstTemplate.config.qFormat)
            .contains(where: containsClozeFilter)
        let backHasCloze = extractTemplateReferences(from: firstTemplate.config.aFormat)
            .contains(where: containsClozeFilter)

        if !frontHasCloze || !backHasCloze {
            return .missingCloze
        }
    }

    return nil
}

private func extractTemplateReferences(from source: String) -> [TemplateReference] {
    let range = NSRange(source.startIndex..., in: source)
    return templateReferenceRegex.matches(in: source, range: range).compactMap { match in
        guard
            match.numberOfRanges > 1,
            let contentRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        var content = source[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            return TemplateReference(fieldName: "", filters: [])
        }

        if let first = content.first, ["#", "^", "/"].contains(first) {
            content.removeFirst()
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let components = content
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let fieldName = components.last else { return nil }

        return TemplateReference(
            fieldName: fieldName,
            filters: Array(components.dropLast())
        )
    }
}

private func containsClozeFilter(_ reference: TemplateReference) -> Bool {
    reference.filters.contains { $0.caseInsensitiveCompare("cloze") == .orderedSame }
}

// MARK: - Preview sample helpers

/// Splits Anki's U+001F-separated field blob.
func buildSampleFields(from note: NoteRecord) -> [String] {
    note.flds
        .split(separator: "\u{1F}", omittingEmptySubsequences: false)
        .map(String.init)
}

/// Placeholder for previewing before any real note exists.
func makeEmptySampleFields(fieldCount: Int) -> [String] {
    Array(repeating: "", count: max(fieldCount, 0))
}

func sortedNotetypeNames(_ entries: [NotetypeNameId]) -> [NotetypeNameId] {
    entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
