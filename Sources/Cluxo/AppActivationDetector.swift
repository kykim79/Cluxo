import AppKit

// MARK: - AppActivationDetector
//
// 녹화·발표·회의 앱이 활성화되면 콜백. NSWorkspace.didActivateApplicationNotification
// 구독으로 polling 없이 즉시 반응 (기존 RecordingDetector 5초 polling 대체).
//
// settings.autoEnableOnRecording 토글로 ON/OFF.
@MainActor
final class AppActivationDetector {
    private weak var settings: CursorSettings?
    private let onTriggerAppActivated: () -> Void
    private var observer: NSObjectProtocol?

    init(settings: CursorSettings, onTriggerAppActivated: @escaping () -> Void) {
        self.settings = settings
        self.onTriggerAppActivated = onTriggerAppActivated
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let settings = self.settings,
                  settings.autoEnableOnRecording,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  Self.triggerBundles.contains(bundleId) else { return }
            self.onTriggerAppActivated()
        }
    }

    /// 트리거 앱 — 녹화·발표·회의 (외부 사용자에게 cursor가 잘 보여야 하는 시나리오).
    /// 추가 요청 많으면 settings에 사용자 정의 목록 노출 검토.
    static let triggerBundles: Set<String> = [
        // 화면 녹화
        "com.apple.QuickTimePlayerX",
        "com.obsproject.obs-studio",
        "com.cleanshot.mac",
        "com.loom.desktop",
        // 발표
        "com.apple.iWork.Keynote",
        "com.microsoft.Powerpoint",
        // 화상 회의
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
    ]

    /// 현재 활성 앱이 트리거인지 (초기 활성화 시 1회 체크용).
    static func isTriggerAppFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier else { return false }
        return triggerBundles.contains(bundleId)
    }
}
