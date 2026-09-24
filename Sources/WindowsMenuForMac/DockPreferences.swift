import Foundation
import WindowMenuCore

enum SettingsError: LocalizedError {
    case saveFailed
    case reloadFailed
    var errorDescription: String? {
        switch self {
        case .saveFailed: return "設定を保存できませんでした。システム設定の「デスクトップとDock」から確認してください。"
        case .reloadFailed: return "Dockを再読み込みできませんでした。復元情報は保存されています。設定画面から復元を再試行できます。"
        }
    }
}

final class SystemDockPreferences: DockPreferenceStore {
    private let domain = "com.apple.dock" as CFString
    private let key = "autohide" as CFString

    func readAutohide() throws -> Bool? {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw SettingsError.saveFailed }
        return CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
    }

    func writeAutohide(_ value: Bool?) throws {
        CFPreferencesSetValue(key, value.map { NSNumber(value: $0) }, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw SettingsError.saveFailed }
    }

    func reloadDock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", NSUserName(), "Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SettingsError.reloadFailed }
    }
}

final class SavedDockRecovery: DockRecoveryStore {
    private let defaults: UserDefaults
    private let key = "dockRecoverySnapshot"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> DockSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(DockSnapshot.self, from: data)
    }

    func save(_ snapshot: DockSnapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
        guard defaults.synchronize() else { throw SettingsError.saveFailed }
    }

    func clear() throws {
        defaults.removeObject(forKey: key)
        guard defaults.synchronize() else { throw SettingsError.saveFailed }
    }
}
