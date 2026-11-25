import AnkiKit

/// Working copy of one notetype. The editor mutates only templates in this
/// round; field mutation helpers exist for the P1 fields screen and for the
/// structural-change tests.
struct NotetypeDraft {
    let baseline: Notetype
    var notetype: Notetype

    init(_ notetype: Notetype) {
        self.baseline = notetype
        self.notetype = notetype
    }

    // MARK: - Templates

    var templates: [Notetype.Template] { notetype.templates }

    func template(at index: Int) -> Notetype.Template? {
        guard templates.indices.contains(index) else { return nil }
        return templates[index]
    }

    mutating func updateTemplate(at index: Int, _ body: (inout Notetype.Template) -> Void) {
        guard notetype.templates.indices.contains(index) else { return }
        body(&notetype.templates[index])
    }

    mutating func appendTemplate(named name: String) {
        // `ord = nil` tells the engine to append and assign the next ordinal.
        notetype.templates.append(.init(ord: nil, name: name))
    }

    mutating func removeTemplate(at index: Int) {
        guard notetype.templates.indices.contains(index) else { return }
        notetype.templates.remove(at: index)
    }

    // MARK: - Fields

    var fieldNames: [String] { notetype.fields.map(\.name) }

    /// Appends a field. E1: a new field must carry `ord == nil`; the engine
    /// assigns the next ordinal and appends it at the end.
    @discardableResult
    mutating func appendField(named name: String) -> Notetype.Field {
        let field = Notetype.Field(ord: nil, name: name)
        notetype.fields.append(field)
        return field
    }

    mutating func removeField(at index: Int) {
        guard notetype.fields.indices.contains(index) else { return }
        notetype.fields.remove(at: index)
    }

    mutating func moveField(from source: Int, to destination: Int) {
        guard
            notetype.fields.indices.contains(source),
            destination >= 0,
            destination <= notetype.fields.count
        else { return }
        let field = notetype.fields.remove(at: source)
        let target = min(destination, notetype.fields.count)
        notetype.fields.insert(field, at: target)
    }

    // MARK: - Output

    func apply() -> Notetype { notetype }

    var isDirty: Bool { notetype != baseline }

    /// Fields/templates added, removed or reordered force a full sync (E2).
    /// Renaming a template or editing its text does not.
    var hasStructuralChange: Bool {
        if notetype.fields.map(\.name) != baseline.fields.map(\.name) {
            return true
        }
        if notetype.templates.count != baseline.templates.count {
            return true
        }
        // Template ordinals are positional: any explicit ordinal that differs
        // from the index means the order changed.
        for (index, template) in notetype.templates.enumerated() {
            if let ord = template.ord, ord != index {
                return true
            }
        }
        return false
    }

    /// True when the draft has fields the saved notetype lacks — their
    /// `{{Field}}` references cannot render until those fields are saved (E4).
    var hasUnsavedNewFields: Bool {
        notetype.fields.count > baseline.fields.count
    }

    var validationMessage: String? {
        templateValidationMessage(for: notetype)
    }

    /// Insertion tokens offered above the keyboard.
    var fieldTokens: [String] {
        notetype.fields.map { "{{\($0.name)}}" } + ["{{FrontSide}}"]
    }
}
