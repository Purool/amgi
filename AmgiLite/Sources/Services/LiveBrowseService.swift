import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import Foundation

struct LiveBrowseService: BrowseServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func searchNotes(query: String, limit: Int) async throws -> [NoteSummary] {
        let backend = self.backend
        try requireCollectionOpen(state)
        let ids: [NoteID] = try await backendOffload {
            try backend.invoke(.searchNoteIds(query: query))
        }

        // The engine exposes a single-note read, not a batch one. Page size is
        // what bounds this loop; 50 notes at ~1 ms per RPC is imperceptible.
        var summaries: [NoteSummary] = []
        summaries.reserveCapacity(min(ids.count, max(0, limit)))
        for id in ids.prefix(max(0, limit)) {
            let note: NoteRecord = try await backendOffload {
                try backend.invoke(.getNote(id: id))
            }
            summaries.append(NoteSummary(note: note))
        }
        return summaries
    }

    func note(id: NoteID) async throws -> NoteRecord {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.getNote(id: id))
        }
    }
}

extension NoteSummary {
    /// Anki joins note fields with U+001F. `sfld` is the sort field, which is
    /// what the browser shows as the row title.
    init(note: NoteRecord) {
        let fields = note.flds
            .split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map(String.init)

        let title = note.sfld.isEmpty ? (fields.first ?? "") : note.sfld
        let secondary = fields.dropFirst().joined(separator: " · ")

        self.init(
            id: note.id,
            title: Self.plainText(title),
            snippet: Self.plainText(secondary)
        )
    }

    private static let tagExpression = try? NSRegularExpression(pattern: "<[^>]+>", options: [])

    static func plainText(_ html: String) -> String {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let stripped = tagExpression?.stringByReplacingMatches(
            in: html,
            options: [],
            range: range,
            withTemplate: " "
        ) ?? html

        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
