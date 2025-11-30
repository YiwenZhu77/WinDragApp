# WinDragApp

A macOS app that enables Windows-style double-tap to drag functionality for trackpads with "Tap to Click" enabled.

## Features

- **Double-tap to drag**: Tap once to select, tap again and drag without holding down
- **Trackpad only mode**: Optionally disable when an external mouse is connected
- **Configurable delays**: Adjust double-tap window and lift detection delay
- **Menu bar app**: Runs quietly in the background with a status bar icon
- **English UI**: Clean, simple interface

## How It Works

1. **First tap**: Registers the tap location and time
2. **Second tap** (within the double-tap window): Enters drag mode
3. **Move finger**: Drags the selected item
4. **Lift finger**: Ends the drag (detected when no movement for the lift detection delay)

## Requirements

- macOS 12.0 or later
- Accessibility permission (required for event interception)

## Installation

### From Release

1. Download `WinDragApp.app.zip` from the [Releases](../../releases) page
2. Unzip and move `WinDragApp.app` to `/Applications`
3. Launch the app
4. Grant Accessibility permission when prompted:
   - Go to **System Settings > Privacy & Security > Accessibility**
   - Add and enable WinDragApp

### Build from Source

1. Clone the repository
2. Open `WinDragApp.xcodeproj` in Xcode
3. Build and run (⌘R)

## Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Enable Double-Tap Drag | Turn the feature on/off | On |
| Trackpad Only | Disable when mouse is connected | Off |
| Double-Tap Window | Time to recognize second tap | 500ms |
| Lift Detection Delay | Time without movement to end drag | 150ms |

## Usage Tips

- Enable "Tap to Click" in System Settings > Trackpad for best results
- If drags end too quickly, increase the Lift Detection Delay
- If double-taps aren't detected, increase the Double-Tap Window

## License

MIT License

## Credits

Inspired by Windows ClickLock feature for accessibility.
