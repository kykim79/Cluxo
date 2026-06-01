import XCTest
import CoreGraphics

// RadialHitTest.classify — 라디얼 메뉴 거리/각도 → sector/sub/subSub 분류 검증.
//
// 트리 모양은 클로저로 주입(CursorSettings 의존 없음). 기본 트리:
//   sector 0: sub 3개 [leaf, branch(자식5), branch(자식3)]  ← spotlight 모양
//   그 외 sector: sub 4개 모두 leaf                          ← 단순 sector
//
// 거리 링: dead 50 / main 150 / sub 230 / subSub 290 (기본 토큰값).

final class RadialHitTestTests: XCTestCase {

    private let rings = RadialHitTest.Rings(dead: 50, main: 150, sub: 230, subSub: 290)

    // sector 0만 branch 트리, 나머지는 leaf 4개
    private func subCountOf(_ s: Int) -> Int { s == 0 ? 3 : 4 }
    private func isBranch(_ s: Int, _ sub: Int) -> Bool { s == 0 && (sub == 1 || sub == 2) }
    private func subSubCountOf(_ s: Int, _ sub: Int) -> Int {
        guard s == 0 else { return 0 }
        if sub == 1 { return 5 }   // 반경 5단계
        if sub == 2 { return 3 }   // 경계 3단계
        return 0
    }

    // 테스트용 span — 개수 기반(앱은 라벨 내용 기반 contentSpan을 주입). 항목당 22°, 50~140° clamp.
    private func span(_ n: Int) -> Double { min(140, max(50, Double(n) * 22)) }

    private func classify(dx: CGFloat, dy: CGFloat, lockSector: Int? = nil, lockSub: Int? = nil) -> RadialHitTest.Hit {
        RadialHitTest.classify(
            dx: dx, dy: dy, lockedSector: lockSector, lockedSub: lockSub, rings: rings,
            subCountOf: subCountOf,
            subSpanOf: { self.span(self.subCountOf($0)) },
            isBranch: isBranch,
            subSubCountOf: subSubCountOf,
            subSubSpanOf: { self.span(self.subSubCountOf($0, $1)) })
    }

    // 위쪽(12시) = (0, -r) in Cocoa? — radialMenuCenter 기준 dy는 화면 좌표.
    // clockwiseFromTop은 (90 - atan2(dy,dx)). 12시 방향(위)을 만들려면 atan2가 90°가 되어야 하므로 dy>0.
    // 즉 이 좌표계에서 (0, +r)이 cw=0(12시). 테스트는 이 규약을 따른다.

    // MARK: - 거리 구간

    func test_deadZone_noSelection() {
        let hit = classify(dx: 10, dy: 10)   // dist ~14 < 50
        XCTAssertEqual(hit, .init(sector: nil, sub: nil, subSub: nil))
    }

    func test_beyondOuter_noSelection() {
        let hit = classify(dx: 0, dy: 320)   // dist 320 > 290, lock 없음 → 전체 해제(✕)
        XCTAssertEqual(hit, .init(sector: nil, sub: nil, subSub: nil))
    }

    func test_beyondOuter_branchClears() {
        // branch sub(0,1)를 펼친 채 가장 바깥 너머로 가면 닫기(✕) — leaf와 일관
        let hit = classify(dx: 0, dy: 320, lockSector: 0, lockSub: 1)
        XCTAssertEqual(hit, .init(sector: nil, sub: nil, subSub: nil))
    }

    func test_mainArea_selectsSectorFreely_noSub() {
        // 12시 방향, main 영역(dist 100)
        let hit = classify(dx: 0, dy: 100)
        XCTAssertEqual(hit.sector, 0)
        XCTAssertNil(hit.sub)
        XCTAssertNil(hit.subSub)
    }

    func test_mainArea_eachOfEightSectors() {
        // 8방향 중심각 cw = sector*45. (0,+r)=cw0. 시계방향: 오른쪽(3시)=cw90 → (r,0).
        // cw = 90 - atan2(dy,dx). sector k 중심 cw = 45k. atan2 = 90 - 45k.
        for k in 0..<8 {
            let ang = (90.0 - 45.0 * Double(k)) * .pi / 180
            let dx = CGFloat(cos(ang)) * 100
            let dy = CGFloat(sin(ang)) * 100
            XCTAssertEqual(classify(dx: dx, dy: dy).sector, k, "sector \(k) at cw \(45*k)")
        }
    }

    // MARK: - Sub 영역 (2번째 ring)

    func test_subArea_selectsSub_noSubSub() {
        // sector 0, sub 영역(dist 190), 12시 방향 → sub fan 가운데(3개 중 1번)
        let hit = classify(dx: 0, dy: 190)
        XCTAssertEqual(hit.sector, 0)
        XCTAssertEqual(hit.sub, 1)       // 3개 fan에서 중앙
        XCTAssertNil(hit.subSub)
    }

    func test_subArea_leafSectorNeverHasSubSub() {
        // sector 2(leaf 4개)를 lock, sub 영역
        let hit = classify(dx: 0, dy: 190, lockSector: 2, lockSub: 1)
        XCTAssertEqual(hit.sector, 2)
        XCTAssertNotNil(hit.sub)
        XCTAssertNil(hit.subSub)
    }

    // MARK: - SubSub 영역 (3번째 ring)

    func test_subSubArea_branchSub_opensChildren() {
        // sector 0의 sub 1(branch, 자식5)을 lock하고 3번째 ring(dist 260)
        let hit = classify(dx: 0, dy: 260, lockSector: 0, lockSub: 1)
        XCTAssertEqual(hit.sector, 0)
        XCTAssertEqual(hit.sub, 1)
        XCTAssertNotNil(hit.subSub)           // branch라 자식 선택됨
        XCTAssertEqual(hit.subSub, 2)         // 5개 fan 중앙(12시)
    }

    func test_subSubArea_leafSub_closes() {
        // sector 0의 sub 0(leaf, 확장 없음)을 lock하고 sub 영역 너머 → 닫기(✕). branch가 subSub로 확장하는 것과 대칭.
        let hit = classify(dx: 0, dy: 260, lockSector: 0, lockSub: 0)
        XCTAssertEqual(hit, .init(sector: nil, sub: nil, subSub: nil))
    }

    func test_subSubArea_lockedSubDoesNotDriftToNeighbor() {
        // branch sub 1을 lock한 채 cursor 각도가 옆으로 다소 틀어져도 sub는 1 유지(lock)
        let ang = (90.0 - 20.0) * .pi / 180   // 12시에서 20° 벗어남
        let dx = CGFloat(cos(ang)) * 260
        let dy = CGFloat(sin(ang)) * 260
        let hit = classify(dx: dx, dy: dy, lockSector: 0, lockSub: 1)
        XCTAssertEqual(hit.sub, 1, "branch sub는 subSub 영역에서 lock 유지")
        XCTAssertNotNil(hit.subSub)
    }

    // MARK: - 순수 헬퍼

    func test_contentSpan_widerForLongerLabels() {
        let r: CGFloat = 130
        let short = CursorSettings.RadialMenuItem.contentSpan(labels: ["1×", "2×"], radius: r)
        let long  = CursorSettings.RadialMenuItem.contentSpan(labels: ["매우 크게", "보통"], radius: r)
        XCTAssertGreaterThan(long, short, "긴 라벨이면 같은 개수라도 더 넓은 span")
        XCTAssertGreaterThanOrEqual(short, 50)
        XCTAssertLessThanOrEqual(long, 150)
    }

    func test_clockwiseFromTop_cardinalDirections() {
        XCTAssertEqual(RadialHitTest.clockwiseFromTop(dx: 0, dy: 100), 0, accuracy: 0.01)    // 12시
        XCTAssertEqual(RadialHitTest.clockwiseFromTop(dx: 100, dy: 0), 90, accuracy: 0.01)   // 3시
        XCTAssertEqual(RadialHitTest.clockwiseFromTop(dx: 0, dy: -100), 180, accuracy: 0.01) // 6시
        XCTAssertEqual(RadialHitTest.clockwiseFromTop(dx: -100, dy: 0), 270, accuracy: 0.01) // 9시
    }
}
