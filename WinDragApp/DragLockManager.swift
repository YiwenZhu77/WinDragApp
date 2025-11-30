import Cocoa
import CoreGraphics
import IOKit
import IOKit.hid

/// Log to both console and file
func appLog(_ message: String) {
    print(message)
    
    // Also write to log file
    let logPath = NSHomeDirectory() + "/Library/Logs/WinDragApp.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

/// Double-tap drag manager - supports Tap to Click mode
///
/// How it works (Tap to Click mode):
/// 1. First tap: Normal click, registers the tap location and time
/// 2. Second tap (within time window) OR movement: Enters drag mode
/// 3. Finger moves on trackpad: Dragging
/// 4. Finger lifts from trackpad (detected via no movement timeout): End drag
///
/// The drag stops when no mouse movement is detected for `liftDetectionDelay` duration.
/// This is because macOS doesn't provide direct "finger lifted" events for tap-to-click.
class DragLockManager {
    
    // MARK: - Singleton
    static let shared = DragLockManager()
    
    // MARK: - Types
    
    /// Drag state machine states
    enum DragState: CustomStringConvertible {
        case idle                                               // Not dragging, waiting for first tap
        case waitingForSecondTap(firstTapTime: TimeInterval, location: CGPoint) // First tap detected, waiting for second
        case dragging(lastMoveTime: TimeInterval)               // Currently dragging
        
        var description: String {
            switch self {
            case .idle: return "idle"
            case .waitingForSecondTap: return "waitingForSecondTap"
            case .dragging: return "dragging"
            }
        }
    }
    
    // MARK: - Properties
    
    private var state: DragState = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let settings = Settings.shared
    
    /// Flag: Should ignore the next mouseDown event (because we sent it ourselves)
    private var ignoringNextMouseDown: Bool = false
    
    /// Flag: Should ignore the next mouseUp event (because we sent it ourselves)
    private var ignoringNextMouseUp: Bool = false
    
    /// Timer for detecting finger lift from trackpad
    private var liftDetectionTimer: Timer?
    
    /// Timer for double-tap timeout
    private var doubleTapTimer: Timer?
    
    /// Location where drag started
    private var dragStartLocation: CGPoint = .zero
    
    /// Last recorded mouse movement location
    private var lastMoveLocation: CGPoint = .zero
    
    /// Maximum distance (in points) allowed between taps for double-tap detection
    private let tapMovementThreshold: CGFloat = 50.0
    
    /// Event subtype field key for identifying trackpad vs mouse
    /// kCGMouseEventSubtype = 9
    private let kCGMouseEventSubtype: CGEventField = CGEventField(rawValue: 9)!
    
    /// Subtype value for trackpad events (tablet/touch)
    /// kCGEventMouseSubtypeTabletPoint = 1
    private let kCGEventMouseSubtypeTabletPoint: Int64 = 1
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start the event tap and begin listening for mouse events
    func start() {
        appLog("🔵 DragLockManager.start() called")
        appLog("   - isEnabled: \(settings.isEnabled)")
        appLog("   - eventTap exists: \(eventTap != nil)")
        
        guard settings.isEnabled else { 
            appLog("❌ Not starting - isEnabled is false")
            return 
        }
        guard eventTap == nil else { 
            appLog("⚠️ Not starting - eventTap already exists")
            return 
        }
        
        // Check accessibility permission first
        let trusted = AXIsProcessTrusted()
        appLog("   - Accessibility trusted: \(trusted)")
        
        if !trusted {
            appLog("❌ Accessibility permission NOT granted!")
            appLog("   Please grant permission in System Settings > Privacy & Security > Accessibility")
            return
        }
        
        // Create event tap for mouse events
        // We listen to: mouseDown, mouseUp, mouseDragged, mouseMoved
        let eventMask: CGEventMask = (
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)
        )
        
        appLog("   - Creating event tap with mask: \(eventMask)")
        
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let manager = Unmanaged<DragLockManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            appLog("❌ Failed to create event tap!")
            appLog("   This usually means accessibility permissions are not properly granted.")
            return
        }
        
        appLog("✅ Event tap created successfully")
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            appLog("✅ Run loop source added")
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
        appLog("✅ DragLockManager started (Tap to Click mode)")
    }
    
    /// Stop the event tap and clean up
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        state = .idle
        
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
        liftDetectionTimer?.invalidate()
        liftDetectionTimer = nil
        
        print("⏹ DragLockManager stopped")
    }
    
    // MARK: - Event Handling
    
    /// Check if an event is from the trackpad (not from a mouse)
    /// Uses the CGEvent's sender ID to identify the source device
    private func isTrackpadEvent(_ event: CGEvent) -> Bool {
        // If trackpadOnly is disabled, allow all events (treat everything as trackpad)
        if !settings.trackpadOnly {
            return true
        }
        
        // Method 1: Check pressure - trackpad tap-to-click has zero pressure, 
        // but physical trackpad clicks and mouse clicks have pressure > 0
        // However, trackpad tap-to-click also reports pressure = 0
        
        // Method 2: Check event subtype
        let subtype = event.getIntegerValueField(kCGMouseEventSubtype)
        
        // subtype 1 = tablet/trackpad with pressure sensing (physical click on trackpad)
        if subtype == kCGEventMouseSubtypeTabletPoint {
            appLog("   isTrackpadEvent: subtype=\(subtype) -> true (tablet)")
            return true
        }
        
        // subtype 0 = default (could be mouse OR tap-to-click)
        // For tap-to-click, we need to check if mouse is connected
        
        // Method 3: Check button number - different for trackpad gestures
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        
        // Method 4: Check click state
        let clickState = event.getIntegerValueField(.mouseEventClickState)
        
        // Method 5: Check if external mouse is connected
        let mouseConnected = isMouseConnected()
        
        appLog("   isTrackpadEvent: subtype=\(subtype) button=\(buttonNumber) click=\(clickState) mouseConnected=\(mouseConnected)")
        
        if !mouseConnected {
            // No external mouse connected, must be trackpad
            return true
        }
        
        // Mouse IS connected and trackpadOnly is enabled
        // We can't reliably distinguish tap-to-click from mouse click when both have subtype=0
        // Conservative approach: reject when mouse is connected
        appLog("   isTrackpadEvent: rejecting because mouse is connected")
        return false
    }
    
    /// Check if an external mouse is currently connected
    private func isMouseConnected() -> Bool {
        let matchingDict = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            appLog("   isMouseConnected: IOServiceGetMatchingServices failed")
            return false
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { 
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            // Check if this device is a mouse (not a trackpad)
            if let deviceUsagePage = IORegistryEntryCreateCFProperty(service, kIOHIDDeviceUsagePageKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               let deviceUsage = IORegistryEntryCreateCFProperty(service, kIOHIDDeviceUsageKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                
                // Get product name for logging
                let productName = IORegistryEntryCreateCFProperty(service, kIOHIDProductKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? "Unknown"
                let transport = IORegistryEntryCreateCFProperty(service, kIOHIDTransportKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? "Unknown"
                
                // Generic Desktop Page (0x01), Mouse usage (0x02)
                if deviceUsagePage == kHIDPage_GenericDesktop && deviceUsage == kHIDUsage_GD_Mouse {
                    appLog("   Found HID Mouse: '\(productName)' transport=\(transport)")
                    
                    // Built-in trackpad uses "SPI" or "I2C", external mice use "USB" or "Bluetooth"
                    if transport == "USB" || transport == "Bluetooth" {
                        let lowercaseName = productName.lowercased()
                        // Exclude if it's a trackpad disguised as mouse
                        if !lowercaseName.contains("trackpad") && !lowercaseName.contains("touch") {
                            appLog("   -> External mouse detected!")
                            return true
                        }
                    }
                }
            }
        }
        
        appLog("   isMouseConnected: No external mouse found")
        return false
    }
    
    /// Main event handler - routes events to appropriate handlers
    private var eventCount = 0
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        eventCount += 1
        
        // Log every 100th event to avoid spam, or always log mouse button events
        let shouldLog = (eventCount % 100 == 1) || type == .leftMouseDown || type == .leftMouseUp
        
        if shouldLog {
            print("🔹 Event #\(eventCount): \(type.rawValue) state=\(state)")
        }
        
        // Handle tap disabled events (system can disable our tap if it's too slow)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("⚠️ Event tap was disabled, re-enabling...")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        guard settings.isEnabled else {
            return Unmanaged.passRetained(event)
        }
        
        // Only process trackpad events, let mouse events pass through unchanged
        // Exception: when dragging, we need to handle all events to maintain drag state
        let isTrackpad = isTrackpadEvent(event)
        if !isTrackpad {
            // If we're dragging and receive a mouse event, we should still handle dragging state
            if case .dragging = state {
                // Let mouse events pass through during drag
            } else {
                // Not dragging, and not trackpad - pass through unchanged
                return Unmanaged.passRetained(event)
            }
        }
        
        let currentTime = ProcessInfo.processInfo.systemUptime
        let location = event.location
        
        switch type {
        case .leftMouseDown:
            return handleMouseDown(event: event, time: currentTime, location: location)
            
        case .leftMouseUp:
            return handleMouseUp(event: event, time: currentTime, location: location)
            
        case .leftMouseDragged:
            return handleMouseDragged(event: event, time: currentTime, location: location)
            
        case .mouseMoved:
            return handleMouseMoved(event: event, time: currentTime, location: location)
            
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    /// Handle mouseDown event
    /// - In idle state: Let it pass through (normal click)
    /// - In waitingForSecondTap: Check if valid double-tap, start drag if so
    /// - In dragging: Let it pass through
    private func handleMouseDown(event: CGEvent, time: TimeInterval, location: CGPoint) -> Unmanaged<CGEvent>? {
        // Check if we should ignore this event (it's one we sent ourselves)
        if ignoringNextMouseDown {
            ignoringNextMouseDown = false
            return Unmanaged.passRetained(event)
        }
        
        switch state {
        case .idle:
            // First tap - just let it pass, we'll handle state transition on mouseUp
            return Unmanaged.passRetained(event)
            
        case .waitingForSecondTap(let firstTapTime, let firstTapLocation):
            // Check if this is a valid second tap (within time window and distance)
            let timeSinceFirstTap = time - firstTapTime
            let distance = distanceBetween(location, firstTapLocation)
            
            if timeSinceFirstTap <= settings.doubleTapWindow && distance <= tapMovementThreshold {
                // Valid second tap! Start dragging
                doubleTapTimer?.invalidate()
                doubleTapTimer = nil
                
                // Enter dragging state
                state = .dragging(lastMoveTime: time)
                dragStartLocation = location
                lastMoveLocation = location
                
                // Start finger lift detection
                startLiftDetectionTimer()
                
                // Send synthetic mouseDown after a small delay to start the drag
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.sendMouseDown(at: location)
                }
                
                // Suppress this event (we'll send our own mouseDown)
                return nil
            } else {
                // Invalid - timeout or too far away
                doubleTapTimer?.invalidate()
                doubleTapTimer = nil
                state = .idle
                return Unmanaged.passRetained(event)
            }
            
        case .dragging:
            // Already dragging, let events pass through
            return Unmanaged.passRetained(event)
        }
    }
    
    /// Handle mouseUp event
    /// - In idle state: First tap completed, start waiting for second tap
    /// - In waitingForSecondTap: Let it pass through
    /// - In dragging: Suppress it (we'll send mouseUp when finger lifts)
    private func handleMouseUp(event: CGEvent, time: TimeInterval, location: CGPoint) -> Unmanaged<CGEvent>? {
        // Check if we should ignore this event (it's one we sent ourselves)
        if ignoringNextMouseUp {
            ignoringNextMouseUp = false
            return Unmanaged.passRetained(event)
        }
        
        switch state {
        case .idle:
            // First tap completed - transition to waiting for second tap
            state = .waitingForSecondTap(firstTapTime: time, location: location)
            startDoubleTapTimer()
            return Unmanaged.passRetained(event)
            
        case .waitingForSecondTap:
            // Just pass through
            return Unmanaged.passRetained(event)
            
        case .dragging:
            // Suppress mouseUp - we want to keep dragging until finger lifts
            return nil
        }
    }
    
    /// Handle mouseDragged event (mouse moved while button is held)
    /// Only relevant in dragging state - updates last move time
    private func handleMouseDragged(event: CGEvent, time: TimeInterval, location: CGPoint) -> Unmanaged<CGEvent>? {
        switch state {
        case .dragging:
            // Update last move time and location for lift detection
            state = .dragging(lastMoveTime: time)
            lastMoveLocation = location
            resetLiftDetectionTimer()
            return Unmanaged.passRetained(event)
            
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    /// Handle mouseMoved event (mouse moved without button held)
    /// - In waitingForSecondTap: If movement detected, start drag (tap + move gesture)
    /// - In dragging: Convert to drag event and update lift detection
    private func handleMouseMoved(event: CGEvent, time: TimeInterval, location: CGPoint) -> Unmanaged<CGEvent>? {
        switch state {
        case .waitingForSecondTap(let firstTapTime, let firstTapLocation):
            // Movement detected while waiting for second tap
            let timeSinceFirstTap = time - firstTapTime
            let distance = distanceBetween(location, firstTapLocation)
            
            // If within time window and moved enough, start dragging
            // This handles the "tap then immediately start moving" gesture
            if timeSinceFirstTap <= settings.doubleTapWindow && distance > 5 {
                doubleTapTimer?.invalidate()
                doubleTapTimer = nil
                
                // Enter dragging state
                state = .dragging(lastMoveTime: time)
                dragStartLocation = firstTapLocation
                lastMoveLocation = location
                
                // Start finger lift detection
                startLiftDetectionTimer()
                
                // Set flag to ignore our own mouseDown event
                ignoringNextMouseDown = true
                
                // Send synthetic mouseDown to start the drag
                if let mouseDown = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseDown,
                    mouseCursorPosition: firstTapLocation,
                    mouseButton: .left
                ) {
                    mouseDown.post(tap: .cghidEventTap)
                }
                
                // Convert this mouseMoved to a drag event
                if let dragEvent = CGEvent(
                    mouseEventSource: CGEventSource(event: event),
                    mouseType: .leftMouseDragged,
                    mouseCursorPosition: location,
                    mouseButton: .left
                ) {
                    return Unmanaged.passRetained(dragEvent)
                }
            }
            return Unmanaged.passRetained(event)
            
        case .dragging:
            // In drag state, convert mouseMoved to leftMouseDragged
            state = .dragging(lastMoveTime: time)
            lastMoveLocation = location
            resetLiftDetectionTimer()
            
            // Create drag event from move event
            if let dragEvent = CGEvent(
                mouseEventSource: CGEventSource(event: event),
                mouseType: .leftMouseDragged,
                mouseCursorPosition: location,
                mouseButton: .left
            ) {
                return Unmanaged.passRetained(dragEvent)
            }
            return Unmanaged.passRetained(event)
            
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    // MARK: - Drag Control
    
    /// Send a synthetic mouseDown event at the specified location
    private func sendMouseDown(at location: CGPoint) {
        guard case .dragging = state else { return }
        
        ignoringNextMouseDown = true
        
        if let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        ) {
            mouseDown.post(tap: .cghidEventTap)
        }
    }
    
    /// End the drag by sending a synthetic mouseUp event
    private func endDrag(at location: CGPoint) {
        guard case .dragging = state else { return }
        
        liftDetectionTimer?.invalidate()
        liftDetectionTimer = nil
        
        state = .idle
        
        ignoringNextMouseUp = true
        
        if let mouseUp = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        ) {
            mouseUp.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Timer Management
    
    /// Start the double-tap timeout timer
    /// If no second tap is detected within the time window, return to idle state
    private func startDoubleTapTimer() {
        doubleTapTimer?.invalidate()
        doubleTapTimer = Timer.scheduledTimer(withTimeInterval: settings.doubleTapWindow, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.doubleTapTimeout()
            }
        }
    }
    
    /// Handle double-tap timeout - return to idle if still waiting
    private func doubleTapTimeout() {
        if case .waitingForSecondTap = state {
            state = .idle
        }
    }
    
    /// Start the lift detection timer
    /// This timer fires periodically to check if the finger has lifted (no movement)
    private func startLiftDetectionTimer() {
        liftDetectionTimer?.invalidate()
        liftDetectionTimer = Timer.scheduledTimer(withTimeInterval: settings.liftDetectionDelay, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkForFingerLift()
            }
        }
    }
    
    /// Reset the lift detection timer (called on each movement)
    /// Note: We don't actually reset the timer, we just update lastMoveTime
    /// The timer checks if enough time has passed since last movement
    private func resetLiftDetectionTimer() {
        // Timer continues running, each movement updates lastMoveTime in state
    }
    
    /// Check if finger has lifted from trackpad
    /// If no movement for liftDetectionDelay duration, end the drag
    private func checkForFingerLift() {
        guard case .dragging(let lastMoveTime) = state else {
            liftDetectionTimer?.invalidate()
            liftDetectionTimer = nil
            return
        }
        
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timeSinceLastMove = currentTime - lastMoveTime
        
        if timeSinceLastMove >= settings.liftDetectionDelay {
            // No movement for the delay duration - finger has lifted
            endDrag(at: lastMoveLocation)
        }
    }
    
    // MARK: - Utilities
    
    /// Calculate distance between two points
    private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}
