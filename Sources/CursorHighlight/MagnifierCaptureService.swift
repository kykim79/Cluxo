import AppKit
import Combine

// MARK: - MagnifierCaptureService
//
// runtime.isMagnifierActive를 구독해 켜지면 20Hz Timer로 커서 주변을 캡처,
// runtime.magnifierImage에 publish. 꺼지면 Timer 중지 → CPU 0.
// 첫 프레임 캡처 실패(프로세스 캐시 문제) 시 재시작 안내 다이얼로그.
@MainActor
final class MagnifierCaptureService {
    private weak var runtime: CursorRuntimeState?
    private weak var settings: CursorSettings?
    private var magnifierTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isCheckingMagnifierCapture = false

    init(runtime: CursorRuntimeState, settings: CursorSettings) {
        self.runtime = runtime
        self.settings = settings
        observeToggle()
    }

    deinit {
        magnifierTimer?.invalidate()
    }

    private func observeToggle() {
        runtime?.$isMagnifierActive
            .removeDuplicates()
            .sink { [weak self] active in
                if active { self?.start() } else { self?.stop() }
            }
            .store(in: &cancellables)
    }

    private func stop() {
        magnifierTimer?.invalidate()
        magnifierTimer = nil
        runtime?.magnifierImage = nil
    }

    // TODO: CGWindowListCreateImage는 macOS 14+에서 deprecated. 향후 ScreenCaptureKit(SCStream) 마이그레이션 필요.
    private func start() {
        magnifierTimer?.invalidate()
        magnifierTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self,
                  let runtime = self.runtime,
                  let settings = self.settings,
                  runtime.isMagnifierActive else { return }
            guard runtime.hasScreenRecordingPermission else {
                DispatchQueue.main.async { runtime.isMagnifierActive = false }
                return
            }
            // 첫 프레임에서 캡처 실패 시(프로세스 캐시 문제) 재시작 안내
            if runtime.magnifierImage == nil && !self.isCheckingMagnifierCapture {
                self.isCheckingMagnifierCapture = true
                self.promptRelaunchIfNeeded()
            }
            let pos = runtime.cursorPosition
            let zoom = settings.magnifierZoom
            let capturePts = settings.magnifierSize / zoom
            let primaryH = NSScreen.screens.first?.frame.height ?? 1080
            let quartzY = primaryH - pos.y
            let rect = CGRect(
                x: pos.x - capturePts / 2,
                y: quartzY - capturePts / 2,
                width: capturePts,
                height: capturePts
            )
            // 메인 스레드 부하를 줄이기 위해 백그라운드에서 캡처
            DispatchQueue.global(qos: .userInteractive).async { [weak runtime] in
                let image = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
                DispatchQueue.main.async { runtime?.magnifierImage = image }
            }
        }
    }

    // 돋보기를 켤 때 캡처가 실제로 동작하는지 확인 후 재시작 안내
    private func promptRelaunchIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            let testRect = CGRect(x: 0, y: 0, width: 10, height: 10)
            let img = CGWindowListCreateImage(testRect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
            let needsRestart = img == nil
            DispatchQueue.main.async {
                self.isCheckingMagnifierCapture = false
                guard needsRestart else { return } // 캡처 정상 — 재시작 불필요
                self.runtime?.isMagnifierActive = false
                let alert = NSAlert()
                alert.messageText = "돋보기를 사용하려면 재시작이 필요합니다"
                alert.informativeText = "화면 녹화 권한이 이 세션에 아직 적용되지 않았습니다."
                alert.addButton(withTitle: "지금 재시작")
                alert.addButton(withTitle: "나중에")
                if alert.runModal() == .alertFirstButtonReturn {
                    let url = URL(fileURLWithPath: "/Applications/CursorHighlight.app")
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
