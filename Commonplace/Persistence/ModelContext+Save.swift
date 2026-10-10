import Foundation
import SwiftData

extension PersistentModel {
    /// Whether the model can still be read. A view can outlive its model for a moment after a
    /// permanent delete, and reading a deleted model's properties traps.
    var isAvailable: Bool {
        modelContext != nil && !isDeleted
    }
}

extension ModelContext {
    /// Saves after a user action so the change reaches the store, and CloudKit, promptly.
    ///
    /// On failure the pending changes are rolled back, so the screen keeps showing what is
    /// actually stored.
    ///
    /// - Returns: `nil` on success, or the error message to show.
    func saveOrRollback() -> String? {
        do {
            try save()
            return nil
        } catch {
            rollback()
            return error.localizedDescription
        }
    }
}
