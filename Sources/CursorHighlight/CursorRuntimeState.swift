import Foundation
import CoreGraphics
import SwiftUI

// MARK: - CursorRuntimeState
//
// 마우스 위치, 가시성, 모션 시멘틱(클릭 펄스/드래그/글로우), 돋보기 런타임 상태.
// cursorPosition은 60Hz로 갱신되므로 이 객체를 보는 view만 그 빈도로 재평가됨.
// 설정(CursorSettings)이나 효과(EffectsState)와 분리되어 무관한 view 재계산을 피한다.
@MainActor
final class CursorRuntimeState: ObservableObject {
    // MARK: - Cursor Position & Visibility
    @Published var cursorPosition: CGPoint = .zero
    @Published var isCursorVisible: Bool = true

    // MARK: - Spotlight / Magnifier
    @Published var isSpotlightActive: Bool = false
    @Published var isMagnifierActive: Bool = false
    @Published var magnifierImage: CGImage?
    @Published var hasScreenRecordingPermission: Bool = false

    // MARK: - Motion Semantics
    @Published var ringClickScale: CGFloat = 1.0
    @Published var ringClickTilt: Double = 0
    @Published var isDragging: Bool = false
    @Published var dragAngle: Double = 0
    @Published var dragVelocity: CGFloat = 0   // pt/s, EMA smoothed (#14 Speed Glow)
    @Published var glowMultiplier: Double = 1.0

    // MARK: - Drag

    func startDrag() {
        dragAngle = 0
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isDragging = true }
    }

    func updateDragAngle(_ newAngle: Double) {
        // 이전 각도의 wrapped 값과 비교해 차이를 (-π, π] 로 정규화한 뒤 누적
        // → atan2의 ±π 불연속점이 사라져 애니메이션이 항상 짧은 방향으로 이동
        let lastWrapped = atan2(sin(dragAngle), cos(dragAngle))
        var diff = newAngle - lastWrapped
        if diff > .pi  { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        dragAngle += diff
    }

    /// 새 raw velocity(pt/s)를 받아 EMA로 부드럽게 누적. 매 frame jitter 회피.
    func updateDragVelocity(_ rawVelocity: CGFloat) {
        // alpha=0.3 — 새 값 30%, 이전 값 70%. 빠른 변화는 흡수, 일정 속도엔 빠르게 수렴.
        dragVelocity = dragVelocity * 0.7 + rawVelocity * 0.3
    }

    func endDrag() {
        // 다음 드래그를 위해 (-π, π]로 정규화 후 0으로 리셋
        dragAngle = atan2(sin(dragAngle), cos(dragAngle))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { isDragging = false }
        dragAngle = 0
        withAnimation(.easeOut(duration: 0.3)) { dragVelocity = 0 }
    }

    // MARK: - Click Pulse

    func triggerClickPulse(isDouble: Bool = false) {
        let scaleTarget: CGFloat = isDouble ? 0.6 : 0.75
        let tiltTarget: Double = isDouble ? 28 : 18
        withAnimation(.spring(response: 0.1, dampingFraction: 0.4)) {
            ringClickScale = scaleTarget
            ringClickTilt = tiltTarget
        }
        Task {
            try? await Task.sleep(for: .milliseconds(isDouble ? 160 : 130))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) {
                ringClickScale = 1.0
                ringClickTilt = 0
            }
        }
    }
}
