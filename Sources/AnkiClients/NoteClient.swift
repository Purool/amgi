//
//  NoteClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

public import AnkiKit
public import Dependencies
import DependenciesMacros
import AnkiBackend
import AnkiServices

@DependencyClient
public struct NoteClient: Sendable {
    public var fetch: @Sendable (_ noteId: NoteID) async throws -> NoteRecord?
    /// Browser-friendly search — returns the first 50 hits with full
    /// fields and the rest as lazy placeholders ("Loading…" sfld) so the
    /// list doesn't stall on large results. Callers that need every
    /// record's real content (e.g. the reader's chapter loader) must
    /// use `searchAll` instead.
    public var search: @Sendable (_ query: String, _ limit: Int?) async throws -> [NoteRecord]
    /// Eager search — returns full NoteRecords for every hit, no lazy
    /// placeholders. Slower for large results but required when the
    /// caller reads `flds` immediately.
    public var searchAll: @Sendable (_ query: String, _ limit: Int?) async throws -> [NoteRecord]
    public var save: @Sendable (_ note: NoteRecord) async throws -> Void
    public var delete: @Sendable (_ noteId: NoteID) async throws -> Void
    public var findDuplicates: @Sendable () async throws -> [DuplicateGroup]
    public var fieldNamesForNotes: @Sendable (_ noteIDs: [NoteID]) async throws -> [String]
    // Empty `noteIDs` replaces across the whole collection; empty `fieldName` means every field.
    public var findAndReplace: @Sendable (
        _ noteIDs: [NoteID], _ search: String, _ replacement: String,
        _ regex: Bool, _ matchCase: Bool, _ fieldName: String
    ) async throws -> Int
}

extension NoteClient: TestDependencyKey {
    public static let testValue = NoteClient()
}

extension DependencyValues {
    public var noteClient: NoteClient {
        get { self[NoteClient.self] }
        set { self[NoteClient.self] = newValue }
    }
}

extension NoteClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.notesService) var notes

        return Self(
            fetch: { noteId in
                try await backendOffload { try notes.getNote(noteId) }
            },
            search: { query, limit in
                try await backendOffload {
                    let ids = try notes.searchNoteIds(query)
                    let bounded = Array(ids.prefix(limit ?? 5000))

                    let firstPageSize = min(bounded.count, 50)
                    var results: [NoteRecord] = []
                    results.reserveCapacity(bounded.count)

                    for nid in bounded.prefix(firstPageSize) {
                        if let note = try? notes.getNote(nid) {
                            results.append(note)
                        }
                    }

                    for nid in bounded.dropFirst(firstPageSize) {
                        results.append(NoteRecord(
                            id: nid, guid: "", mid: NotetypeID(0), mod: 0,
                            tags: "", flds: "", sfld: "Loading...", csum: 0
                        ))
                    }

                    return results
                }
            },
            searchAll: { query, limit in
                try await backendOffload {
                    let ids = try notes.searchNoteIds(query)
                    let bounded = Array(ids.prefix(limit ?? Int.max))
                    var results: [NoteRecord] = []
                    results.reserveCapacity(bounded.count)
                    // No lazy placeholders — every record gets a real
                    // backend fetch. Skips IDs that fail to load (deleted
                    // or otherwise unreachable) rather than aborting the
                    // whole batch.
                    for nid in bounded {
                        if let note = try? notes.getNote(nid) {
                            results.append(note)
                        }
                    }
                    return results
                }
            },
            save: { note in
                try await backendOffload { try notes.saveNote(note) }
            },
            delete: { noteId in
                try await backendOffload { try notes.deleteNote(noteId) }
            },
            findDuplicates: {
                try await backendOffload { try notes.findDuplicates() }
            },
            fieldNamesForNotes: { noteIDs in
                try await backendOffload { try notes.fieldNamesForNotes(noteIDs) }
            },
            findAndReplace: { noteIDs, search, replacement, regex, matchCase, fieldName in
                try await backendOffload {
                    try notes.findAndReplace(noteIDs, search, replacement, regex, matchCase, fieldName)
                }
            }
        )
    }()
}
