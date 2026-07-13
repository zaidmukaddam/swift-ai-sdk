import Foundation

public enum PartialJSON {
    public static func parse(_ text: String) -> JSONValue? {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        input = stripMarkdownFences(input)
        guard !input.isEmpty else { return nil }

        if let value = decode(input) { return value }

        var candidate = input
        for _ in 0..<40 {
            if let repaired = repair(candidate), let value = decode(repaired) {
                return value
            }
            guard let shorter = truncateAtLastBoundary(candidate) else { return nil }
            candidate = shorter
        }
        return nil
    }

    private static func decode(_ s: String) -> JSONValue? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func stripMarkdownFences(_ s: String) -> String {
        var out = s
        if out.hasPrefix("```") {
            if let newline = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: newline)...])
            } else {
                return ""
            }
        }
        if let fence = out.range(of: "```", options: .backwards) {
            out = String(out[..<fence.lowerBound])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func repair(_ s: String) -> String? {
        var stack: [Character] = []
        var inString = false
        var escaped = false

        for ch in s {
            if escaped { escaped = false; continue }
            if inString {
                if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "{", "[": stack.append(ch)
            case "}": if stack.last == "{" { stack.removeLast() } else { return nil }
            case "]": if stack.last == "[" { stack.removeLast() } else { return nil }
            case "\"": inString = true
            default: break
            }
        }

        var out = s
        if escaped { out.removeLast() }
        if inString { out.append("\"") }

        out = repairTail(out)

        for open in stack.reversed() {
            out.append(open == "{" ? "}" : "]")
        }
        return out
    }

    private static func repairTail(_ s: String) -> String {
        var out = s

        func trimTrailingWhitespace() {
            while let last = out.last, last.isWhitespace { out.removeLast() }
        }

        trimTrailingWhitespace()

        for keyword in ["true", "false", "null"] {
            for length in 1..<keyword.count {
                let prefix = String(keyword.prefix(length))
                if out.hasSuffix(prefix), !endsInsideStringOrWord(out, suffixLength: length) {
                    out.append(contentsOf: keyword.dropFirst(length))
                    return out
                }
            }
        }

        while let last = out.last, "+-.eE".contains(last) {
            out.removeLast()
            trimTrailingWhitespace()
        }

        trimTrailingWhitespace()
        if out.hasSuffix(",") { out.removeLast(); trimTrailingWhitespace() }
        if out.hasSuffix(":") { out.append(" null") }
        return out
    }

    private static func endsInsideStringOrWord(_ s: String, suffixLength: Int) -> Bool {
        let head = s.dropLast(suffixLength)
        guard let prev = head.last else { return false }
        return prev.isLetter || prev.isNumber || prev == "\"" || prev == "_"
    }

    private static func truncateAtLastBoundary(_ s: String) -> String? {
        guard let idx = s.lastIndex(where: { $0 == "," || $0 == "{" || $0 == "[" }) else {
            return nil
        }
        if s[idx] == "," {
            return String(s[..<idx])
        }
        let after = s.index(after: idx)
        guard after != s.startIndex else { return nil }
        let candidate = String(s[..<after])
        return candidate == s ? nil : candidate
    }
}
