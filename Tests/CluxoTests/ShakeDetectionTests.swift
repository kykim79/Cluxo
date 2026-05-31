import XCTest
import CoreGraphics

// ShakeState.record(x:y:at:) — 마우스 흔들기 감지 알고리즘 검증.
//
// 감지 조건 (각 축 독립):
//   - 인접 샘플 속도 |v| > 900 pt/s
//   - 이전 속도 |값| > 900 + 부호 반대 (방향 전환)
//   - 0.5초 안에 방향 전환 5회 누적 → detected
//   - dedup: detect 후 0.5초 안엔 재발화 차단
//
// 일반 마우스 이동의 오발동을 막기 위해 둔감하게(속도 900 + 전환 5회) 설정.
// 모든 테스트는 시간을 명시적으로 주입해 wall clock 의존성 없음.
//
// 진동 한 번분 = 0,amp,0,amp,0,amp,0 (7 records). dt=0.05·amp=100이면 |v|=2000(>900):
//   record2 lastV 설정 → record3 dc=1 → … → record7 dc=5 → detect.

final class ShakeDetectionTests: XCTestCase {

    // MARK: - 경계 케이스

    func test_emptyStateNoDetection() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0))
    }

    func test_firstSampleNeverDetects() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
    }

    func test_singleFastMoveDoesNotDetect() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0.05))   // vx=+2000, lastV=0 → lastV 설정만
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0.10))     // vx=-2000 → dirChanges=1
    }

    // MARK: - 수평 흔들기 (좌우) — 방향 전환 5회 누적해야 detect

    func test_horizontalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // lastV=+2000
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // dirChanges=2
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=3
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // dirChanges=4
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "좌우 빠른 진동 5회 → detect")                  // dirChanges=5
    }

    // MARK: - 수직 흔들기 (위아래) — 우세축이 y로 잡혀야 함

    func test_verticalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 0, y: 100, at: t)); t += dt   // vy=+2000, lastV 설정
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=1
        XCTAssertFalse(state.record(x: 0, y: 100, at: t)); t += dt   // dirChanges=2
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=3
        XCTAssertFalse(state.record(x: 0, y: 100, at: t)); t += dt   // dirChanges=4
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "위아래 빠른 진동 5회 → detect (우세축이 y)")     // dirChanges=5
    }

    // MARK: - 대각선 흔들기 — 더 큰 축이 우세축

    func test_diagonalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        // x=100, y=200 → dominant axis = y (vy=±4000)
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 200, at: t)); t += dt   // lastV 설정
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 200, at: t)); t += dt   // dirChanges=2
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // dirChanges=3
        XCTAssertFalse(state.record(x: 100, y: 200, at: t)); t += dt   // dirChanges=4
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "대각선 빠른 진동 — 우세축 기반 detect")           // dirChanges=5
    }

    // MARK: - 음수 부호도 정상 처리

    func test_verticalShakeNegativeY() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 0, y: -100, at: t)); t += dt    // vy=-2000, lastV 설정
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // dirChanges=1
        XCTAssertFalse(state.record(x: 0, y: -100, at: t)); t += dt    // dirChanges=2
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // dirChanges=3
        XCTAssertFalse(state.record(x: 0, y: -100, at: t)); t += dt    // dirChanges=4
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "수직 음수 방향에서도 detect")                     // dirChanges=5
    }

    // MARK: - 카운터 리셋 (detect 후) — dedup window(0.5초) 통과 후 추가 진동 필요

    func test_counterResetsAfterDetection() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 0, y: 0, at: t), "7번째에서 detect (전환 5회)")
        // dedup window 통과 + 다음 진동 시퀀스
        t += 0.6
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 100, y: 0, at: t),
                      "dedup window 후 새 진동에서 다시 detect")
    }

    // MARK: - Dedup window — detect 직후 0.5초 안에 추가 detect 없음

    func test_dedupWithinHalfSecond() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        // 첫 detect (전환 5회)
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 0, y: 0, at: t), "첫 detect"); t += dt
        // 즉시 다음 진동 — dedup window 안이라 detect 안 됨
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertFalse(state.record(x: 0, y: 0, at: t),
                       "dedup window(0.5초) 안엔 추가 detect 차단")
    }

    // MARK: - 대각선 흔들기에서 한 진동당 한 번만 detect (양 축 동시 trigger 회피)

    func test_diagonalDetectsOnlyOncePerShake() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        var detectionCount = 0
        // 좌하↔우상 동조형 대각선 — 양 축 동시 trigger되지만 dedup으로 한 번만
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 100, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 100, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 100, at: t); t += dt
        if state.record(x: 0, y: 0, at: t) { detectionCount += 1 }; t += dt
        // 같은 진동 계속 — dedup window 안이라 더 detect 안 되어야
        _ = state.record(x: 100, y: 100, at: t); t += dt
        if state.record(x: 0, y: 0, at: t) { detectionCount += 1 }; t += dt
        XCTAssertEqual(detectionCount, 1,
                       "대각선 동조 진동에서도 한 번만 detect (양 축 dedup)")
    }

    // MARK: - 느린 움직임 / 가만히

    func test_slowMovementNoDetection() {
        var state = ShakeState()
        let dt = 0.05
        let small: CGFloat = 5     // |v| = 100 — 임계 150 미만이라 방향 전환으로 안 침
        var t = 0.0
        for _ in 0..<10 {
            XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
            XCTAssertFalse(state.record(x: small, y: small, at: t)); t += dt
        }
    }

    // MARK: - 전환 4회까지는 미감지 (5회 요구 회귀 방지)

    func test_fourDirChangesNotEnough() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // lastV 설정
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // dirChanges=2
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=3
        XCTAssertFalse(state.record(x: 100, y: 0, at: t),
                       "방향 전환 4회까지는 detect 안 됨")             // dirChanges=4
    }

    // MARK: - 민감도 설정(requiredDirChanges) 주입

    func test_sensitiveDetectsWithFewerShakes() {
        var state = ShakeState()
        state.requiredDirChanges = 3   // 민감 — 전환 3회에 detect
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // lastV 설정
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // dirChanges=2
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "민감(3회)에서는 전환 3회에 detect")             // dirChanges=3
    }

    func test_insensitiveRequiresMoreShakes() {
        var state = ShakeState()
        state.requiredDirChanges = 8   // 둔감 — 전환 8회 요구
        let dt = 0.05
        var t = 0.0
        // 전환 5회까지 진행(보통이면 detect되는 양) — 둔감에선 미감지여야
        let xs: [CGFloat] = [0, 100, 0, 100, 0, 100, 0]
        var detected = false
        for x in xs { detected = state.record(x: x, y: 0, at: t) || detected; t += dt }
        XCTAssertFalse(detected, "둔감(8회)에서는 전환 5회로 미감지")
    }

    // MARK: - 긴 갭 후 카운터 리셋

    func test_gapDuringShakePreventsDetection() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt              // dirChanges=1
        _ = state.record(x: 100, y: 0, at: t); t += dt            // dirChanges=2
        t += 0.6                                                    // 긴 갭
        XCTAssertFalse(state.record(x: 0, y: 0, at: t),
                       "긴 갭 직후 한 record로는 detect 불가 (recent 만료)")
    }

    // MARK: - Window expiration

    func test_oldRecordsExpired() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 1000, y: 0, at: 0.05))
        XCTAssertFalse(state.record(x: 0, y: 0, at: 1.05),
                       "1초 갭 후엔 이전 샘플 모두 제거되어 detect 불가")
    }

    // MARK: - Zero / tiny dt 안전

    func test_zeroTimeStepIsSafe() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0))            // dt=0 → skip
        XCTAssertFalse(state.record(x: 200, y: 0, at: 0.0005))       // dt<0.001 → skip
    }
}
