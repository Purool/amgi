import AnkiBackend

/// Every engine read/write requires an open collection. Checked against
/// `CollectionState` rather than the backend, whose media path survives close.
func requireCollectionOpen(_ state: CollectionState) throws {
    guard state.isOpen else {
        throw LiteError.collectionNotOpen
    }
}
