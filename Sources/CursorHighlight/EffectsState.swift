import Foundation
import CoreGraphics

// MARK: - EffectsState
//
// 일시적 효과 큐 (클릭/더블클릭/흔들기/스크롤/트레일/클립보드).
// 각 효과는 Task로 일정 시간 후 자동 제거된다.
// animationSpeed는 호출 측에서 인자로 전달 — settings와 결합 회피.
@MainActor
final class EffectsState: ObservableObject {
    @Published var clickEffects: [ClickEffect] = []
    @Published var doubleClickEffects: [DoubleClickEffect] = []
    @Published var shakeEffects: [ShakeEffect] = []
    @Published var scrollEffects: [ScrollEffect] = []
    @Published var trailPoints: [TrailPoint] = []
    @Published var clipboardEffects: [ClipboardEffect] = []

    // MARK: - Effect Structs
    struct ClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isRight: Bool; let isDouble: Bool
    }
    struct DoubleClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ShakeEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ScrollEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isPositive: Bool; let isVertical: Bool
    }
    struct TrailPoint: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ClipboardEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let emoji: String
    }

    // MARK: - Add Effects

    func addClickEffect(at point: CGPoint, isRight: Bool, isDouble: Bool = false, animationSpeed: Double) {
        let effect = ClickEffect(position: point, isRight: isRight, isDouble: isDouble)
        clickEffects.append(effect)
        if isDouble {
            let de = DoubleClickEffect(position: point)
            doubleClickEffects.append(de)
            Task {
                try? await Task.sleep(for: .seconds(0.9 * animationSpeed))
                doubleClickEffects.removeAll { $0.id == de.id }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.7 * animationSpeed))
            clickEffects.removeAll { $0.id == effect.id }
        }
    }

    func triggerShake(at point: CGPoint, animationSpeed: Double) {
        let effect = ShakeEffect(position: point)
        shakeEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(max(1.5, 1.8 * animationSpeed)))
            shakeEffects.removeAll { $0.id == effect.id }
        }
    }

    func addScrollEffect(at point: CGPoint, isPositive: Bool, isVertical: Bool, animationSpeed: Double) {
        scrollEffects.removeAll()
        let effect = ScrollEffect(position: point, isPositive: isPositive, isVertical: isVertical)
        scrollEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(0.65 * animationSpeed))
            scrollEffects.removeAll { $0.id == effect.id }
        }
    }

    func addClipboardEffect(at point: CGPoint, emoji: String) {
        let effect = ClipboardEffect(position: point, emoji: emoji)
        clipboardEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            clipboardEffects.removeAll { $0.id == effect.id }
        }
    }

    // MARK: - Trail
    func updateTrail(_ point: CGPoint) {
        trailPoints.append(TrailPoint(position: point))
        if trailPoints.count > 26 { trailPoints.removeFirst() }
    }
    func clearTrail() { trailPoints.removeAll() }
}
