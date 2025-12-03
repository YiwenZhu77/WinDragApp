import Foundation

/// How to stop dragging
enum StopMode: Int {
    case tapAgain = 0    // Tap/click to stop
    case delayTime = 1   // Stop after delay when finger lifts
}

/// Application settings manager
/// Persists user preferences using UserDefaults
final class Settings {
    
    static let shared = Settings()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let isEnabled = "isEnabled"
        static let doubleTapWindow = "doubleTapWindow"
        static let stopMode = "stopMode"
        static let liftDelay = "liftDelay"
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
    
    /// How to stop dragging: tap again or delay time
    var stopMode: StopMode {
        get { StopMode(rawValue: defaults.integer(forKey: Keys.stopMode)) ?? .tapAgain }
        set { defaults.set(newValue.rawValue, forKey: Keys.stopMode) }
    }
    
    /// Delay time before stopping drag after finger lifts (seconds)
    /// Default: 0.5 seconds (500ms)
    var liftDelay: TimeInterval {
        get { defaults.object(forKey: Keys.liftDelay) as? TimeInterval ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.liftDelay) }
    }
    
    private init() {}
}
