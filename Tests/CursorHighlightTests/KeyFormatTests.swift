import XCTest
import AppKit

// KeyboardHotkeyHandler.formatKey 의 단축키 포맷팅 검증.
// 핵심: ⌃·⌥·⌘ 중 하나라도 있어야 표시 (단순 타이핑·패스워드 노출 방지).
// 순서: ⌃⌥⇧⌘ (macOS HIG 관례).

@MainActor
final class KeyFormatTests: XCTestCase {

    private func makeEvent(modifiers: NSEvent.ModifierFlags, keyCode: UInt16, chars: String = "") -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: - 모디파이어 게이트 (⌃·⌥·⌘ 없으면 표시 X)

    func test_noModifiersIsEmpty() {
        // 단순 'k' 타이핑은 표시 안 함 (패스워드 노출 방지)
        let e = makeEvent(modifiers: [], keyCode: 40, chars: "k")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "")
    }

    func test_shiftOnlyIsEmpty() {
        // ⇧만으로는 표시 안 함 (대문자 K도 password 노출 위험)
        let e = makeEvent(modifiers: [.shift], keyCode: 40, chars: "K")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "")
    }

    // MARK: - 일반 키 + 모디파이어

    func test_controlOnly() {
        let e = makeEvent(modifiers: [.control], keyCode: 40, chars: "k")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌃K")
    }

    func test_controlOption() {
        let e = makeEvent(modifiers: [.control, .option], keyCode: 40, chars: "k")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌃⌥K")
    }

    func test_commandShift() {
        // ⌘⇧K — 코드의 순서: ⌃⌥⇧⌘
        let e = makeEvent(modifiers: [.command, .shift], keyCode: 40, chars: "k")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⇧⌘K")
    }

    func test_allModifiers() {
        let e = makeEvent(modifiers: [.control, .option, .shift, .command], keyCode: 40, chars: "k")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌃⌥⇧⌘K")
    }

    // MARK: - Special keys (special map)

    func test_specialReturn() {
        let e = makeEvent(modifiers: [.control], keyCode: 36, chars: "\r")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌃↩")
    }

    func test_specialEscape() {
        let e = makeEvent(modifiers: [.option], keyCode: 53, chars: "\u{1B}")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌥⎋")
    }

    func test_specialArrowLeft() {
        let e = makeEvent(modifiers: [.control, .option], keyCode: 123, chars: "")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌃⌥←")
    }

    func test_specialSpace() {
        let e = makeEvent(modifiers: [.command], keyCode: 49, chars: " ")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌘Space")
    }

    func test_specialF1() {
        let e = makeEvent(modifiers: [.command], keyCode: 122, chars: "")
        XCTAssertEqual(KeyboardHotkeyHandler.formatKey(e), "⌘F1")
    }
}
