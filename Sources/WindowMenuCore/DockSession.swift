import Foundation

public struct DockSnapshot: Codable, Equatable {
    public var originalAutohide: Bool?
    public init(originalAutohide: Bool?) { self.originalAutohide = originalAutohide }
}

public protocol DockPreferenceStore: AnyObject {
    func readAutohide() throws -> Bool?
    func writeAutohide(_ value: Bool?) throws
    func reloadDock() throws
}

public protocol DockRecoveryStore: AnyObject {
    func load() throws -> DockSnapshot?
    func save(_ snapshot: DockSnapshot) throws
    func clear() throws
}

/// Persists recovery information before touching system preferences.
public final class DockSession {
    private let preferences: DockPreferenceStore
    private let recovery: DockRecoveryStore

    public init(preferences: DockPreferenceStore, recovery: DockRecoveryStore) {
        self.preferences = preferences
        self.recovery = recovery
    }

    public func hide() throws {
        // A pending snapshot must never be replaced by the value we previously applied.
        if try recovery.load() != nil {
            // A prior write or Dock reload may have failed. Retry without replacing its backup.
            if try preferences.readAutohide() != true { try preferences.writeAutohide(true) }
            try preferences.reloadDock()
            return
        }
        let original = try preferences.readAutohide()
        if original == true { return }
        try recovery.save(DockSnapshot(originalAutohide: original))
        try preferences.writeAutohide(true)
        try preferences.reloadDock()
    }

    public func restore() throws {
        guard let snapshot = try recovery.load() else { return }
        // Respect a newer change made by the user in System Settings.
        if try preferences.readAutohide() == true {
            try preferences.writeAutohide(snapshot.originalAutohide)
        }
        // Retry a failed reload even if a previous attempt already wrote the original value.
        try preferences.reloadDock()
        try recovery.clear()
    }
}
