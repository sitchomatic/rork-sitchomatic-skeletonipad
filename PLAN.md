# Fix singleton initialization errors in three service files

**Problem:** Three service classes marked `@MainActor` have `nonisolated(unsafe) static let shared` singletons, which causes a build error because the initializer is main-actor-isolated but the static property context is not.

**Fix:** Replace `nonisolated(unsafe) static let shared` with `static let shared` in:
- `WebViewProcessPoolManager.swift` (line 11)
- `WebViewRecycler.swift` (line 6)
- `WidgetBridgeService.swift` (line 10)

Since the project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, all types are already implicitly `@MainActor`, so the `static let shared` will work correctly without the `nonisolated(unsafe)` annotation. The classes are explicitly `@MainActor` too, so accessing `.shared` from other `@MainActor` code is safe.