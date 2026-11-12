import SwiftData

extension PersistentModel {
    /// Sets `keyPath` to `value`, but only when it's different.
    ///
    /// SwiftData counts every assignment as a change, even of an equal
    /// value: the object is saved again and every view showing it redraws.
    /// A sync copies every era and moment each time, so it goes through this.
    func assign<Value: Equatable>(_ value: Value, to keyPath: ReferenceWritableKeyPath<Self, Value>) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
