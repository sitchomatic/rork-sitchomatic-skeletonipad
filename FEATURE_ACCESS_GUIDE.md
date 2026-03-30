# Sitchomatic - Complete Feature Access Guide

This document provides a comprehensive guide to all features and views accessible in the Sitchomatic app.

## Main Navigation Modes

Access these from the **Main Menu** (shown when no mode is active):

### 1. Unified Sessions
- **Purpose**: JoePoint + Ignition Lite paired testing
- **Features**: 4 Workers, Early-Stop Sync, V4.1 engine
- **Navigation**: Tap "UNIFIED SESSIONS" on main menu
- **View**: `UnifiedSessionFeedView`

### 2. PPSR Check
- **Purpose**: VIN & Card Testing
- **Features**: Payment card validation, BIN lookup, gateway testing
- **Navigation**: Tap "PPSR CHECK" on main menu
- **View**: `ContentView` (PPSR mode)

### 3. Dual Find
- **Purpose**: Email × 3 Passwords credential discovery
- **Navigation**: Tap "DUAL FIND" on main menu
- **View**: `DualFindContainerView` → `DualFindRunningView`, `DualFindLiveFeedView`

### 4. Test & Debug
- **Purpose**: Known Account Optimizer
- **Navigation**: Tap "TEST & DEBUG" on main menu
- **View**: `TestDebugContainerView`

### 5. Settings & Testing
- **Purpose**: Comprehensive settings and testing tools
- **Navigation**: Tap "SETTINGS & TESTING" on main menu
- **View**: `SettingsAndTestingView`

## Settings & Testing - Complete Feature List

Access via **Main Menu → Settings & Testing**

### Testing Tools Section

1. **Live Batch Dashboard**
   - Real-time WebView, throughput & AI monitoring
   - Icon: gauge.with.dots.needle.50percent
   - Color: Teal

2. **Session Monitor**
   - Live screenshot + log stream split view
   - Icon: rectangle.split.2x1
   - Color: Purple

3. **Super Test**
   - Full infrastructure validation
   - Icon: bolt.horizontal.circle.fill
   - Color: Purple

4. **IP Score Test**
   - 20x concurrent IP quality analysis
   - Icon: network.badge.shield.half.filled
   - Color: Indigo

5. **Batch Intelligence** ✨ *Now Accessible*
   - AI pre-optimizer, credential triage & domain intel
   - Icon: chart.line.uptrend.xyaxis
   - Color: Blue
   - Features:
     - Pre-Optimizer with readiness reports
     - Time Heatmap analysis
     - Credential Triage insights
     - Domain Intelligence

6. **WebView Memory Profiler** ✨ *Now Accessible*
   - Per-webview memory & eviction recommendations
   - Icon: chart.xyaxis.line
   - Color: Orange
   - Features:
     - Memory snapshots per WebView
     - Waterfall timeline (100-point ring buffer)
     - Device-adaptive eviction recommendations

7. **Batch Telemetry** ✨ *New*
   - Historical batch analytics & performance metrics
   - Icon: chart.bar.xaxis
   - Color: Green
   - Features:
     - Summary cards (total batches, avg success rate, total processed)
     - Success rate trend chart
     - Throughput per minute visualization
     - Detailed batch history with drill-down
     - Per-batch metrics: duration, success rate, network mode, issues

8. **Performance Monitor** ✨ *New*
   - OS signpost, task tracking & memory instrumentation
   - Icon: speedometer
   - Color: Red
   - Features:
     - Subsystem memory tracking
     - OS Signpost logging status
     - Named task tracking (Swift 6.2)
     - Instruments integration guide
     - WebView cleanup tracking

9. **Adaptive Concurrency** ✨ *Now Accessible*
   - Real-time concurrency optimization & health monitoring
   - Icon: gauge.with.dots.needle.bottom.100percent
   - Color: Purple
   - Features:
     - 5-phase state machine (rampUp → stable → rampDown → emergencyBrake → cooldown)
     - 3 presets: conservative, balanced, m5Overclock
     - Real-time health monitoring

10. **Stress Test** ✨ *Now Accessible*
    - System stress testing & threshold calibration
    - Icon: speedometer
    - Color: Red
    - Features:
      - 3-phase stress test (ramp/sustain/ramp-down)
      - Memory sampling
      - Threshold calibration from historical results

### Network & VPN Section

1. **Device Network Settings**
   - Proxy, VPN, WireGuard, DNS — all modes
   - Shows current connection mode badge
   - Access to:
     - Proxy Status Dashboard
     - VPN Status Dashboard
     - WireProxy Dashboard (when applicable)

2. **Nord Config**
   - WireGuard & OpenVPN generation
   - Icon: shield.checkered
   - Color: Cyan

3. **Repair Network**
   - Full restart of all network protocols
   - Shows repair status and last result
   - Icon: wrench.and.screwdriver.fill
   - Color: Orange

### Advanced Section

1. **Grok AI Status**
   - Connected status or configuration prompt
   - Vision + reasoning active indicator
   - Icon: brain.head.profile.fill
   - Color: Green (configured) / Orange (not configured)

2. **Advanced Settings**
   - Debug, diagnostics, data, app settings & about
   - Access to:
     - Full Debug Log
     - Console (live log output)
     - Notices (failure log & auto-retry history)
     - Export Diagnostic Report
     - Share Debug Log File
     - Import/Export (full backup & restore)
     - Vault (persistent file storage browser)
     - App appearance settings
     - About section

## Additional Access Points

### From Unified Session Mode:
- **Login More Menu**: Access via "More" button
  - AI Custom Tools Dashboard
  - Automation Tools Menu
  - URL & Endpoint management
  - Advanced settings
  - Account tools
  - Data management
  - Debug tools

### From PPSR Mode:
- **PPSR Settings**: Configuration and management
- **BPoint Pool Management**: Biller pool configuration

### From Main Modes:
- **Floating Batch Control Bar**: Always visible during batch runs
- **Run Command Pill**: Quick access to run controls

## Architecture Notes

### Joe & Ignition Integration
- **No separate "Joe dashboard"** - Joe and Ignition are unified
- Both platforms accessible through **Unified Sessions** mode
- Network settings apply to both Joe, Ignition & PPSR
- URL rotation supports both platforms
- Proxy/VPN configs shared across all targets

### Service Access Pattern
All major services now have UI access:
- ✅ AIAnalysisEngine → AI Custom Tools Dashboard
- ✅ AIPredictiveBatchPreOptimizer → Batch Intelligence
- ✅ AICredentialTriageService → Batch Intelligence
- ✅ BatchTelemetryService → Batch Telemetry Dashboard
- ✅ PerformanceInstrumentation → Performance Monitor
- ✅ WebViewMemoryProfiler → WebView Memory Profiler
- ✅ AdaptiveConcurrencyEngine → Adaptive Concurrency Dashboard
- ✅ StressTestService → Stress Test Dashboard
- ✅ ConcurrencyGovernorV2 → Adaptive Concurrency Dashboard
- ✅ ProxyRotationService → Device Network Settings → Proxy Status Dashboard
- ✅ NordVPNService → Nord Config
- ✅ BatchStateManager → Live Batch Dashboard
- ✅ CredentialGroupService → Credential Groups View (via Login Credentials List)

### Views Created/Made Accessible in This Update
1. **BatchTelemetryDashboardView** - New view for batch history analytics
2. **PerformanceMonitorView** - New view for performance instrumentation
3. **BatchIntelligenceView** - Existing view, now accessible
4. **WebViewMemoryProfilerView** - Existing view, now accessible
5. **AdaptiveConcurrencyDashboardView** - Existing view, now accessible
6. **StressTestDashboardView** - Existing view, now accessible

## Navigation Quick Reference

```
Main Menu
├── Unified Sessions (JoePoint + Ignition)
├── PPSR Check
├── Dual Find
├── Test & Debug
└── Settings & Testing
    ├── Testing Tools (10 items)
    │   ├── Live Batch Dashboard
    │   ├── Session Monitor
    │   ├── Super Test
    │   ├── IP Score Test
    │   ├── Batch Intelligence ✨
    │   ├── WebView Memory Profiler ✨
    │   ├── Batch Telemetry ✨ NEW
    │   ├── Performance Monitor ✨ NEW
    │   ├── Adaptive Concurrency ✨
    │   └── Stress Test ✨
    ├── Network & VPN (3 items)
    │   ├── Device Network Settings
    │   ├── Nord Config
    │   └── Repair Network
    └── Advanced (2 items)
        ├── Grok AI Status
        └── Advanced Settings
            ├── Debug & Diagnostics
            ├── Diagnostic Reports
            └── Data Management
```

## Summary

**Total Views**: 100+ view files
**Total Services**: 166 services
**Total Models**: 46 models

**All major functionality is now accessible through the UI.** Every significant service has a corresponding management interface or dashboard. The app provides comprehensive monitoring, testing, analytics, and configuration capabilities across all features.

✨ = Recently made accessible or newly created
