import AppKit

// MARK: - RecordingDetector
//
// 5초마다 백그라운드 녹화 앱(QuickTime, Zoom, OBS 등) 실행 여부를 검사하고
// settings.autoEnableOnRecording이 true면 콜백으로 알린다.
@MainActor
final class RecordingDetector {
    private weak var settings: CursorSettings?
    private let onRecordingDetected: () -> Void
    private var timer: Timer?

    init(settings: CursorSettings, onRecordingDetected: @escaping () -> Void) {
        self.settings = settings
        self.onRecordingDetected = onRecordingDetected
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self,
                  self.settings?.autoEnableOnRecording == true,
                  Self.isScreenBeingRecorded() else { return }
            DispatchQueue.main.async { self.onRecordingDetected() }
        }
    }

    static func isScreenBeingRecorded() -> Bool {
        let recordingBundles: Set<String> = [
            "com.apple.QuickTimePlayerX",
            "us.zoom.xos",
            "com.obsproject.obs-studio",
            "com.cleanshot.mac",
            "com.loom.desktop",
            "com.microsoft.teams2",
            "com.cisco.webexmeetingsapp",
            "com.webex.meetingmanager",
        ]
        return NSWorkspace.shared.runningApplications.contains {
            guard let bundleId = $0.bundleIdentifier else { return false }
            return recordingBundles.contains(bundleId)
        }
    }
}
