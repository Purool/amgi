import AnkiKit

/// Editable copy of one note. Only `flds` and `tags` are written back: the
/// engine recomputes `sfld`/`csum` from the notetype's sort field (E14), and
/// it canonifies tags itself (E18).
struct NoteDraft {
    let baseline: NoteRecord
    let notetype: Notetype

    /// Always exactly `notetype.fields.count` long (E13).
    var fields: [String]
    var tags: String

    private let baselineFields: [String]

    init(note: NoteRecord, notetype: Notetype) {
        self.baseline = note
        self.notetype = notetype
        let parsed = note.flds
            .split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map(String.init)
        let aligned = Self.aligned(parsed, to: notetype.fields.count)
        self.fields = aligned
        self.baselineFields = aligned
        self.tags = Self.normalizedTags(note.tags)
    }

    var fieldNames: [String] { notetype.fields.map(\.name) }

    var isDirty: Bool {
        fields != baselineFields || tags != Self.normalizedTags(baseline.tags)
    }

    /// E15: the engine happily stores an all-empty note but generates zero
    /// cards, so saving one must be refused here.
    func validate() -> String? {
        if fields.count != notetype.fields.count {
            return "This note has \(fields.count) fields but the notetype expects \(notetype.fields.count)."
        }
        let first = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if first.isEmpty {
            return "\(fieldNames.first ?? "The first field") can't be empty — it would create a note with no cards."
        }
        return nil
    }

    func apply() -> NoteRecord {
        var note = baseline
        note.flds = fields.joined(separator: "\u{1F}")
        note.tags = Self.normalizedTags(tags)
        // Deliberately untouched: sfld, csum.
        return note
    }

    /// Splits on whitespace and drops empties/duplicates, keeping first-seen
    /// order. The engine would canonify further; this only keeps the field
    /// tidy and predictable.
    static func normalizedTags(_ raw: String) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for token in raw.split(whereSeparator: { $0.isWhitespace }) {
            let tag = String(token)
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result.joined(separator: " ")
    }

    static func aligned(_ fields: [String], to count: Int) -> [String] {
        if fields.count == count { return fields }
        if fields.count > count { return Array(fields.prefix(count)) }
        return fields + Array(repeating: "", count: count - fields.count)
    }
}
