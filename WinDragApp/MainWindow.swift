import Cocoa

/// Main settings window controller
final class MainWindowController: NSWindowController {
    
    private var enabledCheckbox: NSButton!
    private var doubleTapTextField: NSTextField!
    private var statusLabel: NSTextField!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinDrag Settings"
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        setupUI()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: NSNotification.Name("SettingsChanged"), object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Title
        let titleLabel = NSTextField(labelWithString: "WinDrag")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 24)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Double-tap to drag, tap again to release")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        
        // Enable checkbox
        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Double-Tap Drag", target: self, action: #selector(toggleEnabled(_:)))
        enabledCheckbox.state = Settings.shared.isEnabled ? .on : .off
        enabledCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(enabledCheckbox)
        
        // Double-tap time window
        let doubleTapLabel = NSTextField(labelWithString: "Double-Tap Window:")
        doubleTapLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(doubleTapLabel)
        
        doubleTapTextField = NSTextField(string: "\(Int(Settings.shared.doubleTapWindow * 1000))")
        doubleTapTextField.translatesAutoresizingMaskIntoConstraints = false
        doubleTapTextField.alignment = .center
        doubleTapTextField.delegate = self
        contentView.addSubview(doubleTapTextField)
        
        let msLabel = NSTextField(labelWithString: "ms (100-1000)")
        msLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(msLabel)
        
        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)
        updateStatusLabel()
        
        // Instructions
        let instructionsLabel = NSTextField(wrappingLabelWithString: """
        How to use:
        1. Tap the trackpad once
        2. Within the time window, tap again or start moving
        3. Move your finger to drag
        4. Tap again to release
        
        Only works with trackpad (ignores mouse input).
        Accessibility permission required in System Settings.
        """)
        instructionsLabel.font = NSFont.systemFont(ofSize: 11)
        instructionsLabel.textColor = .secondaryLabelColor
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instructionsLabel)
        
        // Accessibility button
        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(accessibilityButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            enabledCheckbox.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            enabledCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            doubleTapLabel.topAnchor.constraint(equalTo: enabledCheckbox.bottomAnchor, constant: 16),
            doubleTapLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            doubleTapTextField.centerYAnchor.constraint(equalTo: doubleTapLabel.centerYAnchor),
            doubleTapTextField.leadingAnchor.constraint(equalTo: doubleTapLabel.trailingAnchor, constant: 8),
            doubleTapTextField.widthAnchor.constraint(equalToConstant: 60),
            
            msLabel.centerYAnchor.constraint(equalTo: doubleTapLabel.centerYAnchor),
            msLabel.leadingAnchor.constraint(equalTo: doubleTapTextField.trailingAnchor, constant: 8),
            
            statusLabel.topAnchor.constraint(equalTo: doubleTapLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            instructionsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            instructionsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructionsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            accessibilityButton.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 12),
            accessibilityButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            accessibilityButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }
    
    private func updateStatusLabel() {
        statusLabel.stringValue = Settings.shared.isEnabled ? "Status: ✅ Enabled" : "Status: ⏸ Disabled"
    }
    
    @objc private func toggleEnabled(_ sender: NSButton) {
        let wantEnabled = sender.state == .on
        
        if wantEnabled && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            sender.state = .off
            return
        }
        
        Settings.shared.isEnabled = wantEnabled
        
        if wantEnabled {
            DragLockManager.shared.doubleTapWindow = Settings.shared.doubleTapWindow
            DragLockManager.shared.start()
        } else {
            DragLockManager.shared.stop()
        }
        
        updateStatusLabel()
        NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
    }
    
    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func settingsChanged() {
        enabledCheckbox.state = Settings.shared.isEnabled ? .on : .off
        doubleTapTextField.stringValue = "\(Int(Settings.shared.doubleTapWindow * 1000))"
        updateStatusLabel()
    }
}

// MARK: - NSTextFieldDelegate

extension MainWindowController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        let value = Int(textField.stringValue) ?? 500
        let clamped = max(100, min(1000, value))
        textField.stringValue = "\(clamped)"
        
        Settings.shared.doubleTapWindow = TimeInterval(clamped) / 1000.0
        DragLockManager.shared.doubleTapWindow = Settings.shared.doubleTapWindow
    }
}
