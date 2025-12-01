import Cocoa

/// Main application delegate
/// Manages the status bar icon, menu, and application lifecycle
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem?
    private var mainWindowController: MainWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        
        // Start drag manager if enabled AND we have permission
        if AXIsProcessTrusted() && Settings.shared.isEnabled {
            DragLockManager.shared.doubleTapWindow = Settings.shared.doubleTapWindow
            DragLockManager.shared.start()
        }
        
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
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use custom menu bar icon, fallback to emoji
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "🖐"
            }
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
    }
    
    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        Settings.shared.isEnabled.toggle()
        sender.state = Settings.shared.isEnabled ? .on : .off
        
        if Settings.shared.isEnabled {
            DragLockManager.shared.doubleTapWindow = Settings.shared.doubleTapWindow
            DragLockManager.shared.start()
        } else {
            DragLockManager.shared.stop()
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
    }
    
    @objc func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
