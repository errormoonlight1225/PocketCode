import Foundation
// Small native ANSI screen for iOS 12, with bounded scrollback. No browser or JS runtime.
// Supports shell editing, cursor motion, erase, scroll regions and alternate screens.
// SGR styling, mouse reporting and advanced terminal graphics are intentionally not emulated.
final class ANSIScreen {
    var cols = 80, rows = 24, x = 0, y = 0, savedX = 0, savedY = 0
    var top = 0, bottom = 23
    var grid = Array(repeating: Array(repeating: " ", count: 80), count: 24)
    var history: [String] = []
    var alternate: [[String]]?
    var state = 0
    var escape = ""
    var pending: [UInt8] = []
    var response: ((Data) -> Void)?
    var wrapPending = false
    var bracketedPaste = false
    func reset() { grid = Array(repeating: blank(), count: rows); x = 0; y = 0; top = 0; bottom = rows - 1; state = 0; history = []; alternate = nil; wrapPending = false; bracketedPaste = false }
    func blank() -> [String] { Array(repeating: " ", count: cols) }
    func resize(_ width: Int, _ height: Int) {
        let width = max(10, width), height = max(3, height)
        guard width != cols || height != rows else { return }
        // Keep the cursor and bottom output visible when the keyboard reduces the rows.
        let removed = max(0, y - height + 1)
        if removed > 0 {
            if alternate == nil { history.append(contentsOf: grid.prefix(removed).map { $0.joined() }); trimHistory() }
            grid.removeFirst(removed); y -= removed; savedY = max(0, savedY - removed)
        }
        cols = width; rows = height
        grid = Array(grid.prefix(rows)).map { Array(($0 + blank()).prefix(cols)) }
        while grid.count < rows { grid.append(blank()) }
        if let a = alternate { var b = Array(a.prefix(rows)).map { Array(($0 + blank()).prefix(cols)) }; while b.count < rows { b.append(blank()) }; alternate = b }
        x = min(x, cols - 1); y = min(y, rows - 1); savedX = min(savedX, cols - 1); savedY = min(savedY, rows - 1)
        top = 0; bottom = rows - 1; wrapPending = false
    }
    func trimHistory() { if history.count > 2000 { history.removeFirst(history.count - 2000) } }
    func pasteData(_ text: String) -> Data {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let value = bracketedPaste ? "\u{1b}[200~" + normalized + "\u{1b}[201~" : normalized.replacingOccurrences(of: "\n", with: "\r")
        return Data(value.utf8)
    }
    var cursorOffset: Int {
        let lines = (alternate == nil ? history : []) + grid.prefix(y).map { $0.joined() }
        return lines.reduce(0) { $0 + $1.utf16.count + 1 } + grid[y].prefix(x).joined().utf16.count
    }
    func scroll() {
        let removed = grid.remove(at: top)
        if top == 0 && bottom == rows - 1 && alternate == nil { history.append(removed.joined()); trimHistory() }
        grid.insert(blank(), at: bottom)
    }
    func newline() { if y == bottom { scroll() } else { y = min(rows - 1, y + 1) }; wrapPending = false }
    func write(_ scalar: UnicodeScalar) {
        let n = scalar.value
        if state == 3 { if n == 7 { state = 0 } else if n == 27 { state = 4 }; return }
        if state == 4 { state = n == 92 ? 0 : 3; return }
        if state == 5 { state = 0; return }
        if state == 1 {
            state = 0
            switch n {
            case 91: state = 2; escape = ""
            case 93: state = 3
            case 40, 41: state = 5
            case 55: savedX = x; savedY = y
            case 56: x = min(cols - 1, savedX); y = min(rows - 1, savedY)
            case 68: newline()
            case 77: if y == top { grid.remove(at: bottom); grid.insert(blank(), at: top) } else { y = max(0, y - 1) }
            case 99: reset()
            default: break
            }; return
        }
        if state == 2 {
            if (64...126).contains(n) { csi(Character(String(scalar))); state = 0; escape = "" }
            else if escape.count < 128 { escape.append(Character(String(scalar))) } else { state = 0 }; return
        }
        switch n {
        case 27: state = 1
        case 13: x = 0; wrapPending = false
        case 10, 11, 12: newline()
        case 8: x = max(0, x - 1); wrapPending = false
        case 9: x = min(cols - 1, ((x / 8) + 1) * 8)
        case 0...31, 127: break
        default:
            if CharacterSet.nonBaseCharacters.contains(scalar) { grid[y][max(0, x - 1)] += String(scalar); return }
            let wide = n >= 0x1100 && (n <= 0x115F || (n >= 0x2E80 && n <= 0xA4CF) || (n >= 0xAC00 && n <= 0xD7A3) || (n >= 0xF900 && n <= 0xFAFF) || (n >= 0xFF01 && n <= 0xFF60) || n >= 0x1F300)
            if wrapPending || (wide && x == cols - 1) { x = 0; newline() }
            grid[y][x] = String(scalar)
            if wide && x + 1 < cols { grid[y][x + 1] = "" }
            let next = x + (wide ? 2 : 1); wrapPending = next >= cols; x = min(cols - 1, next)
        }
    }
    func csi(_ final: Character) {
        let privateMode = escape.hasPrefix("?")
        let parts = escape.trimmingCharacters(in: CharacterSet(charactersIn: "?>!" )).split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let n = max(1, parts.first ?? 1)
        func at(_ i: Int) -> Int { i < parts.count ? parts[i] : 0 }
        switch final {
        case "A": y = max(0, y - n)
        case "B": y = min(rows - 1, y + n)
        case "C": x = min(cols - 1, x + n)
        case "D": x = max(0, x - n)
        case "E": y = min(rows - 1, y + n); x = 0
        case "F": y = max(0, y - n); x = 0
        case "G", "`": x = min(cols - 1, n - 1)
        case "d": y = min(rows - 1, n - 1)
        case "H", "f": y = min(rows - 1, max(0, at(0) - 1)); x = min(cols - 1, max(0, at(1) - 1))
        case "J":
            if at(0) == 2 || at(0) == 3 { grid = Array(repeating: blank(), count: rows); if at(0) == 3 { history = [] } }
            else if at(0) == 0 { for col in x..<cols { grid[y][col] = " " }; if y + 1 < rows { for row in (y + 1)..<rows { grid[row] = blank() } } }
            else if at(0) == 1 { for col in 0...x { grid[y][col] = " " }; if y > 0 { for row in 0..<y { grid[row] = blank() } } }
        case "K": let range = at(0) == 0 ? x..<cols : at(0) == 1 ? 0..<(x + 1) : 0..<cols; for col in range { grid[y][col] = " " }
        case "P": for _ in 0..<min(n, cols - x) { grid[y].remove(at: x); grid[y].append(" ") }
        case "@": for _ in 0..<min(n, cols - x) { grid[y].insert(" ", at: x); grid[y].removeLast() }
        case "X": for col in x..<min(cols, x + n) { grid[y][col] = " " }
        case "L": if y >= top && y <= bottom { for _ in 0..<min(n, bottom - y + 1) { grid.remove(at: bottom); grid.insert(blank(), at: y) } }
        case "M": if y >= top && y <= bottom { for _ in 0..<min(n, bottom - y + 1) { grid.remove(at: y); grid.insert(blank(), at: bottom) } }
        case "S": for _ in 0..<min(n, rows) { scroll() }
        case "T": for _ in 0..<min(n, rows) { grid.remove(at: bottom); grid.insert(blank(), at: top) }
        case "r": top = min(rows - 1, max(0, at(0) - 1)); bottom = at(1) == 0 ? rows - 1 : min(rows - 1, max(top, at(1) - 1)); x = 0; y = 0
        case "s": savedX = x; savedY = y
        case "u": x = min(cols - 1, savedX); y = min(rows - 1, savedY)
        case "n": if at(0) == 6 { response?(Data("\u{1b}[\(y + 1);\(x + 1)R".utf8)) } else if at(0) == 5 { response?(Data("\u{1b}[0n".utf8)) }
        case "c": response?(Data("\u{1b}[?1;2c".utf8))
        case "h", "l":
            if privateMode && parts.contains(2004) { bracketedPaste = final == "h" }
            if privateMode && parts.contains(where: { [47, 1047, 1049].contains($0) }) {
            if final == "h" && alternate == nil { alternate = grid; savedX = x; savedY = y; grid = Array(repeating: blank(), count: rows); x = 0; y = 0 }
            else if final == "l", let old = alternate { grid = old; alternate = nil; x = min(cols - 1, savedX); y = min(rows - 1, savedY) }
        }
        default: break
        }; if final != "m" { wrapPending = false }
    }
    func feed(_ data: Data) {
        pending.append(contentsOf: data); var i = 0
        while i < pending.count {
            let b = pending[i]; let count = b < 0x80 ? 1 : b >= 0xC2 && b <= 0xDF ? 2 : b <= 0xEF && b >= 0xE0 ? 3 : b <= 0xF4 && b >= 0xF0 ? 4 : 1
            if i + count > pending.count { break }
            let bytes = Array(pending[i..<(i + count)])
            for s in String(decoding: bytes, as: UTF8.self).unicodeScalars { write(s) }; i += count
        }; pending.removeFirst(i)
    }
    var text: String { ((alternate == nil ? history : []) + grid.map { $0.joined() }).joined(separator: "\n") }
}
