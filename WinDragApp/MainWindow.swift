import Cocoa

/// Main settings window controller
/// Provides UI for configuring double-tap drag behavior
class MainWindowController: NSWindowController {
    
    private var enabledCheckbox: NSButton!
    private var trackpadOnlyCheckbox: NSButton!
    private var doubleTapSlider: NSSlider!
    private var doubleTapTextField: NSTextField!
    private var liftDelaySlider: NSSlider!
    private var liftDelayTextField: NSTextField!
    private var statusLabel: NSTextField!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinDrag - Double-Tap Drag"
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        setupUI()
        
        // Listen for settings changes from other sources (e.g., menu bar)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Setup all UI elements
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        contentView.wantsLayer = true
        
        // Title
        let titleLabel = NSTextField(labelWithString: "WinDrag")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 24)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = NSTextField(labelWithString: "Double-tap trackpad to drag, lift finger to release")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        
        // Enable checkbox
        enabledCheckbox = NSButton(checkboxWithTitle: "Enable Double-Tap Drag", target: self, action: #selector(toggleEnabled(_:)))
        enabledCheckbox.state = Settings.shared.isEnabled ? .on : .off
        enabledCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(enabledCheckbox)
        
        // Trackpad only checkbox
        trackpadOnlyCheckbox = NSButton(checkboxWithTitle: "Trackpad Only (disable when mouse connected)", target: self, action: #selector(toggleTrackpadOnly(_:)))
        trackpadOnlyCheckbox.state = Settings.shared.trackpadOnly ? .on : .off
        trackpadOnlyCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(trackpadOnlyCheckbox)
        
        // Double-tap time window
        let doubleTapTitleLabel = NSTextField(labelWithString: "Double-Tap Window:")
        doubleTapTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(doubleTapTitleLabel)
        
        // Slider with 50ms steps (100-1000ms, so 18 tick marks)
        doubleTapSlider = NSSlider(value: Settings.shared.doubleTapWindow * 1000, minValue: 100, maxValue: 1000, target: self, action: #selector(doubleTapSliderChanged(_:)))
        doubleTapSlider.numberOfTickMarks = 19  // (1000-100)/50 + 1 = 19
        doubleTapSlider.allowsTickMarkValuesOnly = true
        doubleTapSlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(doubleTapSlider)
        
        // Editable text field for double-tap window
        doubleTapTextField = NSTextField(string: "\(Int(Settings.shared.doubleTapWindow * 1000))")
        doubleTapTextField.translatesAutoresizingMaskIntoConstraints = false
        doubleTapTextField.alignment = .center
        doubleTapTextField.delegate = self
        doubleTapTextField.tag = 1  // Tag to identify this field
        contentView.addSubview(doubleTapTextField)
        
        let doubleTapUnitLabel = NSTextField(labelWithString: "ms")
        doubleTapUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(doubleTapUnitLabel)
        
        // Lift detection delay
        let liftDelayTitleLabel = NSTextField(labelWithString: "Lift Detection Delay:")
        liftDelayTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liftDelayTitleLabel)
        
        // Slider with 50ms steps (50-500ms, so 10 tick marks)
        liftDelaySlider = NSSlider(value: Settings.shared.liftDetectionDelay * 1000, minValue: 50, maxValue: 500, target: self, action: #selector(liftDelaySliderChanged(_:)))
        liftDelaySlider.numberOfTickMarks = 10  // (500-50)/50 + 1 = 10
        liftDelaySlider.allowsTickMarkValuesOnly = true
        liftDelaySlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liftDelaySlider)
        
        // Editable text field for lift delay
        liftDelayTextField = NSTextField(string: "\(Int(Settings.shared.liftDetectionDelay * 1000))")
        liftDelayTextField.translatesAutoresizingMaskIntoConstraints = false
        liftDelayTextField.alignment = .center
        liftDelayTextField.delegate = self
        liftDelayTextField.tag = 2  // Tag to identify this field
        contentView.addSubview(liftDelayTextField)
        
        let liftDelayUnitLabel = NSTextField(labelWithString: "ms")
        liftDelayUnitLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(liftDelayUnitLabel)
        
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
        4. Lift your finger to release
        
        Note: Drag stops when no movement is detected for the lift delay duration.
        
        Accessibility permission is required in System Settings.
        """)
        instructionsLabel.font = NSFont.systemFont(ofSize: 11)
        instructionsLabel.textColor = .secondaryLabelColor
        instructionsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(instructionsLabel)
        
        // Open accessibility settings button
        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(accessibilityButton)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            enabledCheckbox.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            enabledCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            trackpadOnlyCheckbox.topAnchor.constraint(equalTo: enabledCheckbox.bottomAnchor, constant: 8),
            trackpadOnlyCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            doubleTapTitleLabel.topAnchor.constraint(equalTo: trackpadOnlyCheckbox.bottomAnchor, constant: 16),
            doubleTapTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            doubleTapTitleLabel.widthAnchor.constraint(equalToConstant: 130),
            
            doubleTapSlider.centerYAnchor.constraint(equalTo: doubleTapTitleLabel.centerYAnchor),
            doubleTapSlider.leadingAnchor.constraint(equalTo: doubleTapTitleLabel.trailingAnchor, constant: 8),
            doubleTapSlider.widthAnchor.constraint(equalToConstant: 120),
            
            doubleTapTextField.centerYAnchor.constraint(equalTo: doubleTapTitleLabel.centerYAnchor),
            doubleTapTextField.leadingAnchor.constraint(equalTo: doubleTapSlider.trailingAnchor, constant: 8),
            doubleTapTextField.widthAnchor.constraint(equalToConstant: 50),
            
            doubleTapUnitLabel.centerYAnchor.constraint(equalTo: doubleTapTitleLabel.centerYAnchor),
            doubleTapUnitLabel.leadingAnchor.constraint(equalTo: doubleTapTextField.trailingAnchor, constant: 4),
            
            liftDelayTitleLabel.topAnchor.constraint(equalTo: doubleTapTitleLabel.bottomAnchor, constant: 12),
            liftDelayTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            liftDelayTitleLabel.widthAnchor.constraint(equalToConstant: 130),
            
            liftDelaySlider.centerYAnchor.constraint(equalTo: liftDelayTitleLabel.centerYAnchor),
            liftDelaySlider.leadingAnchor.constraint(equalTo: liftDelayTitleLabel.trailingAnchor, constant: 8),
            liftDelaySlider.widthAnchor.constraint(equalToConstant: 120),
            
            liftDelayTextField.centerYAnchor.constraint(equalTo: liftDelayTitleLabel.centerYAnchor),
            liftDelayTextField.leadingAnchor.constraint(equalTo: liftDelaySlider.trailingAnchor, constant: 8),
            liftDelayTextField.widthAnchor.constraint(equalToConstant: 50),
            
            liftDelayUnitLabel.centerYAnchor.constraint(equalTo: liftDelayTitleLabel.centerYAnchor),
            liftDelayUnitLabel.leadingAnchor.constraint(equalTo: liftDelayTextField.trailingAnchor, constant: 4),
            
            statusLabel.topAnchor.constraint(equalTo: liftDelayTitleLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            instructionsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            instructionsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructionsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            accessibilityButton.topAnchor.constraint(equalTo: instructionsLabel.bottomAnchor, constant: 12),
            accessibilityButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            accessibilityButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }
    
    /// Update the status label based on current enabled state
    private func updateStatusLabel() {
        let status = Settings.shared.isEnabled ? "✅ Enabled" : "⏸ Disabled"
        statusLabel.stringValue = "Status: \(status)"
    }
    
    /// Toggle the drag feature on/off
    @objc private func toggleEnabled(_ sender: NSButton) {
        let wantEnabled = sender.state == .on
        
        if wantEnabled {
            // Check accessibility permission first
            let trusted = AXIsProcessTrusted()
            if !trusted {
                // Show permission dialog
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                
                // Show alert
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Please grant accessibility permission in System Settings, then try enabling again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                // Revert checkbox state
                sender.state = .off
                return
            }
            
            DragLockManager.shared.start()
        } else {
            DragLockManager.shared.stop()
        }
        
        Settings.shared.isEnabled = wantEnabled
        updateStatusLabel()
    }
    
    /// Toggle trackpad-only mode
    @objc private func toggleTrackpadOnly(_ sender: NSButton) {
        Settings.shared.trackpadOnly = sender.state == .on
    }
    
    /// Handle double-tap window slider change
    @objc private func doubleTapSliderChanged(_ sender: NSSlider) {
        // Snap to 50ms steps
        let snappedValue = round(sender.doubleValue / 50) * 50
        sender.doubleValue = snappedValue
        let value = snappedValue / 1000.0
        Settings.shared.doubleTapWindow = value
        doubleTapTextField.stringValue = "\(Int(snappedValue))"
    }
    
    /// Handle lift detection delay slider change
    @objc private func liftDelaySliderChanged(_ sender: NSSlider) {
        // Snap to 50ms steps
        let snappedValue = round(sender.doubleValue / 50) * 50
        sender.doubleValue = snappedValue
        let value = snappedValue / 1000.0
        Settings.shared.liftDetectionDelay = value
        liftDelayTextField.stringValue = "\(Int(snappedValue))"
    }
    
    /// Open System Settings > Accessibility
    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    /// Handle settings changed notification from other sources
    @objc private func settingsChanged() {
        enabledCheckbox.state = Settings.shared.isEnabled ? .on : .off
        updateStatusLabel()
    }
}

// MARK: - NSTextFieldDelegate
extension MainWindowController: NSTextFieldDelegate {
    /// Handle text field value changes (when user presses Enter or field loses focus)
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        if textField.tag == 1 {
            // Double-tap window text field
            if let value = Int(textField.stringValue), value >= 100, value <= 1000 {
                // Snap to 50ms steps
                let snappedValue = Double(round(Double(value) / 50) * 50)
                Settings.shared.doubleTapWindow = snappedValue / 1000.0
                doubleTapSlider.doubleValue = snappedValue
                textField.stringValue = "\(Int(snappedValue))"
            } else {
                // Invalid input, reset to current value
                textField.stringValue = "\(Int(Settings.shared.doubleTapWindow * 1000))"
            }
        } else if textField.tag == 2 {
            // Lift delay text field
            if let value = Int(textField.stringValue), value >= 50, value <= 500 {
                // Snap to 50ms steps
                let snappedValue = Double(round(Double(value) / 50) * 50)
                Settings.shared.liftDetectionDelay = snappedValue / 1000.0
                liftDelaySlider.doubleValue = snappedValue
                textField.stringValue = "\(Int(snappedValue))"
            } else {
                // Invalid input, reset to current value
                textField.stringValue = "\(Int(Settings.shared.liftDetectionDelay * 1000))"
            }
        }
    }
}

// Helper type alias for NSTextField used as label
typealias NSLabel = NSTextField
