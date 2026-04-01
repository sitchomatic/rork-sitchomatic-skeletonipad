# Sitchomatic

An iPad Pro–optimized automation testing suite built with Swift and SwiftUI. Designed for high-concurrency credential validation across multiple platforms, with deep AI integration, advanced networking, and real-time monitoring dashboards.

## Features

### Core Modes

- **Unified Sessions** — Paired JoePoint + Ignition testing with 4–40 concurrent worker pairs, early-stop sync, and result tracking
- **PPSR CarCheck** — Payment card validation (BIN lookup, gateway testing) and VIN verification against the PPSR government database
- **Dual Find** — Email × 3 password permutation credential discovery with AI-powered priority triage
- **Test & Debug** — Known-account optimizer for targeted testing
- **Settings & Testing** — 11 dedicated monitoring and diagnostic dashboards

### AI-Powered Automation

- Unified `AIAnalysisEngine` with priority queue and response caching (replaces 16+ separate AI services)
- Grok API integration for vision and reasoning analysis
- On-Device Apple Intelligence (iOS 26+) with automatic fallback to cloud
- Predictive batch pre-optimization, credential triage, and confidence scoring
- 18 specialized AI service wrappers coordinated through the central engine

### High-Performance WebView Management

- Shared `WKProcessPool` — single OS process for all concurrent WebViews
- `WebViewRecycler` — pre-warm, checkout, return, and flush lifecycle (~5ms creation vs ~200ms)
- Per-WebView memory profiling with eviction recommendations
- Crash recovery with automatic restart

### Adaptive Concurrency

- 5-phase state machine: rampUp → stable → rampDown → emergencyBrake → cooldown
- M5-calibrated governor supporting up to 40 concurrent pairs (80 WebViews)
- Device-aware thresholds via `DeviceCapability` (M5 / M4 / HighPerformance / Standard tiers)
- Live concurrency adjustment during batch runs

### Networking & Proxy

- Unified `ProxyOrchestrator` (merged 9 proxy services) with SOCKS5, WireGuard, OpenVPN, and NodeMaven support
- Per-protocol connection pooling, health monitoring, and auto-failover with circuit breaker
- DNS caching with TTL-based background refresh
- NordVPN WireGuard and OpenVPN configuration generation

### Monitoring Dashboards (11 Tools)

| Dashboard | Description |
|-----------|-------------|
| Live Batch | Real-time WebView count, throughput charts, AI governance panel |
| Session Monitor | Live screenshot + log stream split view for any active pair |
| Super Test | Full infrastructure validation suite |
| IP Score Test | 20× concurrent IP quality analysis |
| Batch Intelligence | AI pre-optimizer, credential triage, domain intel |
| WebView Memory Profiler | Per-WebView memory tracking with waterfall timeline |
| Batch Telemetry | Historical batch analytics, success rate trends, throughput |
| Performance Monitor | OS signpost tracing, task tracking, Instruments integration |
| Adaptive Concurrency | Real-time concurrency optimization with 3 presets |
| Stress Test | Configurable stress testing and threshold calibration |
| Service Status | Infrastructure-wide service health overview |

### iPad Pro UI

- `NavigationSplitView` 3-column layout optimized for 13" landscape
- 12+ keyboard shortcuts (⌘R run, ⌘. stop, ⌘P pause, ⌘1–6 switch modules)
- Trackpad hover effects and right-click context menus
- Home screen widget, lock screen widget, and Live Activity for batch progress

## Architecture

```
ios/Sitchomatic/
├── SitchomaticApp.swift          # @main entry point
├── ContentView.swift             # PPSR tab-based view
├── ProductMode.swift             # Product mode enum
├── Services/                     # 176 service files
│   ├── ApexSessionEngine.swift   # Master session coordinator
│   ├── AIAnalysisEngine.swift    # Unified AI engine
│   ├── ProxyOrchestrator.swift   # Unified proxy management
│   ├── PersistenceActor.swift    # Actor-isolated file storage
│   ├── BatchStateManager.swift   # Batch execution lifecycle
│   ├── WebViewRecycler.swift     # WebView pooling
│   ├── WireProxy/                # WireGuard implementation
│   └── Patterns/                 # Login pattern matching
├── Views/                        # 98 SwiftUI views
├── ViewModels/                   # 13 view models
├── Models/                       # 45 data models
└── Utilities/                    # 13 cross-cutting utilities

ios/SitchomaticWidget/            # Widget extension
├── SitchomaticWidget.swift       # Home/lock screen widgets
├── CommandCenterLiveActivity.swift
└── CommandCenterActivityAttributes.swift
```

### Key Architectural Patterns

- **Swift 6 concurrency** — `@MainActor` isolation on all observable models; `static let shared` on @MainActor singletons; actor-based persistence
- **Device-adaptive performance** — `DeviceCapability` detects hardware tier and provides dynamic thresholds for concurrency, memory, caching, and WebView limits
- **Coalesced persistence** — `PersistenceActor` batches rapid writes into single disk operations (500ms window) with read-through pending writes
- **Singleton service container** — 163 services coordinated through `ServiceContainer` and individual `.shared` singletons
- **AI response cleaning** — `AIResponseCleaner.cleanJSON()` strips markdown fences from LLM responses, used by all 18 AI services

## Requirements

- **Platform**: iPadOS 18.0+ (On-Device Apple Intelligence requires iPadOS 26+; guarded with `@available` and falls back to cloud AI on earlier versions)
- **Optimized for**: iPad Pro 13" with M4/M5 chip
- **Xcode**: 15.0+
- **Swift**: 6.0+
- **Dependencies**: CoreXLSX (Excel file parsing)

## Getting Started

1. Clone the repository
2. Open `ios/Sitchomatic.xcodeproj` in Xcode
3. Select the `Sitchomatic` scheme and an iPad Pro simulator or device
4. Build and run (⌘R)

The app uses file-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new Swift files added to the `Sitchomatic/` directory are automatically discovered without editing the project file.

### Build Error Check

To check for build errors without including warnings:

```bash
./check_build_errors.sh
```

This script validates all Swift files under `ios/` (app, widget, and tests) using `swiftc -parse` and reports only compilation errors (warnings are filtered out). Exit code is 0 if no errors are found, 1 if errors exist.

### Configuration

- **Grok AI**: Configure API credentials in Settings & Testing → Grok AI Status
- **NordVPN**: Generate WireGuard/OpenVPN profiles in Settings & Testing → Nord Config
- **Proxy**: Set up proxy rotation in Settings & Testing → Device Network Settings
- **Import credentials**: CSV, JSON, or pipe-delimited files are auto-detected (Settings & Testing → Advanced Settings → Import/Export)

## Project Stats

| Category | Count |
|----------|-------|
| Swift files | 361 |
| Services | 176 |
| Views | 98 |
| Models | 45 |
| View Models | 13 |
| Utilities | 13 |
| Widget extension | 1 |

## Documentation

- **[PLAN.md](PLAN.md)** — 20-part iPad Pro M5 performance overhaul implementation plan
- **[FEATURE_ACCESS_GUIDE.md](FEATURE_ACCESS_GUIDE.md)** — Complete feature access guide with navigation reference for all 98 views and 163 services

## License

Proprietary. All rights reserved.
