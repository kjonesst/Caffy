import SwiftData

extension PersistentModel {
    /// `false` once the object has been deleted. A view holding a model can be
    /// redrawn once more after a sync deletes it, before its list drops it,
    /// and reading a deleted (and saved) object's attributes crashes
    /// SwiftData. Views check this before reading anything.
    var isLive: Bool {
        modelContext != nil && !isDeleted
    }
}
