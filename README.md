# WinDragApp

A macOS menu bar app that brings Windows-style double-tap-to-drag to your trackpad.

## What it does

Double-tap on your trackpad to start dragging, then tap again (or wait) to release. No more holding down while dragging.

## Usage

1. Tap once on trackpad
2. Tap again within the time window → drag mode starts
3. Move your finger to drag
4. Tap again to stop (or wait for lift delay if enabled)

Works only with trackpad — mouse input is ignored.

## Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Enable | Turn feature on/off | On |
| Double-Tap Window | Time to detect second tap | 500ms |
| Stop Mode | Tap again, or delay after finger lifts | Tap again |
| Lift Delay | Time to wait before stopping (delay mode) | 500ms |

## Requirements

- macOS 12.0+
- Accessibility permission

## Install

1. Download from [Releases](../../releases)
2. Unzip, move to `/Applications`
3. Launch and grant Accessibility permission in System Settings

## Build

```
git clone https://github.com/YiwenZhu77/WinDragApp.git
cd WinDragApp
open WinDragApp.xcodeproj
# Build with ⌘R
```

## License

MIT
