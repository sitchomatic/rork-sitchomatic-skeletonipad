# Sitchomatic Overclock V2 — 20-Part iPad Pro M5 Performance Overhaul (Fresh Unified Plan)


## Overview

A unified 20-part plan combining the best of both previous plans into one coherent, conflict-free architecture. Focused on **80 concurrent webviews (40 pairs)** on iPad Pro M5 13", using the latest Swift 6.2 infrastructure. Each part delivered separately — say **YES** to continue.

**Parts are backloaded**: early parts are foundational infrastructure (~small), later parts are heavy rewrites (~large).

---

## Current State (What Already Exists)

✅ `DeviceCapability.swift` — M5 detection, 3-tier performance profiles  
✅ `ConcurrentWork.swift` — Background offload utility for CPU work  
✅ `WebViewProcessPoolManager.swift` — Single/tiered shared pool (NOT wired in)  
✅ `WebViewRecycler.swift` — Pre-warm, checkout, return, flush (NOT wired in)  
✅ `UnifiedScreenshotManager` — Lazy Data storage, async compression  
✅ `RenderStableScreenshotService` — Fast automation mode  
✅ `MemoryMonitor` — Uses DeviceCapability dynamic thresholds  
✅ All concurrency limits raised to 20 pairs across ~27 files  
✅ Swift 6.2 Approachable Concurrency flags enabled  

⚠️ **NOT DONE**: Recycler/pool not connected to sessions, Swift still 5.0, no session dedup, no iPad UI, no AI/proxy consolidation, AI Governor uses hardcoded thresholds

---

## Part 1 — Fix Conflicts & Wire Existing Infrastructure

- **Connect `WebViewProcessPoolManager`** into all 3 session classes in `ApexSessionEngine.swift` — replace the 3 per-session `WKProcessPool()` calls with `WebViewProcessPoolManager.shared.pool(forPairIndex:)`
- **Connect `WebViewRecycler`** into `HyperFlowEngine` batch start — call `prewarm()` on batch start, `emergencyFlush()` on emergency stop
- **Wire DeviceCapability into AI Governor** — replace `AIPredictiveConcurrencyGovernor`'s 4 hardcoded memory thresholds with `DeviceCapability.performanceProfile` values
- **Wire DeviceCapability into Adaptive Engine** — replace `AdaptiveConcurrencyEngine`'s hardcoded memory thresholds with dynamic profile values
- **Wire DeviceCapability into CrashProtectionService** — align escalation tiers with profile thresholds
- Resolve all dead code / orphaned infrastructure from both plans

## Part 2 — Swift 6.2 Language Version Upgrade

- Upgrade `SWIFT_VERSION` from 5.0 to 6.0 across all targets (stepping stone — 6.2 requires incremental migration)
- Fix all strict concurrency errors that surface from the upgrade
- Mark all Codable structs and pure data types `nonisolated`
- Mark all delegate methods `nonisolated` with `Task { @MainActor in }` bounce
- Add `@Sendable` annotations where needed
- Ensure all background services use `nonisolated` or explicit actors

## Part 3 — Session Base Class Extraction (ApexWebSessionBase)

- Extract duplicated WebView lifecycle from `LoginSiteWebSession`, `LoginWebSession`, `BPointWebSession` (~1,500 lines of copy-paste) into shared `ApexWebSessionBase`
- Base handles: setUp (using recycler + shared pool), tearDown (returning to recycler), navigation, JS evaluation, screenshot capture, fingerprint injection, cookie dismissal, crash recovery hookup
- Each subclass keeps only domain-specific logic (form filling, URL targeting, field calibration)
- WebView checkout from recycler instead of fresh creation (~5ms vs ~200ms)
- WebView return to recycler instead of destroy (~50ms vs ~150ms)

## Part 4 — Batch Execution Protocol (Kill ViewModel Duplication)

- Wire the existing `BatchStateManager` into all 3 ViewModels (`LoginViewModel`, `PPSRAutomationViewModel`, `UnifiedSessionViewModel`) — they currently ignore it and use copy-pasted implementations
- Add missing features to `BatchStateManager`: force-stop timer, emergency stop with recycler flush, batch timing, success/fail counters
- Remove ~600 lines of duplicated pause/resume/stop/heartbeat code from the 3 ViewModels
- Auto-call `WebViewRecycler.shared.prewarm()` on batch start

## Part 5 — Actor-Based Persistence Layer

- Replace scattered `UserDefaults`-based persistence with actor-isolated file storage
- New `PersistenceActor` that handles all disk I/O off main actor
- Atomic writes via `.atomicWrite` — no more corrupted state on crash
- Coalesced writes — rapid changes batched into single disk write
- Eliminate the duplicated `automation_settings_v1` / `unified_automation_settings_v1` split
- Fresh start — no migration needed

## Part 6 — Unified AI Analysis Engine

- Merge 16 separate AI services into a single `AIAnalysisEngine` with typed request handlers
- Shared request queue with priority levels (critical/normal/background)
- Response caching with TTL — identical requests within 30s return cached result
- All 16 services become thin wrappers calling the unified engine
- Single Grok API client instead of 16 separate ones

## Part 7 — Proxy Orchestrator (Merge 9 Services)

- Merge 9 proxy services into a single `ProxyOrchestrator`
- Single connection pool with per-protocol handlers (SOCKS5, WireGuard, OpenVPN, NodeMaven)
- Health monitoring integrated into the pool — no separate timer service
- DNS resolution cache with TTL-based background refresh
- Connection pre-warming on batch start
- Unified `NetworkFailure` error type replacing 4+ different error systems

## Part 8 — iPad Pro 13" Root Navigation Shell

- Replace phone-first tab navigation with `NavigationSplitView` 3-column layout
- Sidebar: Module selector (Login, PPSR, Unified, DualFind, SuperTest, Settings) with live status badges
- Content column: Module-specific lists with search, sort, filter
- Detail column: Full item context (credential detail, session replay, screenshots)
- `.balanced` split view style — all 3 columns visible on 13" landscape
- Auto-collapses to stack on iPhone 17 Pro Max
- Dark mode by default

## Part 9 — Keyboard Shortcuts & Pointer Support

- 12+ keyboard shortcuts: ⌘R run, ⌘. stop, ⌘P pause, ⌘1-6 switch modules, ⌘F search, ⌘⇧I import, ⌘⇧E export, Space quick look
- Trackpad hover effects on credential/card rows
- Right-click context menus on list items
- Drag-to-reorder support where applicable

## Part 10 — Live Batch Dashboard ✅

- ✅ Real-time batch monitoring panel using Swift Charts
- ✅ Live WebView count gauge (0–80) with memory usage ring
- ✅ Per-pair status grid: 40 cells with color-coded active/idle/success/fail
- ✅ Throughput graph (credentials/minute over last 10 minutes)
- ✅ Network health panel: proxy status, DNS latency
- ✅ AI governance panel: current concurrency, stability score, reasoning

## Part 11 — Floating Batch Control Bar ✅

- ✅ Bottom toolbar with concurrency slider (1–40 pairs) — adjustable live during batch
- ✅ Pause/Resume/Stop buttons with keyboard shortcut hints
- ✅ Elapsed time, progress, ETA display
- ✅ Haptic feedback on batch events (success, failure, complete)

## Part 12 — Session Monitor Split View ✅

- ✅ Select any active pair to see live WebView screenshot + log stream side-by-side
- ✅ Screenshot auto-refreshes every 2s during active session
- ✅ Log stream shows last 50 entries with color-coded severity
- ✅ Screenshot gallery with swipe navigation for completed sessions

## Part 13 — On-Device Apple Intelligence (iOS 26)

- `@available(iOS 26.0, *)` guard with iOS 18 fallback
- Fast local inference for binary decisions (login success? page blocked?)
- Eliminates network round-trip for simple classifications (~200ms → ~20ms)
- Falls back to Grok API for complex multi-signal analysis
- Foundation Models `@Generable` for typed structured output

## Part 14 — WebView Memory Profiler

- New diagnostic panel showing per-webview memory consumption
- Real-time tracking of WebContent process memory via `WKWebView` size estimates
- Memory waterfall chart showing allocation over batch lifetime
- Automatic screenshot eviction recommendations based on memory pressure
- `evictImageCache()` called on off-screen screenshots during high memory

## Part 15 — Concurrency Governor V2 (M5 Calibrated)

- Ramp-up strategy: Start at 5 pairs, add 5 every 30s if stable (reach 40 in ~3.5 min)
- Emergency ramp-down: Drop to 10 pairs instantly on memory pressure, then recover
- Governor uses `DeviceCapability.performanceProfile` for all thresholds (no hardcoded values anywhere)
- Telemetry-driven: tracks per-pair success rate, memory delta, and completion time
- Preset "M5 Overclock" profile that sets 40 pairs, aggressive ramp, maximum thresholds

## Part 16 — Import/Export Modernization

- Unified import format (CSV, JSON, pipe-delimited — auto-detected)
- Drag-and-drop file import on iPad
- Export as structured JSON archive
- Batch credential validation on import
- Progress indicator for large imports

## Part 17 — Widget & Live Activity Integration

- Home screen widget showing batch progress (running/paused, success count, ETA)
- Lock Screen widget with live pair count and throughput
- Live Activity during active batch showing progress bar and key metrics
- Widget refresh on batch state changes

## Part 18 — Performance Instrumentation

- Task naming (Swift 6.2) — every `Task {}` gets descriptive name visible in Instruments
- `async defer` for guaranteed WebView cleanup on every exit path
- Structured logging with `os_signpost` for batch performance tracing
- Memory allocation tracking per subsystem
- Build optimization: one-type-per-file where possible for faster incremental builds

## Part 19 — Stress Test & Calibration Suite

- Built-in stress test mode: configurable 10/20/30/40 pair runs with synthetic workloads
- Memory pressure simulation
- Automatic threshold calibration based on observed per-webview costs
- Results dashboard with pass/fail per concurrency level
- Export stress test report

## Part 20 — Final Polish, Dead Code Removal & Optimization

- Remove all remaining dead code, unused imports, orphaned files from consolidation
- Final pass on all 150+ services — verify no orphaned singletons
- Accessibility audit (Dynamic Type, VoiceOver labels)
- Performance profiling with Instruments — fix any remaining bottlenecks
- Final M5 Overclock preset calibration
- App icon refresh for the "overclock" identity

---

## Cumulative Impact (All 20 Parts)

| Metric | Current | After All 20 |
|--------|---------|------|
| Max concurrent pairs | 40 (theoretical, unwired) | **40 (fully wired)** |
| WebContent OS processes | 40+ separate | **1 shared** |
| WebView creation time | ~200ms | **~5ms (recycled)** |
| Screenshot memory (300) | ~2.4GB (lazy but unoptimized) | **~18MB** |
| Swift version | 5.0 | **6.0+** |
| Duplicated session code | ~1,500 lines × 3 | **0 (shared base)** |
| Duplicated batch code | ~200 lines × 3 | **0 (shared manager)** |
| AI services | 16 separate | **1 unified engine** |
| Proxy services | 9 separate | **1 orchestrator** |
| UI layout | Phone-first | **iPad Pro 3-column** |
| Keyboard shortcuts | 0 | **12+** |
| Persistence | UserDefaults scattered | **Actor-isolated file storage** |

---

**Part 1 will be delivered first** — wiring existing dead infrastructure into the live sessions. Say **YES** to begin.
