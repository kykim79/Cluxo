import CoreGraphics
import Foundation

// MARK: - RadialHitTest
//
// 라디얼 메뉴에서 cursor의 (중심 기준) 상대 위치 → 어떤 sector/sub/subSub가 선택됐는지 분류.
// 순수 함수로 분리해 unit test 가능(`RadialHitTestTests`). CursorSettings·@MainActor 의존을
// 클로저로 주입받아 끊는다 — 트리 모양(subCount/branch/subSubCount)만 알면 된다.
//
// 거리 구간 (안→밖):
//   dead   : cancel (선택 없음)
//   main   : sector 자유 회전 (옆으로 가면 그쪽 sector)
//   sub    : sector LOCK + sub fan 선택 (2번째 ring)
//   subSub : branch sub LOCK + 자식 fan 선택 (3번째 ring). leaf면 sub 유지(subSub=nil).
//   바깥   : 선택 없음
//
// fan 분할은 기존 RadialMenuItem.subSpan 공식과 동일(4개 이하 45°, 5개부터 항목당 +12°, 최대 120°).
enum RadialHitTest {

    struct Hit: Equatable {
        let sector: Int?
        let sub: Int?
        let subSub: Int?
    }

    struct Rings {
        let dead: CGFloat
        let main: CGFloat
        let sub: CGFloat
        let subSub: CGFloat
    }

    /// 12시=0, 시계방향으로 증가하는 각도(0~360).
    static func clockwiseFromTop(dx: CGFloat, dy: CGFloat) -> Double {
        let atan2Deg = atan2(Double(dy), Double(dx)) * 180 / .pi
        return (90 - atan2Deg + 720).truncatingRemainder(dividingBy: 360)
    }

    /// 중심각(centerDeg)을 기준으로 span을 count칸 분할했을 때 cw가 속한 인덱스(0..<count).
    static func fanIndex(cw: Double, centerDeg: Double, span: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = span / Double(count)
        var diff = cw - centerDeg
        if diff > 180  { diff -= 360 }
        if diff < -180 { diff += 360 }
        let rel = diff + span / 2          // 0~span 정규화
        let clamped = max(0, min(span - 0.001, rel))
        return Int(clamped / step)
    }

    /// sub fan 내에서 sub 인덱스의 중심 각도 — subSub fan은 이 각도를 중심으로 펼쳐진다.
    static func subCenterAngle(sector: Int, sub: Int, subSpan: Double, subCount: Int) -> Double {
        let mainAngle = Double(sector) * 45
        let step = subSpan / Double(max(1, subCount))
        let start = mainAngle - subSpan / 2
        return start + step * (Double(sub) + 0.5)
    }

    /// cursor 상대좌표(dx,dy)와 현재 lock 상태로부터 선택 결과를 계산.
    /// - lockedSector/lockedSub: sub·subSub 영역에서 sector/sub를 고정하기 위한 현재 선택값.
    /// - subCountOf: sector → 최상위 sub 개수. isBranch: (sector,sub) → branch 여부. subSubCountOf: (sector,sub) → 자식 수.
    static func classify(
        dx: CGFloat, dy: CGFloat,
        lockedSector: Int?,
        lockedSub: Int?,
        rings: Rings,
        subCountOf: (Int) -> Int,
        subSpanOf: (Int) -> Double,            // sector → sub fan 각도 (라벨 내용 기반)
        isBranch: (Int, Int) -> Bool,
        subSubCountOf: (Int, Int) -> Int,
        subSubSpanOf: (Int, Int) -> Double      // (sector,sub) → 자식 fan 각도
    ) -> Hit {
        let dist = (dx * dx + dy * dy).squareRoot()

        if dist < rings.dead { return Hit(sector: nil, sub: nil, subSub: nil) }      // cancel
        if dist > rings.subSub { return Hit(sector: nil, sub: nil, subSub: nil) }    // 바깥 무효

        let cw = clockwiseFromTop(dx: dx, dy: dy)

        // 메인 영역 — sector 자유
        if dist < rings.main {
            return Hit(sector: Int((cw + 22.5) / 45) % 8, sub: nil, subSub: nil)
        }

        // [main, subSub] → sector LOCK (이미 선택돼 있으면 유지, 첫 진입이면 angle)
        let sector = lockedSector ?? (Int((cw + 22.5) / 45) % 8)
        let subCount = subCountOf(sector)
        guard subCount > 0 else { return Hit(sector: sector, sub: nil, subSub: nil) }

        let subSpan = subSpanOf(sector)
        let sub = fanIndex(cw: cw, centerDeg: Double(sector) * 45, span: subSpan, count: subCount)

        // 2번째 ring — sub 값
        if dist < rings.sub {
            return Hit(sector: sector, sub: sub, subSub: nil)
        }

        // 3번째 ring — branch sub LOCK (옆 branch로 새지 않게)
        let lockSub = lockedSub ?? sub
        guard isBranch(sector, lockSub) else {
            // leaf — subSub 없이 sub 유지 (3번째 ring에서도 클릭하면 leaf 실행)
            return Hit(sector: sector, sub: lockSub, subSub: nil)
        }
        let kidCount = subSubCountOf(sector, lockSub)
        guard kidCount > 0 else { return Hit(sector: sector, sub: lockSub, subSub: nil) }

        let center = subCenterAngle(sector: sector, sub: lockSub, subSpan: subSpan, subCount: subCount)
        let subSub = fanIndex(cw: cw, centerDeg: center, span: subSubSpanOf(sector, lockSub), count: kidCount)
        return Hit(sector: sector, sub: lockSub, subSub: subSub)
    }
}
