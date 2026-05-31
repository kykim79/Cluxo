import AppKit
import Combine
import CoreImage
import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.ktoy.Cluxo", category: "Magnifier")

// MARK: - MagnifierCaptureService
//
// ScreenCaptureKit(SCStream)으로 주 디스플레이를 20Hz 캡처하고,
// 매 프레임마다 cursor 주변을 CIImage로 crop해 runtime.magnifierImage에 publish.
//
// 이전 CGWindowListCreateImage는 macOS 14+에서 deprecated.
// SCStream은 push 모델 — Timer 없이 stream callback이 sample queue에서 호출됨.
@MainActor
final class MagnifierCaptureService {
    private weak var runtime: CursorRuntimeState?
    private weak var settings: CursorSettings?
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var cancellables = Set<AnyCancellable>()
    private let ciContext = CIContext()

    // 현재 캡처 중인 디스플레이 정보 (cursor가 있는 디스플레이를 동적 선택)
    private var captureScreenFrame: CGRect = .zero  // 글로벌 좌표(Cocoa point)에서의 디스플레이 영역
    private var captureScreenScale: CGFloat = 1     // backing scale
    private var currentDisplayID: CGDirectDisplayID?
    private var isRestarting = false

    init(runtime: CursorRuntimeState, settings: CursorSettings) {
        self.runtime = runtime
        self.settings = settings
        observeToggle()
        observeCursorDisplayChange()
    }

    deinit {
        // SCStream.stopCapture는 async — deinit에서 fire-and-forget
        if let stream {
            Task.detached { try? await stream.stopCapture() }
        }
    }

    /// cursor가 있는 NSScreen을 찾아 반환 (없으면 main 또는 first).
    @MainActor
    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// NSScreen의 displayID (SCDisplay.displayID와 매칭용)
    @MainActor
    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func observeToggle() {
        runtime?.$isMagnifierActive
            .removeDuplicates()
            .sink { [weak self] active in
                if active { Task { await self?.start() } }
                else      { Task { await self?.stop() } }
            }
            .store(in: &cancellables)
    }

    /// cursor가 다른 디스플레이로 옮길 때 SCStream을 그 디스플레이로 재구성한다.
    /// removeDuplicates로 displayID 변경 시에만 sink 발화 → 60Hz cursorPosition 폭주 회피.
    private func observeCursorDisplayChange() {
        runtime?.$cursorPosition
            .compactMap { [weak self] pos -> CGDirectDisplayID? in
                guard let self,
                      self.runtime?.isMagnifierActive == true,
                      let screen = self.screenContaining(pos) else { return nil }
                return self.displayID(of: screen)
            }
            .removeDuplicates()
            .sink { [weak self] newDisplayID in
                guard let self,
                      self.currentDisplayID != nil,                // 첫 start() 전이면 무시
                      newDisplayID != self.currentDisplayID,       // 다른 디스플레이로 옮긴 경우만
                      !self.isRestarting else { return }
                Task { await self.restart() }
            }
            .store(in: &cancellables)
    }

    private func restart() async {
        guard !isRestarting else { return }
        isRestarting = true
        await stop()
        await start()
        isRestarting = false
    }

    private func start() async {
        guard stream == nil else { return }

        // cursor가 있는 디스플레이 동적 선택 (이중 모니터 대응)
        let cursorPos = runtime?.cursorPosition ?? .zero
        guard let cursorScreen = screenContaining(cursorPos),
              let cursorDisplayID = displayID(of: cursorScreen) else {
            runtime?.isMagnifierActive = false
            return
        }
        self.captureScreenFrame = cursorScreen.frame
        self.captureScreenScale = cursorScreen.backingScaleFactor
        self.currentDisplayID = cursorDisplayID

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            // cursor가 있는 디스플레이를 displayID로 매칭
            guard let display = content.displays.first(where: { $0.displayID == cursorDisplayID })
                  ?? content.displays.first else {
                runtime?.isMagnifierActive = false
                return
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )

            let config = SCStreamConfiguration()
            config.width = display.width * Int(self.captureScreenScale)
            config.height = display.height * Int(self.captureScreenScale)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)  // 60fps — 렌즈/이미지 갱신을 부드럽게(떨림 감소)
            config.queueDepth = 5
            // 캡처에서 시스템 커서 제외 — 렌즈는 cursor 위치 중심 crop이라 렌즈 정중앙 = cursor 지점이고,
            // 실제 시스템 커서가 렌즈 위(OS 최상단)에 그대로 떠 그 지점을 가리킨다. showsCursor=true면
            // 렌즈 안에 확대된 커서가 한 번 더 캡처돼 시스템 커서와 이중으로 보인다 → false로 중복 제거.
            config.showsCursor = false

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let output = StreamOutput { [weak self] sampleBuffer in
                self?.processFrame(sampleBuffer)
            }
            try stream.addStreamOutput(
                output,
                type: .screen,
                sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive)
            )
            try await stream.startCapture()

            self.streamOutput = output
            self.stream = stream
        } catch {
            runtime?.isMagnifierActive = false
            log.error("SCStream start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        self.streamOutput = nil
        self.currentDisplayID = nil
        runtime?.magnifierImage = nil
    }

    /// Sample queue(백그라운드)에서 호출됨. CIImage 단계에서 cropping만 하고
    /// CGImage 생성·publish는 MainActor에서.
    nonisolated private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // CIImage는 lazy — cropped(to:)는 메타데이터만 변경, 실제 픽셀 처리는 createCGImage에서.
        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        Task { @MainActor [weak self] in
            guard let self,
                  let runtime = self.runtime,
                  let settings = self.settings,
                  runtime.isMagnifierActive else { return }

            // cursor 글로벌 좌표 → 캡처 중인 디스플레이의 local 좌표 변환 (Cocoa Y-up).
            // CIImage(cvImageBuffer:)도 Quartz Y-up이라 추가 flip 없음.
            let globalPos = runtime.cursorPosition
            let screenFrame = self.captureScreenFrame
            let scale = self.captureScreenScale
            let localX = globalPos.x - screenFrame.origin.x
            let localY = globalPos.y - screenFrame.origin.y

            let zoom = settings.magnifierZoom
            let captureSizePx = (settings.magnifierSize / zoom) * scale
            // 서브픽셀 crop 허용 — 정수 정렬(.integral)하면 cursor가 픽셀 경계를 넘을 때 crop이 1px씩
            // 점프하고 zoom배로 확대돼 떨림으로 보인다. CIImage 보간이 부드럽게 처리한다.
            let cropRect = CGRect(
                x: localX * scale - captureSizePx / 2,
                y: localY * scale - captureSizePx / 2,
                width: captureSizePx,
                height: captureSizePx
            )

            let cropped = ciImage.cropped(to: cropRect)
            let extent = cropped.extent
            guard !extent.isNull, !extent.isEmpty, !extent.isInfinite, extent.width > 0 else { return }

            // 화질 개선 파이프라인:
            //  1) 표시 해상도(magnifierSize × scale)까지 Lanczos로 고품질 업스케일 — SwiftUI 기본
            //     bilinear 업스케일보다 가장자리가 선명. (소스 픽셀 한계는 못 넘지만 blur는 줄어든다.)
            //  2) 가벼운 sharpen으로 확대로 뭉개진 윤곽을 또렷하게.
            let targetPx = settings.magnifierSize * scale
            var output = cropped
            let upscale = targetPx / extent.width
            if upscale > 1.01 {
                output = output.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: upscale,
                    kCIInputAspectRatioKey: 1.0,
                ])
            }
            output = output.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.4,
            ])

            let outExtent = output.extent
            guard !outExtent.isNull, !outExtent.isEmpty, !outExtent.isInfinite else { return }
            guard let cgImage = self.ciContext.createCGImage(output, from: outExtent) else { return }
            // 이미지와 렌즈 위치를 함께 갱신 — 같은 시점의 cursor 좌표라 렌즈 안에서 내용이 밀리지 않는다.
            runtime.magnifierImage = cgImage
            runtime.magnifierImageCenter = globalPos
        }
    }
}

// MARK: - SCStreamOutput delegate
// SCStreamOutput protocol 채택을 위해 NSObject 상속 필요. MainActor 클래스와 분리.

private final class StreamOutput: NSObject, SCStreamOutput {
    private let onFrame: (CMSampleBuffer) -> Void

    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        // Frame status가 .complete가 아니면 skip (idle/dropped frame)
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int,
           status != SCFrameStatus.complete.rawValue {
            return
        }
        onFrame(sampleBuffer)
    }
}
