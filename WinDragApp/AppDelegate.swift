import Cocoa

/// Main application delegate
/// Manages the status bar icon, menu, and application lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem?
    private var mainWindowController: MainWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("✅ Application launched from: \(Bundle.main.bundlePath)")
        appLog("   Process ID: \(ProcessInfo.processInfo.processIdentifier)")
        
        // Setup status bar icon
        setupStatusBar()
        
        // Check and request accessibility permissions
        let trusted = checkAndRequestAccessibilityPermission()
        appLog("   Accessibility permission: \(trusted)")
        
        // Start drag manager if enabled AND we have permission
        if trusted && Settings.shared.isEnabled {
            appLog("   Starting DragLockManager...")
            DragLockManager.shared.start()
        } else {
            appLog("   NOT starting DragLockManager - trusted:\(trusted) isEnabled:\(Settings.shared.isEnabled)")
        }
        
        // Show main settings window
        showMainWindow()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        DragLockManager.shared.stop()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    // MARK: - Status Bar
    
    /// Setup the menu bar status item with icon and menu
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use emoji as icon since SF Symbols may not be available
            button.title = "🖐"
        }
        
        let menu = NSMenu()
        
        let enableItem = NSMenuItem(title: "Enable Drag", action: #selector(toggleEnabled(_:)), keyEquivalent: "e")
        enableItem.state = Settings.shared.isEnabled ? .on : .off
        menu.addItem(enableItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showMainWindow), keyEquivalent: ","))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        print("✅ Status bar setup complete")
    }
    
    /// Toggle the drag feature on/off
    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Settings.shared.isEnabled.toggle()
        sender.state = Settings.shared.isEnabled ? .on : .off
        
        if Settings.shared.isEnabled {
            DragLockManager.shared.start()
        } else {
            DragLockManager.shared.stop()
        }
        
        // Notify main window to update UI
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
    }
    
    /// Show the main settings window
    @objc func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Quit the application
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Accessibility
    
    /// Check if accessibility permissions are granted and prompt if not
    /// Returns true if trusted, false otherwise
    private func checkAndRequestAccessibilityPermission() -> Bool {
        // First check without prompting
        let trustedWithoutPrompt = AXIsProcessTrusted()
        appLog("📋 Initial accessibility check: \(trustedWithoutPrompt)")
        
        if !trustedWithoutPrompt {
            // Show prompt to user
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "WinDragApp needs accessibility permissions to intercept trackpad events.\n\n1. Go to System Settings > Privacy & Security > Accessibility\n2. Make sure WinDragApp is checked\n3. Restart the app after granting permission"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // Open System Settings to Accessibility
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            
            appLog("⚠️ Accessibility permission required - prompted user")
            return false
        } else {
            appLog("✅ Accessibility permission granted")
            return true
        }
    }
    
    /// Legacy method for compatibility
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !trusted {
            print("⚠️ Accessibility permission required for proper operation")
        } else {
            print("✅ Accessibility permission granted")
        }
    }
}

// MARK: - Main Entry Point
@main
struct WinDragApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
