import Foundation

extension Collection {
    /// Bounds-checked read used by list screens when an index may outlive a
    /// reload. Returns nil rather than trapping.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
