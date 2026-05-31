# skStats Development & Maintenance Guide

This document provides specialized instructions and architectural context for maintaining and extending the **skStats** macOS system monitoring application.

## 🏗 Architecture Overview

The app follows a modern SwiftUI architecture with a strict separation between UI, state management, and telemetry gathering.

### 1. Core Components
- **`skStatsApp.swift`**: Entry point using `MenuBarExtra`. Manages the high-level lifecycle and defines the Menu Bar display logic.
- **`SystemMonitor.swift`**:
    - **`SystemMonitor` (MainActor ObservableObject)**: The single source of truth for UI state. It handles settings persistence via `UserDefaults` and coordinates update cycles.
    - **`TelemetryWorker` (Actor)**: Handles all thread-unsafe and performance-heavy system calls (IOKit, Mach host info, libproc) in a background context to prevent UI hangs.
    - **`SystemStats` (Struct)**: A thread-safe data transfer object used to pass snapshots from the worker to the monitor.
- **`ContentView.swift`**: The main dashboard UI. Uses specialized `DashboardSection` wrappers and SwiftUI `Gauge` components for visualization.

### 2. Telemetry Logic
- **CPU**: Uses `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` to calculate per-core load.
- **GPU**: Uses `IOKit` (`IOAccelerator`) to fetch "Device Utilization %".
- **Memory**: Uses `host_statistics64` with `HOST_VM_INFO64`.
- **Disk/Network**: Calculates rates by comparing cumulative byte counts over the `updateInterval`.
- **Processes**: Uses `libproc` (`proc_listpids` and `proc_pidinfo`). CPU percentage for processes is calculated by delta snapshots over time for accuracy.

## 🎨 UI & Styling Standards

- **Color Cues**: CPU Gauges use dynamic threshold coloring:
    - `Green`: < 70% (Normal)
    - `Orange`: 70% - 90% (Warning)
    - `Red`: > 90% (Critical)
- **Components**: Prefer `Gauge` for percentage-based metrics and `StatView` for rate-based metrics (MB/s).
- **Aesthetics**: Use `VisualEffectView` for native macOS vibrant backgrounds. Maintain monospaced fonts for numerical data to prevent layout jitter.

## 🛠 Maintenance Workflows

### Build & Run (Development)
```bash
xcodebuild -project skStats.xcodeproj -scheme skStats -configuration Debug -derivedDataPath build build
./build/Build/Products/Debug/skStats.app/Contents/MacOS/skStats
```

### Build & Run (Release)
```bash
xcodebuild -project skStats.xcodeproj -scheme skStats -configuration Release -derivedDataPath build clean build
open build/Build/Products/Release/skStats.app
```

### Key Maintenance Tasks
- **Updating Constants**: The `updateInterval` is configurable via UI but defaults to 3s.
- **Process Filtering**: Top processes are limited to the top 3 by default. Adjust `prefix(3)` in `TelemetryWorker` to change this.
- **Adding New Metrics**: 
    1. Update `SystemStats` struct.
    2. Add fetch logic in `TelemetryWorker`.
    3. Update `SystemMonitor` `@Published` properties.
    4. Create a new dashboard view in `ContentView.swift`.

## ⚠️ Security & Performance
- **Actor Isolation**: Never call `TelemetryWorker` methods directly from the UI. Always use `Task` from `SystemMonitor`.
- **Memory Safety**: Ensure all `io_object_t` and Mach pointers are properly released/deallocated.
- **Sandboxing**: If App Sandbox is enabled, ensure `com.apple.security.network.client` and hardware access entitlements are correctly set in `.entitlements` or `Info.plist`.
