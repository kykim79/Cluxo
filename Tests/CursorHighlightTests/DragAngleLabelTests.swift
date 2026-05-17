import XCTest
import SwiftUI

/// DragAngleLabel의 순수 변환 함수 검증 — atan2 라디안 → 시계방향 12시 기준 0~359° 정수.
/// standalone test bundle이라 module import 없이 같은 file pool 안에서 직접 호출.
@MainActor
final class DragAngleLabelTests: XCTestCase {

    // MARK: - clockwiseDegrees

    func test_clockwiseDegrees_up() {
        // dx=0, dy=-1 (위로 이동, 화면 좌표) → atan2(-1, 0) = -π/2 → 12시 = 0°
        let radians = atan2(-1.0, 0.0)
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: radians), 0)
    }

    func test_clockwiseDegrees_right() {
        // dx=1, dy=0 → atan2(0, 1) = 0 → 3시 = 90°
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: 0), 90)
    }

    func test_clockwiseDegrees_down() {
        // dx=0, dy=1 (아래) → atan2(1, 0) = π/2 → 6시 = 180°
        let radians = atan2(1.0, 0.0)
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: radians), 180)
    }

    func test_clockwiseDegrees_left() {
        // dx=-1, dy=0 → atan2(0, -1) = π → 9시 = 270°
        let radians = atan2(0.0, -1.0)
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: radians), 270)
    }

    func test_clockwiseDegrees_upperRight() {
        // dx=1, dy=-1 → atan2(-1, 1) = -π/4 (-45°) → 12시+45° = 45°
        let radians = atan2(-1.0, 1.0)
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: radians), 45)
    }

    func test_clockwiseDegrees_lowerLeft() {
        // dx=-1, dy=1 → atan2(1, -1) = 3π/4 (135°) → 12시+225° = 225°
        let radians = atan2(1.0, -1.0)
        XCTAssertEqual(DragAngleLabel.clockwiseDegrees(fromAtan2: radians), 225)
    }

    func test_clockwiseDegrees_alwaysInRange_0to359() {
        // 임의 angle 100개 → 결과 모두 [0, 360) 범위
        for _ in 0..<100 {
            let randomRadians = Double.random(in: -10...10)
            let result = DragAngleLabel.clockwiseDegrees(fromAtan2: randomRadians)
            XCTAssertGreaterThanOrEqual(result, 0)
            XCTAssertLessThan(result, 360)
        }
    }

    // MARK: - directionArrow

    func test_directionArrow_up() {
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 0), "↑")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 22), "↑")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 338), "↑")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 359), "↑")
    }

    func test_directionArrow_upperRight() {
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 23), "↗")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 45), "↗")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 67), "↗")
    }

    func test_directionArrow_right() {
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 90), "→")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 112), "→")
    }

    func test_directionArrow_allEightDirections() {
        // 8방향 모두 표시되는지 — 중심 degree 기준
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 0), "↑")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 45), "↗")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 90), "→")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 135), "↘")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 180), "↓")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 225), "↙")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 270), "←")
        XCTAssertEqual(DragAngleLabel.directionArrow(forCWDegrees: 315), "↖")
    }
}
