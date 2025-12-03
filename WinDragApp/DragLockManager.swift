import Cocoa
import CoreGraphics

// MARK: - Double-Tap Drag Manager

/// Enables Windows-style double-tap-to-drag functionality for macOS trackpads.
///
/// **Usage:**
/// 1. Double-tap on trackpad to start dragging
/// 2. Move finger to drag
/// 3. Tap again to release
///
/// Only responds to trackpad input (NSEvent.subtype == 3), ignoring all mice.
final class DragLockManager {
    
    // MARK: - Singleton
    
    static let shared = DragLockManager()
    
    // MARK: - State
    
    private enum State {
        case idle
        case waitingForSecondTap(time: TimeInterval, location: CGPoint)
        case dragging
    }
    
    private var state: State = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var doubleTapTimer: Timer?
    private var liftDelayTimer: Timer?
    private var lastMoveLocation: CGPoint = .zero
    private var lastMoveTime: TimeInterval = 0
    
    // Flags to ignore synthetic events we create
    private var ignoreNextMouseDown = false
    private var ignoreNextMouseUp = false
    
    // Track if last click was from mouse (to ignore mouse-initiated sequences)
    private var lastClickWasFromMouse = false
    
    // MARK: - Settings
    
    /// Time window for double-tap detection (seconds)
    var doubleTapWindow: TimeInterval = 0.5
    
    /// How to stop dragging
    var stopMode: StopMode = .tapAgain
    
    /// Delay before stopping drag after finger lifts (seconds)
    var liftDelay: TimeInterval = 0.5
    
    /// Maximum distance between taps (points)
    private let maxTapDistance: CGFloat = 50.0
    
    /// Whether the manager is currently enabled
    private(set) var isRunning = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start listening for trackpad events
    func start() {
        guard !isRunning, eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            print("❌ Accessibility permission required")
            return
        }
        
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                      (1 << CGEventType.leftMouseUp.rawValue) |
                                      (1 << CGEventType.leftMouseDragged.rawValue) |
                                      (1 << CGEventType.mouseMoved.rawValue)
        
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<DragLockManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        print("✅ DragLockManager started")
    }
    
    /// Stop listening for events
    func stop() {
        doubleTapTimer?.invalidate()
        doubleTapTimer = nil
        liftDelayTimer?.invalidate()
        liftDelayTimer = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        state = .idle
        isRunning = false
        print("⏹ DragLockManager stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        let location = event.location
        let time = ProcessInfo.processInfo.systemUptime
        
        switch type {
        case .leftMouseDown:
            return handleMouseDown(event: event, location: location, time: time)
        case .leftMouseUp:
            return handleMouseUp(event: event, location: location, time: time)
        case .mouseMoved:
            return handleMouseMoved(event: event, location: location, time: time)
        case .leftMouseDragged:
            return handleMouseDragged(event: event, location: location)
        default:
            return Unmanaged.passRetained(event)
        }
    }
    
    // MARK: - Mouse Down
    
    private func handleMouseDown(event: CGEvent, location: CGPoint, time: TimeInterval) -> Unmanaged<CGEvent>? {
        // Skip synthetic events we created
        if ignoreNextMouseDown {
            ignoreNextMouseDown = false
            return Unmanaged.passRetained(event)
        }
        
        // Only respond to trackpad events
        guard isTrackpadEvent(event) else {
            lastClickWasFromMouse = true
            return Unmanaged.passRetained(event)
        }
        lastClickWasFromMouse = false
        
        switch state {
        case .idle:
            // First tap - just pass through
            return Unmanaged.passRetained(event)
            
        case .waitingForSecondTap(let firstTime, let firstLocation):
            // Check if valid double-tap
            let elapsed = time - firstTime
            let distance = hypot(location.x - firstLocation.x, location.y - firstLocation.y)
            
            if elapsed <= doubleTapWindow && distance <= maxTapDistance {
                // Valid double-tap! Start dragging
                doubleTapTimer?.invalidate()
                state = .dragging
                lastMoveLocation = location
                
                // Send synthetic mouseDown to start drag
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                    self?.sendMouseDown(at: location)
                }
                return nil // Suppress this event
            } else {
                // Invalid - reset to idle
                doubleTapTimer?.invalidate()
                state = .idle
                return Unmanaged.passRetained(event)
            }
            
        case .dragging:
            // Tap while dragging = end drag (only if stopMode is tapAgain)
            if stopMode == .tapAgain {
                endDrag(at: location)
            }
            return Unmanaged.passRetained(event)
        }
    }
    
    // MARK: - Mouse Up
    
    private func handleMouseUp(event: CGEvent, location: CGPoint, time: TimeInterval) -> Unmanaged<CGEvent>? {
        // Skip synthetic events
        if ignoreNextMouseUp {
            ignoreNextMouseUp = false
            return Unmanaged.passRetained(event)
        }
        
        // Ignore mouse events
        if lastClickWasFromMouse {
            return Unmanaged.passRetained(event)
        }
        
        switch state {
        case .idle:
            // First tap completed - wait for second
            state = .waitingForSecondTap(time: time, location: location)
            startDoubleTapTimer()
            return Unmanaged.passRetained(event)
            
        case .waitingForSecondTap, .dragging:
            return Unmanaged.passRetained(event)
        }
    }
    
    // MARK: - Mouse Moved
    
    private func handleMouseMoved(event: CGEvent, location: CGPoint, time: TimeInterval) -> Unmanaged<CGEvent>? {
        switch state {
        case .idle:
            return Unmanaged.passRetained(event)
            
        case .waitingForSecondTap(let firstTime, let firstLocation):
            // Movement after first tap - start drag if within time window
            if lastClickWasFromMouse {
                return Unmanaged.passRetained(event)
            }
            
            let elapsed = time - firstTime
            let distance = hypot(location.x - firstLocation.x, location.y - firstLocation.y)
            
            if elapsed <= doubleTapWindow && distance > 5 {
                // Tap + move = start drag
                doubleTapTimer?.invalidate()
                state = .dragging
                lastMoveLocation = location
                
                // Send mouseDown and convert to drag
                ignoreNextMouseDown = true
                sendMouseDown(at: location)
                
                return createDragEvent(from: event, at: location)
            }
            return Unmanaged.passRetained(event)
            
        case .dragging:
            // Convert mouseMoved to drag event
            lastMoveLocation = location
            lastMoveTime = time
            
            // Reset lift delay timer on movement (delay mode only)
            if stopMode == .delayTime {
                startLiftDelayTimer()
            }
            
            return createDragEvent(from: event, at: location)
        }
    }
    
    // MARK: - Mouse Dragged
    
    private func handleMouseDragged(event: CGEvent, location: CGPoint) -> Unmanaged<CGEvent>? {
        if case .dragging = state {
            lastMoveLocation = location
        }
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Helpers
    
    /// Check if event is from trackpad (not mouse)
    /// Trackpad events have NSEvent.subtype == 3
    private func isTrackpadEvent(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return true }
        // subtype 3 = trackpad/touch, subtype 1 = tablet, subtype 0 = mouse
        return nsEvent.subtype.rawValue == 3 || nsEvent.subtype.rawValue == 1
    }
    
    private func sendMouseDown(at location: CGPoint) {
        ignoreNextMouseDown = true
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: location, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    private func endDrag(at location: CGPoint) {
        guard case .dragging = state else { return }
        state = .idle
        lastClickWasFromMouse = false
        
        ignoreNextMouseUp = true
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: location, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    private func createDragEvent(from event: CGEvent, at location: CGPoint) -> Unmanaged<CGEvent>? {
        if let drag = CGEvent(mouseEventSource: CGEventSource(event: event),
                              mouseType: .leftMouseDragged,
                              mouseCursorPosition: location, mouseButton: .left) {
            return Unmanaged.passRetained(drag)
        }
        return Unmanaged.passRetained(event)
    }
    
    private func startDoubleTapTimer() {
        doubleTapTimer?.invalidate()
        doubleTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
            self?.state = .idle
            self?.lastClickWasFromMouse = false
        }
    }
    
    private func startLiftDelayTimer() {
        liftDelayTimer?.invalidate()
        liftDelayTimer = Timer.scheduledTimer(withTimeInterval: liftDelay, repeats: false) { [weak self] _ in
            guard let self = self, case .dragging = self.state else { return }
            self.endDrag(at: self.lastMoveLocation)
        }
    }
}
