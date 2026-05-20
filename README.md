<p align="center">
  <img src="images/screenshot.png" alt="skStats Screen" width="350">
</p>

# skStats

<p align="left">
  <img src="https://img.shields.io/badge/macOS-13.0+-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-UI-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/github/actions/workflow/status/ericsk/skStats/xcode-build.yml?style=for-the-badge&logo=githubactions&logoColor=white" alt="Build Status">
  <img src="https://img.shields.io/github/license/ericsk/skStats?style=for-the-badge" alt="License">
</p>

**skStats** is a lightweight, elegant, and native macOS menu bar application designed to monitor your real-time system hardware and performance resources. Built cleanly with Swift and SwiftUI, it acts as your personal system supervisor without ever getting in your way.

> **Note**: This project is completely built by Google Gemini.

## 🚀 Features

- **Resource Leaderboards**: Instantly see the **Top 3 CPU** and **Top 3 Memory** consuming processes with relative visual load indicators.
- **Per-Core CPU Load**: Real-time load monitoring for each individual core with high-fidelity circular gauges.
- **Memory Usage**: Real-time RAM footprints with pressure monitoring and swap tracking.
- **GPU & Disk I/O**: Live GPU utilization tracking via `IOAccelerator` and exact Drive Read/Write rates.
- **Network Speed**: Instant Upload/Download network throughput.
- **Launch at Login [NEW]**: Seamlessly integrates with macOS Login Items for 24/7 monitoring.
- **Activity Monitor Integration [NEW]**: Quick-access shortcut to the system Activity Monitor.
- **Pure Native UX**: Modern SwiftUI interface with glassmorphism and smooth transitions. Operates exclusively in the menu bar (`LSUIElement`).

## 🛡️ Stability & DevOps

- **Native System Integration**: skStats uses high-performance Mach and IOKit APIs (`host_processor_info`, `proc_pidinfo`, `sysctlbyname`) rather than shell-bridging. This guarantees minimal resource footprint and zero overhead from external processes.
- **Zero-Leak Engineering**: All Mach memory allocations (e.g., `processor_info_array_t`) are strictly deallocated with `vm_deallocate`, and IOKit objects are correctly released, ensuring it can run flawlessly 24/7.
- **Cloud CI/CD Enabled**: Features built-in **GitHub Actions** for automatic verification and compilation on macOS cloud runners.

## 💻 Requirements

- macOS 13.0 or later
- Xcode / Xcode Command Line Tools

## 🔨 How to Build

### Option A: Using Xcode
1. Clone the repository.
2. Open `skStats.xcodeproj` in Xcode.
3. Select your Mac as the destination.
4. Press `Cmd + R` to Build and Run! 

### Option B: Terminal Release Build (Optimized)
To create an optimized, high-performance production build exactly like the CI workflow does:
```bash
xcodebuild build -project skStats.xcodeproj -scheme skStats -configuration Release -destination 'platform=macOS' CONFIGURATION_BUILD_DIR=$(PWD)/build/Release
```
The compiled binary `.app` will appear in the `build/Release/` directory.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
