# Crimson Sweep: Replace 12+ Detection Services with Unified AI Vision

## Overview

Replace 12+ overlapping detection, settlement, and analysis services with a single **Unified AI Vision Service** that sends screenshots to Grok Vision API and gets back structured outcomes. Falls back to Apple on-device AI (iOS 26+) when Grok is unavailable.

**Before:** Submit click → 15+ services polling DOM, OCR keywords, button CSS, XHR hooks, weighted scoring → 7+ seconds  
**After:** Submit click → wait 2s → screenshot → 1 Grok Vision API call → structured outcome → done

---

## What Gets Created

### 1. UnifiedAIVisionService — The ONE Detection Engine

- Single entry point: takes a screenshot + context (which site, which phase) → returns a structured outcome
- Outcomes: success, noAcc, permDisabled, tempDisabled, smsDetected, connectionFailure, unsure
- Each outcome includes confidence (0–100) and reasoning text
- Also reports whether the page looks settled and whether it's blank
- **Primary:** Sends screenshot as base64 JPEG to Grok Vision with a context-tuned prompt
- **Fallback:** If Grok fails → Apple FoundationModels on-device (iOS 26+) analyzes OCR text extracted via Vision framework

### 2. AIVisionSettlementService — Settlement via Screenshots

- Replaces all DOM/JS-based settlement polling
- After clicking submit: takes screenshots at timed intervals (500ms, 1.5s, 3s, 5s)
- Sends each screenshot to the Unified AI Vision Service asking "has the page settled? what's the outcome?"
- Returns as soon as AI says page has settled with a definitive outcome
- No more JavaScript injection, button CSS polling, or XHR monkey-patching

### 3. Enhanced RorkToolkitService — New Unified Vision Method

- New method for unified vision analysis with optimized prompts per scenario
- Login prompt: asks about outcome, page state, error text, lobby/dashboard presence
- Settlement prompt: asks if page is still loading, content changed, error/success messages
- PPSR prompt: asks about passed/declined/error with payment page markers

---

## What Gets Gutted (Detection Logic Removed)

These services have their detection/analysis logic **replaced** with a single call to the Unified AI Vision Service. Their shells remain for compile compatibility where needed:

1. **StrictLoginDetectionEngine** — All DOM scanning, OCR keyword matching, 3.5s waits, retry cycles → replaced by single AI Vision call
2. **ConfidenceResultEngine** — All 7-signal weighted scoring → deleted, AI confidence is the only confidence
3. **VisionTextCropService** — All keyword arrays, pattern matching, outcome detection → only `smartCrop()` kept for screenshot cropping
4. **SettlementGateEngine** — All button color fingerprinting, error text JS, URL redirect classification → replaced by AI Vision Settlement
5. **SmartButtonRecoveryService** — All button CSS polling, loading term detection → deleted
6. **SmartPageSettlementService** — All XHR/fetch monkey-patching, MutationObserver, DOM readiness polling → deleted
7. **AIConfidenceAnalyzerService** — All learned keyword boosting, feedback recording → deleted
8. **UserInterventionLearningService** — All correction-based keyword learning → deleted
9. **OnDeviceAIService** — All heuristic fallbacks → replaced by unified AI Vision calls
10. **VisionMLService** — All field detection, saliency, instance masks, OCR scanning → removed entirely
11. **PageReadinessService** — All JavaScript DOM readiness polling → replaced by screenshot-based settlement

---

## Callers Updated to Use AI Vision

1. **DualSiteWorkerService** — Replace `strictDetection`, `settlementGate`, `visionOCR` calls with Unified AI Vision
2. **LoginAutomationEngine** — Replace `confidenceEngine`, `strictDetection`, `visionML` with Unified AI Vision
3. **TrueDetectionService** — Replace `validateSuccess()` and DOM scanning with AI Vision screenshot analysis
4. **ApexSessionEngine** — Replace settlement service calls with AI Vision Settlement
5. **DualFindViewModel** — Replace strict detection and settlement calls with AI Vision
6. **HumanInteractionEngine** — Remove VisionML-based pattern selection (keep coordinate click as default)
7. **LoginCredential.recordResult()** — Replace keyword-based status classification with direct outcome mapping
8. **DisabledCheckService** — Replace DOM text scanning with AI Vision screenshot analysis

---

## What Stays Unchanged

- Form filling (hardcoded selectors for email, password, submit on both sites)
- Screenshot capture (`captureScreenshot()` on web sessions)
- Network/proxy/stealth settings and rotation
- Credential management, import/export
- All UI views (dashboard, credential lists, session feeds)
- Core RorkToolkitService API calling infrastructure
- LoginOutcome, SiteResult, CredentialStatus enums (kept for data compatibility)
- CoordinateInteractionEngine (click mechanics stay the same)
- HardwareTypingEngine (typing stays the same)

---

## Settings Cleanup

- Remove detection-related settings that no longer apply (DOM detection toggles, OCR weight sliders, settlement thresholds, button recovery timeouts, heuristic fallback toggles)
- Keep: Grok API key settings, screenshot capture settings, page load timeout, stealth config

