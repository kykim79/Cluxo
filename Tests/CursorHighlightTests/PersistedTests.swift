import XCTest
import Combine
import SwiftUI

// MARK: - 테스트용 ObservableObject
//
// Persisted는 ObservableObject의 _enclosingInstance subscript로만 동작.
// 격리된 UserDefaults suite를 사용하기 위해 Persisted는 .standard만 쓰므로
// 각 테스트에서 .standard의 키를 정리한다.

@MainActor
final class TestNativeOwner: ObservableObject {
    @Persisted("test_bool", default: false) var flag: Bool
    @Persisted("test_int", default: 42) var count: Int
    @Persisted("test_double", default: 1.0) var ratio: Double
    @Persisted("test_string", default: "default") var label: String
    @Persisted("test_cgfloat", default: CGFloat(10)) var width: CGFloat
    @Persisted("test_uint16", default: UInt16(7)) var code: UInt16
}

@MainActor
final class TestEnumOwner: ObservableObject {
    enum Mode: String, CaseIterable { case a, b, c }
    @Persisted("test_enum", default: Mode.a) var mode: Mode
}

@MainActor
final class TestDebounceOwner: ObservableObject {
    @Persisted("test_debounce", default: 0.0, debounce: 0.1) var value: Double
}

// MARK: - Tests

@MainActor
final class PersistedTests: XCTestCase {
    private let testKeys = [
        "test_bool", "test_int", "test_double", "test_string",
        "test_cgfloat", "test_uint16", "test_enum", "test_debounce",
    ]

    override func setUp() async throws {
        try await super.setUp()
        for key in testKeys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func tearDown() async throws {
        for key in testKeys { UserDefaults.standard.removeObject(forKey: key) }
        try await super.tearDown()
    }

    // MARK: - Native types: 기본값 / write / read 순환

    func test_native_returnsDefaultWhenUnset() {
        let owner = TestNativeOwner()
        XCTAssertEqual(owner.flag, false)
        XCTAssertEqual(owner.count, 42)
        XCTAssertEqual(owner.ratio, 1.0)
        XCTAssertEqual(owner.label, "default")
        XCTAssertEqual(owner.width, 10)
        XCTAssertEqual(owner.code, 7)
    }

    func test_native_writeThenReadAcrossInstances() {
        do {
            let owner = TestNativeOwner()
            owner.flag = true
            owner.count = 123
            owner.ratio = 3.14
            owner.label = "hello"
            owner.width = 50.5
            owner.code = 99
        }
        // 새 instance — UserDefaults에서 다시 로드되어야 함
        let reloaded = TestNativeOwner()
        XCTAssertEqual(reloaded.flag, true)
        XCTAssertEqual(reloaded.count, 123)
        XCTAssertEqual(reloaded.ratio, 3.14, accuracy: 0.0001)
        XCTAssertEqual(reloaded.label, "hello")
        XCTAssertEqual(reloaded.width, 50.5, accuracy: 0.0001)
        XCTAssertEqual(reloaded.code, 99)
    }

    // Bool 특수 케이스: bool(forKey:)는 미저장 시 false 반환. object(forKey:)로 nil/Bool 구분 검증.
    func test_native_boolFalseIsPersistedAndDistinctFromDefault() {
        do {
            let owner = TestNativeOwner()
            owner.flag = false  // default와 같은 값이지만 명시적 set
        }
        let raw = UserDefaults.standard.object(forKey: "test_bool")
        XCTAssertNotNil(raw, "Bool false도 명시적으로 저장되어야 함 (default fallback 회피)")
        XCTAssertEqual(raw as? Bool, false)
    }

    // MARK: - RawRepresentable (enum)

    func test_enum_writeThenReadAcrossInstances() {
        do {
            let owner = TestEnumOwner()
            XCTAssertEqual(owner.mode, .a)  // 기본값
            owner.mode = .c
        }
        let reloaded = TestEnumOwner()
        XCTAssertEqual(reloaded.mode, .c)
    }

    func test_enum_corruptRawValueFallsBackToDefault() {
        UserDefaults.standard.set("nonexistent_case", forKey: "test_enum")
        let owner = TestEnumOwner()
        XCTAssertEqual(owner.mode, .a, "잘못된 raw value는 기본값으로 fallback")
    }

    // MARK: - ObservableObject 통합

    func test_objectWillChangeFiresOnWrite() {
        let owner = TestNativeOwner()
        let exp = expectation(description: "objectWillChange")
        let cancellable = owner.objectWillChange.sink { _ in exp.fulfill() }
        owner.flag = true
        wait(for: [exp], timeout: 1.0)
        cancellable.cancel()
    }

    // MARK: - Debounce

    func test_debounce_writeIsDelayedAndCoalesced() {
        let owner = TestDebounceOwner()
        // 빠르게 여러 번 write
        for v in [1.0, 2.0, 3.0, 4.0, 5.0] { owner.value = v }
        // 즉시 UserDefaults에는 아직 안 적혀야 함 (debounce 0.1s)
        XCTAssertNil(UserDefaults.standard.object(forKey: "test_debounce"),
                     "debounce 기간 안에는 디스크 쓰기가 발생하지 않아야 함")
        // 0.2s 후 마지막 값만 저장
        let exp = expectation(description: "debounce flush")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(UserDefaults.standard.double(forKey: "test_debounce"), 5.0,
                           "debounce flush 후 마지막 값만 저장되어야 함")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
