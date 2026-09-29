import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) } }
let screen = ANSIScreen()
screen.resize(10, 3)
screen.feed(Data("hello\rOK\u{1b}[K".utf8))
check(screen.grid[0].joined().hasPrefix("OK   "), "CR + erase line must clear old shell text")
screen.reset()
let unicode = Array("你好".utf8)
screen.feed(Data(unicode.prefix(2)))
check(screen.grid[0][0] == " ", "Incomplete UTF8 must wait for next packet")
screen.feed(Data(unicode.dropFirst(2)))
check(screen.grid[0][0] == "你" && screen.grid[0][2] == "好", "Split UTF8 and CJK cells")
screen.feed(Data("\u{1b}[?1049hother\u{1b}[?1049l".utf8))
check(screen.grid[0][0] == "你", "Alternate screen must restore primary content")
screen.resize(80, 24); screen.feed(Data("\u{1b}[24;80H\u{1b}7".utf8)); screen.resize(10, 3); screen.feed(Data("\u{1b}8X".utf8))
check(screen.y < 3 && screen.x < 10, "Saved cursor must stay in bounds after resize")
screen.reset(); screen.feed(Data("one\r\ntwo\r\nthree\r\nfour".utf8))
check(screen.history.count == 1 && screen.history[0].hasPrefix("one"), "Shell scrollback")
let actual = try Pocket.bridgeAddress("https://friendly-space.github.dev")
check(actual == "https://friendly-space-8765.app.github.dev", "Codespace URL conversion")
for bad in ["http://friendly-space.github.dev", "https://friendly-space.github.dev.evil.test", "https://user:password@friendly-space.github.dev", "https://friendly-space.github.dev?token=secret", "https://app.github.dev", "https://friendly-space.github.dev:443", "https://friendly-space.github.dev/arbitrary"] {
    do { _ = try Pocket.bridgeAddress(bad); fatalError("Accepted an unsafe workspace URL") } catch { }
}
print("PASS: native ANSI streaming, Unicode, screen restore, resize bounds, scrollback and credential URL boundaries")
