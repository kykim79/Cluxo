import Foundation
import SwiftUI

// MARK: - KeystrokeOverlayState
//
// 화면 하단에 표시되는 키스트로크 오버레이 + 상태 알림(스포트라이트/돋보기/키스트로크 토글).
// timeout은 호출 측에서 인자로 전달 — settings와 결합 회피.
@MainActor
final class KeystrokeOverlayState: ObservableObject {
    @Published var keystrokeText: String = ""
    @Published var isKeystrokeVisible: Bool = false

    private var keystrokeHideTask: Task<Void, Never>?

    /// 키스트로크 표시 — `timeout` 초 후 자동 숨김.
    func showKeystroke(_ text: String, timeout: Double) {
        keystrokeText = text
        isKeystrokeVisible = true
        keystrokeHideTask?.cancel()
        keystrokeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(timeout))
                withAnimation(.easeOut(duration: 0.3)) { self.isKeystrokeVisible = false }
            } catch {}
        }
    }

    /// 상태 알림 (1.5초 고정) — 단축키 토글 등 짧은 안내용.
    func showStatusNotification(_ text: String) {
        keystrokeText = text
        isKeystrokeVisible = true
        keystrokeHideTask?.cancel()
        keystrokeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.3)) { self.isKeystrokeVisible = false }
            } catch {}
        }
    }
}
