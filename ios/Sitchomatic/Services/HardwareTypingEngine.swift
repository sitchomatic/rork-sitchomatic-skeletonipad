import Foundation

@MainActor
class HardwareTypingEngine {
    static let shared = HardwareTypingEngine()

    private let logger = DebugLogger.shared
    private let coordEngine = CoordinateInteractionEngine.shared

    private let typoProbability: Double = 0.02
    private let typoChars = "abcdefghijklmnopqrstuvwxyz"

    private func gaussianDelay(minMs: Int, maxMs: Int) -> Int {
        let mean = Double(minMs + maxMs) / 2.0
        let stdDev = Double(maxMs - minMs) / 4.0
        let u1 = Double.random(in: 0.0001...0.9999)
        let u2 = Double.random(in: 0.0001...0.9999)
        let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let delay = mean + z * stdDev
        return max(minMs, min(maxMs, Int(delay)))
    }

    func focusAndType(
        fieldSelectors: [String],
        text: String,
        executeJS: @escaping (String) async -> String?,
        minKeystrokeMs: Int = 50,
        maxKeystrokeMs: Int = 150,
        sessionId: String = ""
    ) async -> Bool {
        let focused = await coordEngine.coordinateFocusField(
            selectors: fieldSelectors,
            executeJS: executeJS,
            jitterPx: 2,
            sessionId: sessionId
        )
        guard focused else {
            logger.log("HWTyping: focus FAILED for selectors", category: .automation, level: .error, sessionId: sessionId)
            return false
        }

        try? await Task.sleep(for: .milliseconds(Int.random(in: 80...220)))

        let cleared = await clearActiveField(executeJS: executeJS)
        if !cleared {
            logger.log("HWTyping: clear field failed — proceeding anyway", category: .automation, level: .warning, sessionId: sessionId)
        }

        var charIndex = 0
        let chars = Array(text)

        while charIndex < chars.count {
            guard !Task.isCancelled else { return false }

            if charIndex > 2 && Double.random(in: 0...1) < typoProbability {
                let typoChar = typoChars.randomElement()!
                let typoTyped = await typeKeystroke(char: typoChar, executeJS: executeJS)
                if typoTyped {
                    logger.log("HWTyping: deliberate typo '\(typoChar)' at pos \(charIndex)", category: .automation, level: .trace, sessionId: sessionId)
                    try? await Task.sleep(for: .milliseconds(gaussianDelay(minMs: 150, maxMs: 400)))
                    _ = await typeBackspace(executeJS: executeJS)
                    try? await Task.sleep(for: .milliseconds(gaussianDelay(minMs: 100, maxMs: 300)))
                }
            }

            let char = chars[charIndex]
            let typed = await typeKeystroke(char: char, executeJS: executeJS)
            if !typed {
                logger.log("HWTyping: keystroke FAILED at index \(charIndex)", category: .automation, level: .warning, sessionId: sessionId)
                return false
            }

            let delay = gaussianDelay(minMs: minKeystrokeMs, maxMs: maxKeystrokeMs)
            if charIndex > 0 && charIndex % Int.random(in: 4...8) == 0 {
                let thinkPause = gaussianDelay(minMs: 200, maxMs: 500)
                try? await Task.sleep(for: .milliseconds(delay + thinkPause))
            } else {
                try? await Task.sleep(for: .milliseconds(delay))
            }

            charIndex += 1
        }

        let verified = await verifyFieldLength(executeJS: executeJS, expectedLength: text.count)
        if !verified {
            logger.log("HWTyping: verification failed — expected \(text.count) chars", category: .automation, level: .warning, sessionId: sessionId)
        }
        return verified
    }

    private func typeKeystroke(char: Character, executeJS: @escaping (String) async -> String?) async -> Bool {
        let charStr = String(char)
        let escaped = escapeJS(charStr)
        let keyCode = charKeyCode(char)
        let code = charCodeString(char)

        let js = """
        (function(){
            var el=document.activeElement;
            if(!el||!(el.tagName==='INPUT'||el.tagName==='TEXTAREA'))return'NO_ACTIVE';
            el.dispatchEvent(new KeyboardEvent('keydown',{key:'\(escaped)',code:'\(code)',keyCode:\(keyCode),which:\(keyCode),bubbles:true,cancelable:true}));
            el.dispatchEvent(new KeyboardEvent('keypress',{key:'\(escaped)',code:'\(code)',keyCode:\(keyCode),which:\(keyCode),bubbles:true,cancelable:true,charCode:\(keyCode)}));
            var ns=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
            var cur=el.value||'';
            var nv=cur+'\(escaped)';
            if(ns&&ns.set){ns.set.call(el,nv);}else{el.value=nv;}
            el.dispatchEvent(new InputEvent('input',{bubbles:true,cancelable:false,inputType:'insertText',data:'\(escaped)'}));
            el.dispatchEvent(new KeyboardEvent('keyup',{key:'\(escaped)',code:'\(code)',keyCode:\(keyCode),which:\(keyCode),bubbles:true}));
            return'TYPED';
        })()
        """
        let result = await executeJS(js)
        return result == "TYPED"
    }

    private func typeBackspace(executeJS: @escaping (String) async -> String?) async -> Bool {
        let js = """
        (function(){
            var el=document.activeElement;
            if(!el)return'NO_EL';
            el.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',code:'Backspace',keyCode:8,which:8,bubbles:true,cancelable:true}));
            var ns=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
            var nv=(el.value||'').slice(0,-1);
            if(ns&&ns.set){ns.set.call(el,nv);}else{el.value=nv;}
            el.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'deleteContentBackward'}));
            el.dispatchEvent(new KeyboardEvent('keyup',{key:'Backspace',code:'Backspace',keyCode:8,which:8,bubbles:true}));
            return'BS';
        })()
        """
        let result = await executeJS(js)
        return result == "BS"
    }

    private func clearActiveField(executeJS: @escaping (String) async -> String?) async -> Bool {
        let js = """
        (function(){
            var el=document.activeElement;
            if(!el||!(el.tagName==='INPUT'||el.tagName==='TEXTAREA'))return'NO_ACTIVE';
            var ns=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
            if(ns&&ns.set){ns.set.call(el,'');}else{el.value='';}
            el.dispatchEvent(new Event('input',{bubbles:true}));
            return'CLEARED';
        })()
        """
        let result = await executeJS(js)
        return result == "CLEARED"
    }

    private func verifyFieldLength(executeJS: @escaping (String) async -> String?, expectedLength: Int) async -> Bool {
        let js = "(function(){var el=document.activeElement;if(!el)return'0';return(el.value||'').length.toString();})()"
        let result = await executeJS(js)
        let typedLen = Int(result ?? "0") ?? 0
        return typedLen >= expectedLength
    }

    private func escapeJS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func charKeyCode(_ char: Character) -> Int {
        let s = String(char).uppercased()
        guard let ascii = s.unicodeScalars.first?.value else { return 0 }
        if ascii >= 65 && ascii <= 90 { return Int(ascii) }
        if ascii >= 48 && ascii <= 57 { return Int(ascii) }
        switch char {
        case "@": return 50
        case ".": return 190
        case "-", "_": return 189
        case "!": return 49
        case "#": return 51
        case "$": return 52
        case "%": return 53
        case "&": return 55
        case "*": return 56
        case "+", "=": return 187
        default: return Int(ascii)
        }
    }

    private func charCodeString(_ char: Character) -> String {
        let upper = String(char).uppercased()
        if char.isLetter { return "Key\(upper)" }
        if char.isNumber { return "Digit\(char)" }
        switch char {
        case "@": return "Digit2"
        case ".": return "Period"
        case "-", "_": return "Minus"
        case " ": return "Space"
        case "!": return "Digit1"
        case "#": return "Digit3"
        case "$": return "Digit4"
        default: return "Key\(upper)"
        }
    }
}
