import Foundation

/// Application settings manager
/// Persists user preferences using UserDefaults
final class Settings {
    
    static let shared = Settings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let doubleTapWindow = "doubleTapWindow"
    }
    
    /// Whether the double-tap drag feature is enabled
    var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }
    
    /// Time window for detecting double-tap (in seconds)
    /// Default: 0.5 seconds (500ms)
    var doubleTapWindow: TimeInterval {
        get { defaults.object(forKey: Keys.doubleTapWindow) as? TimeInterval ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.doubleTapWindow) }
    }
    
    private init() {}
}
