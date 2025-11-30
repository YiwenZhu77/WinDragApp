import Foundation

/// Application settings manager
/// Persists user preferences using UserDefaults
class Settings {
    static let shared = Settings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let doubleTapWindow = "doubleTapWindow"
        static let liftDetectionDelay = "liftDetectionDelay"
        static let trackpadOnly = "trackpadOnly"
    }
    
    /// Whether the double-tap drag feature is enabled
    var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }
    
    /// Time window for detecting double-tap (in seconds)
    /// User must perform second tap within this duration after first tap
    var doubleTapWindow: TimeInterval {
        get { defaults.object(forKey: Keys.doubleTapWindow) as? TimeInterval ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.doubleTapWindow) }
    }
    
    /// Delay before detecting finger lift (in seconds)
    /// If no movement is detected for this duration, drag is released
    var liftDetectionDelay: TimeInterval {
        get { defaults.object(forKey: Keys.liftDetectionDelay) as? TimeInterval ?? 0.15 }
        set { defaults.set(newValue, forKey: Keys.liftDetectionDelay) }
    }
    
    /// Whether to only respond to trackpad events (ignore mouse when connected)
    var trackpadOnly: Bool {
        get { defaults.object(forKey: Keys.trackpadOnly) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.trackpadOnly) }
    }
    
    private init() {}
}
