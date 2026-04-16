# skStats

A lightweight, native macOS menu bar application designed to monitor real-time system resources. Built cleanly with Swift and SwiftUI.

> **Note**: This project is completely built by Google Antigravity.

<p align="center">
  <img src="images/screenshot.png" alt="skStats Screen" width="350">
</p>

## Features

- **CPU Load**: Real-time load monitoring for each core, using purely native responsive layout to cleanly fit any multi-core setup.
- **GPU Load**: Live GPU device utilization tracking.
- **Memory Usage**: Real-time RAM usage with a clean Used/Total representation.
- **Disk I/O**: Live Drive Read/Write rate monitoring.
- **Network Speed**: Instant Upload/Download network throughput.
- **Customizable Visibility**: Toggle individual metrics to keep your dashboard clean and focused.
- **Adjustable Frequency**: Precise real-time update intervals ranging from 1 to 10 seconds, controllable via a simple slider.
- **Native macOS Feel**: Operates exclusively in the menu bar without cluttering the Dock, presenting a highly polished popover dashboard interface.

## Requirements

- macOS 13.0 or later
- Xcode

## How to Build

1. Clone the repository.
2. Open `skStats.xcodeproj` in Xcode.
3. Select your Mac as the destination.
4. Press `Cmd + R` to Build and Run! 

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
