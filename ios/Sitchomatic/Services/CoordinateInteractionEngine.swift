import Foundation

@MainActor
class CoordinateInteractionEngine {
    static let shared = CoordinateInteractionEngine()

    private let logger = DebugLogger.shared

    nonisolated struct ElementRect: Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let tag: String
        let visible: Bool

        var centerX: Double { x + width / 2.0 }
        var centerY: Double { y + height / 2.0 }
        var isValid: Bool { width > 0 && height > 0 && visible }
    }

    nonisolated struct ClickResult: Sendable {
        let success: Bool
        let method: String
        let coordinates: (x: Double, y: Double)?
    }

    private func gaussianJitter(range: Int) -> Double {
        let u1 = Double.random(in: 0.0001...0.9999)
        let u2 = Double.random(in: 0.0001...0.9999)
        let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let jitter = z * (Double(range) / 3.0)
        return max(Double(-range), min(Double(range), jitter))
    }

    func locateElement(
        selectors: [String],
        executeJS: @escaping (String) async -> String?,
        timeoutMs: Int = 1000
    ) async -> ElementRect? {
        let selectorArray = selectors.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" }.joined(separator: ",")
        let js = """
        (function(){
            var sels = [\(selectorArray)];
            for(var i=0;i<sels.length;i++){
                try{
                    var el=document.querySelector(sels[i]);
                    if(!el) continue;
                    var r=el.getBoundingClientRect();
                    if(r.width===0||r.height===0) continue;
                    var vis=el.offsetParent!==null||el.offsetHeight>0||el.offsetWidth>0;
                    if(!vis&&el.style.display!=='none'){vis=true;}
                    return JSON.stringify({x:r.left,y:r.top,w:r.width,h:r.height,tag:el.tagName,vis:vis,sel:sels[i]});
                }catch(e){}
            }
            return 'NOT_FOUND';
        })()
        """

        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            guard let raw = await executeJS(js), raw != "NOT_FOUND",
                  let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if Date().timeIntervalSince(start) * 1000 >= Double(timeoutMs) { break }
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            let rect = ElementRect(
                x: json["x"] as? Double ?? 0,
                y: json["y"] as? Double ?? 0,
                width: json["w"] as? Double ?? 0,
                height: json["h"] as? Double ?? 0,
                tag: json["tag"] as? String ?? "",
                visible: json["vis"] as? Bool ?? false
            )
            if rect.isValid { return rect }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func coordinateClick(
        rect: ElementRect,
        executeJS: @escaping (String) async -> String?,
        jitterPx: Int = 3,
        hoverDwellMs: Int = 0,
        sessionId: String = ""
    ) async -> ClickResult {
        let jx = gaussianJitter(range: jitterPx)
        let jy = gaussianJitter(range: jitterPx)
        let cx = max(rect.x + 1, min(rect.x + rect.width - 1, rect.centerX + jx))
        let cy = max(rect.y + 1, min(rect.y + rect.height - 1, rect.centerY + jy))

        let moveJS = buildMouseMoveJS(targetX: cx, targetY: cy, rect: rect)
        _ = await executeJS(moveJS)

        let pointerDownJS = buildPointerEventJS(type: "pointerdown", x: cx, y: cy, button: 0, buttons: 1)
        _ = await executeJS(pointerDownJS)
        let mouseDownJS = buildMouseEventJS(type: "mousedown", x: cx, y: cy, button: 0, buttons: 1)
        _ = await executeJS(mouseDownJS)

        if hoverDwellMs > 0 {
            try? await Task.sleep(for: .milliseconds(hoverDwellMs))
        }

        let pointerUpJS = buildPointerEventJS(type: "pointerup", x: cx, y: cy, button: 0, buttons: 0)
        _ = await executeJS(pointerUpJS)
        let mouseUpJS = buildMouseEventJS(type: "mouseup", x: cx, y: cy, button: 0, buttons: 0)
        _ = await executeJS(mouseUpJS)
        let clickJS = buildMouseEventJS(type: "click", x: cx, y: cy, button: 0, buttons: 0)
        _ = await executeJS(clickJS)

        return ClickResult(success: true, method: "coordinate_dispatch@\(Int(cx)),\(Int(cy))", coordinates: (cx, cy))
    }

    func coordinateClickWithFallback(
        primarySelectors: [String],
        fallbackSelectors: [String],
        executeJS: @escaping (String) async -> String?,
        jitterPx: Int = 3,
        hoverDwellMs: Int = 0,
        sessionId: String = ""
    ) async -> ClickResult {
        if let rect = await locateElement(selectors: primarySelectors, executeJS: executeJS, timeoutMs: 1000) {
            logger.log("CoordEngine: located via primary selectors at (\(Int(rect.centerX)),\(Int(rect.centerY)))", category: .automation, level: .trace, sessionId: sessionId)
            return await coordinateClick(rect: rect, executeJS: executeJS, jitterPx: jitterPx, hoverDwellMs: hoverDwellMs, sessionId: sessionId)
        }

        if let rect = await locateElement(selectors: fallbackSelectors, executeJS: executeJS, timeoutMs: 500) {
            logger.log("CoordEngine: located via fallback selectors at (\(Int(rect.centerX)),\(Int(rect.centerY)))", category: .automation, level: .warning, sessionId: sessionId)
            return await coordinateClick(rect: rect, executeJS: executeJS, jitterPx: jitterPx, hoverDwellMs: hoverDwellMs, sessionId: sessionId)
        }

        logger.log("CoordEngine: element NOT_FOUND via any selector", category: .automation, level: .error, sessionId: sessionId)
        return ClickResult(success: false, method: "NOT_FOUND", coordinates: nil)
    }

    func coordinateFocusField(
        selectors: [String],
        executeJS: @escaping (String) async -> String?,
        jitterPx: Int = 2,
        sessionId: String = ""
    ) async -> Bool {
        guard let rect = await locateElement(selectors: selectors, executeJS: executeJS, timeoutMs: 1000) else {
            return false
        }
        let result = await coordinateClick(rect: rect, executeJS: executeJS, jitterPx: jitterPx, sessionId: sessionId)
        return result.success
    }

    func waitForButtonStable(
        selectors: [String],
        executeJS: @escaping (String) async -> String?,
        stabilityMs: Int = 300,
        timeoutMs: Int = 5000,
        sessionId: String = ""
    ) async -> ElementRect? {
        var lastRect: ElementRect?
        var stableStart: Date?
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)

        while Date() < deadline {
            guard let rect = await locateElement(selectors: selectors, executeJS: executeJS, timeoutMs: 200) else {
                lastRect = nil
                stableStart = nil
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            if let last = lastRect,
               abs(rect.x - last.x) < 2 && abs(rect.y - last.y) < 2 &&
               abs(rect.width - last.width) < 2 && abs(rect.height - last.height) < 2 {
                if let start = stableStart {
                    if Date().timeIntervalSince(start) * 1000 >= Double(stabilityMs) {
                        return rect
                    }
                } else {
                    stableStart = Date()
                }
            } else {
                stableStart = Date()
            }

            lastRect = rect
            try? await Task.sleep(for: .milliseconds(50))
        }

        return lastRect
    }

    func checkNetworkIdle(executeJS: @escaping (String) async -> String?, timeoutMs: Int = 5000) async -> Bool {
        let js = """
        (function(){
            return document.readyState === 'complete' ? 'IDLE' : document.readyState;
        })()
        """
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            let result = await executeJS(js)
            if result == "IDLE" { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    nonisolated struct TripleClickResult: Sendable {
        let success: Bool
        let clicksCompleted: Int
        let method: String
    }

    func tripleClickWithEscalatingDwell(
        selectors: [String],
        fallbackSelectors: [String] = [],
        executeJS: @escaping (String) async -> String?,
        jitterPx: Int = 3,
        sessionId: String = ""
    ) async -> TripleClickResult {
        let allSelectors = selectors + fallbackSelectors
        guard let rect = await locateElement(selectors: allSelectors, executeJS: executeJS, timeoutMs: 1500) else {
            logger.log("TripleClick: button NOT_FOUND", category: .automation, level: .error, sessionId: sessionId)
            return TripleClickResult(success: false, clicksCompleted: 0, method: "NOT_FOUND")
        }

        let dwellRanges: [(min: Int, max: Int)] = [
            (80, 150),
            (200, 400),
            (500, 900)
        ]
        let interClickDelays: [(min: Int, max: Int)] = [
            (300, 600),
            (400, 800)
        ]

        var completed = 0
        for (idx, dwell) in dwellRanges.enumerated() {
            guard !Task.isCancelled else { break }

            let dwellMs = Int.random(in: dwell.min...dwell.max)
            let freshRect = await locateElement(selectors: allSelectors, executeJS: executeJS, timeoutMs: 500) ?? rect

            let result = await coordinateClick(
                rect: freshRect,
                executeJS: executeJS,
                jitterPx: jitterPx,
                hoverDwellMs: dwellMs,
                sessionId: sessionId
            )
            if result.success {
                completed += 1
                logger.log("TripleClick: click \(idx + 1)/3 @ dwell \(dwellMs)ms", category: .automation, level: .trace, sessionId: sessionId)
            }

            if idx < interClickDelays.count {
                let delay = interClickDelays[idx]
                try? await Task.sleep(for: .milliseconds(Int.random(in: delay.min...delay.max)))
            }
        }

        let success = completed >= 2
        logger.log("TripleClick: \(completed)/3 clicks completed — \(success ? "OK" : "PARTIAL")", category: .automation, level: success ? .info : .warning, sessionId: sessionId)
        return TripleClickResult(success: success, clicksCompleted: completed, method: "triple_escalating_dwell")
    }

    private func buildMouseMoveJS(targetX: Double, targetY: Double, rect: ElementRect) -> String {
        let startX = rect.x - 40.0 - Double.random(in: 0...60)
        let startY = rect.y + Double.random(in: -10...10)
        let steps = Int.random(in: 5...9)
        return """
        (function(){
            var startX=\(startX),startY=\(startY),endX=\(targetX),endY=\(targetY),steps=\(steps);
            for(var i=0;i<=steps;i++){
                var t=i/steps;var bt=t*t*(3-2*t);
                var mx=startX+(endX-startX)*bt+(Math.random()*2-1);
                var my=startY+(endY-startY)*bt+(Math.random()*2-1);
                var el=document.elementFromPoint(mx,my);
                if(el){try{el.dispatchEvent(new MouseEvent('mousemove',{bubbles:true,clientX:mx,clientY:my}));}catch(e){}}
            }
            return 'MOVED';
        })()
        """
    }

    private func buildPointerEventJS(type: String, x: Double, y: Double, button: Int, buttons: Int) -> String {
        """
        (function(){
            var el=document.elementFromPoint(\(x),\(y));
            if(!el)return'NO_EL';
            el.dispatchEvent(new PointerEvent('\(type)',{bubbles:true,cancelable:true,clientX:\(x),clientY:\(y),pointerId:1,pointerType:'mouse',button:\(button),buttons:\(buttons),view:window}));
            return'OK';
        })()
        """
    }

    private func buildMouseEventJS(type: String, x: Double, y: Double, button: Int, buttons: Int) -> String {
        """
        (function(){
            var el=document.elementFromPoint(\(x),\(y));
            if(!el)return'NO_EL';
            el.dispatchEvent(new MouseEvent('\(type)',{bubbles:true,cancelable:true,clientX:\(x),clientY:\(y),button:\(button),buttons:\(buttons),view:window}));
            return'OK';
        })()
        """
    }
}
