//
//  ImageOcclusionClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 28.04.2026.
//

public import AnkiKit
public import Dependencies
import DependenciesMacros
public import Foundation
import AnkiBackend
import AnkiProtoBridge

@DependencyClient
public struct ImageOcclusionClient: Sendable {
    /// Creates an image occlusion note from the given source image path.
    /// The client is responsible for selecting the target deck/current deck state
    /// before delegating to the backend image-occlusion add flow.
    public var addNote: @Sendable (
        _ imageURL: URL,
        _ occlusions: String,
        _ header: String,
        _ backExtra: String,
        _ tags: [String],
        _ deckID: DeckID,
        _ notetypeID: NotetypeID
    ) async throws -> Void

    /// Fetches an existing image occlusion note for editing.
    /// Returns (imageData, imageName, occlusions, header, backExtra, tags).
    public var getNote: @Sendable (_ noteId: NoteID) async throws -> ImageOcclusionNoteData

    /// Updates an existing image occlusion note.
    public var updateNote: @Sendable (
        _ noteId: NoteID,
        _ occlusions: String,
        _ header: String,
        _ backExtra: String,
        _ tags: [String]
    ) async throws -> Void
}

extension ImageOcclusionClient: TestDependencyKey {
    public static let testValue = ImageOcclusionClient()
}

extension DependencyValues {
    public var imageOcclusionClient: ImageOcclusionClient {
        get { self[ImageOcclusionClient.self] }
        set { self[ImageOcclusionClient.self] = newValue }
    }
}

extension ImageOcclusionClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            addNote: { imageURL, occlusions, header, backExtra, tags, deckID, notetypeID in
                try await backendOffload {
                    // 1. Ensure the notetype exists.
                    try backend.invoke(.addImageOcclusionNotetype)

                    // 2. IO note creation saves into the backend's current deck.
                    try backend.invoke(.setCurrentDeck(deckId: deckID))

                    // 3. Let the backend import the selected source file into media.
                    try backend.invoke(.addImageOcclusionNote(
                        imagePath: imageURL.path,
                        occlusions: occlusions,
                        header: header,
                        backExtra: backExtra,
                        tags: tags,
                        notetypeId: notetypeID
                    ))
                }
            },

            getNote: { noteId in
                try await backend.invoke(.getImageOcclusionNote(noteId: noteId))
            },

            updateNote: { noteId, occlusions, header, backExtra, tags in
                try await backend.invoke(.updateImageOcclusionNote(
                    noteId: noteId,
                    occlusions: occlusions,
                    header: header,
                    backExtra: backExtra,
                    tags: tags
                ))
            }
        )
    }()
}
