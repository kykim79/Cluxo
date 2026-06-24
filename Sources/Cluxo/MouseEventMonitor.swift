import CoreGraphics
import Foundation
import AppKit

class MouseEventMonitor {
    var onMouseMove: ((CGPoint) -> Void)?
    var onLeftClick: ((CGPoint, Bool) -> Void)?   // (position, isDouble)
    /// Background thread에서 호출 — radial menu 활성 중에만 true 리턴해 좌클릭을 소비.
    /// main에서 갱신 (한 워드 Bool read), 단일 Bool라 race tolerated.
    nonisolated(unsafe) var shouldConsumeLeftClick: Bool = false
    /// ⌃⌥D 그리기 모드 — leftMouseDown/Dragged/Up 전부 소비 + 그리기 콜백으로 라우팅.
    nonisolated(unsafe) var isDrawingModeActive: Bool = false
    var onDrawingDrag: ((CGPoint) -> Void)?      // leftMouseDragged in drawing mode (Quartz 좌표)
    var onDrawingRelease: ((CGPoint) -> Void)?   // leftMouseUp in drawing mode
    var onRightClick: ((CGPoint) -> Void)?
    var onMiddleClick: ((CGPoint) -> Void)?       // 휠 클릭 (button 2)
    var onShake: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, Bool, Bool, CGFloat) -> Void)? // (position, isPositive, isVertical, magnitude)
    var onDragStart: ((CGPoint) -> Void)?  // 시작 위치 (Quartz 좌표, AppDelegate가 Cocoa로 변환)
    var onDragAngle: ((Double, CGFloat) -> Void)?  // (angle in radians, velocity in pt/s)
    var onDragEnd: (() -> Void)?

    /// 좌클릭 hold (Tokens.Radial.longPressDuration) 시 fire — 라디얼 메뉴 트리거.
    /// 마우스 hold / 트랙패드 long touch 모두 같은 left mouse 이벤트라 단일 메커니즘으로 처리.
    var onLongPress: ((CGPoint) -> Void)?

    /// 라디얼 메뉴 활성 중 잡아 끌어 메뉴 중심을 이동 — delta(Quartz 좌표 이동량)를 전달.
    var onRadialMenuDrag: ((CGPoint) -> Void)?
    // 라디얼 메뉴 grab 추적 — 활성 중 leftMouseDown으로 grab, deadband 초과 이동이면 drag(이동),
    // 그 이하로 release면 click(실행/닫기)으로 판정.
    private var radialGrabbing = false
    private var radialPressStart: CGPoint = .zero
    private var radialLastDrag: CGPoint = .zero
    private var radialDidDrag = false

    // long press 추적 — mouseDown 시 timer 시작, deadband 초과 이동 또는 mouseUp 시 cancel.
    private var longPressWorkItem: DispatchWorkItem?
    private var longPressStartPos: CGPoint = .zero
    /// 상위 코드에서 라디얼 메뉴 / 그리기 모드 활성 여부 (background에서 읽음, main에서 갱신).
    /// 활성 시 long press timer 시작 안 함 (중복 트리거/모드 충돌 방지).
    private var canStartLongPress: Bool { !shouldConsumeLeftClick && !isDrawingModeActive }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfPtr: UnsafeMutableRawPointer?
    private var tapThread: Thread?

    // 흔들기 감지 — 알고리즘은 ShakeState.swift에 추출(테스트 가능).
    private var shakeState = ShakeState()

    /// 흔들기 감지 민감도(방향 전환 횟수) — AppDelegate가 설정값으로 주입. 적을수록 민감.
    var shakeRequiredDirChanges: Int = 5 {
        didSet { shakeState.requiredDirChanges = shakeRequiredDirChanges }
    }

    // 스크롤 디바운스
    private var lastScrollTime: TimeInterval = 0
    private var lastScrollKey: String = ""

    // 드래그 상태
    private var inDrag: Bool = false
    private var lastDragPos: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0


    func start() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        // 관심 이벤트 — 한 줄 OR 체인은 untyped `1` 리터럴 추론이 -O(릴리스 WMO)에서 타입체크
        // 타임아웃을 일으켜, 배열 + reduce로 표현식을 쪼갠다.
        let monitoredTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .otherMouseDown,       // 휠 클릭(button 2) 및 나머지
            .leftMouseDragged,
            .rightMouseDragged,    // 오른쪽 버튼 드래그 — 링이 따라가도록 위치 추적
            .otherMouseDragged,    // 가운데(휠) 버튼 드래그 — 링이 따라가도록 위치 추적
            .scrollWheel,
        ]
        let mask: CGEventMask = monitoredTypes.reduce(0) { $0 | (1 << $1.rawValue) }

        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // 평소 consume 안 함. radial menu 활성 중 leftMouseDown만 소비.
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let m = Unmanaged<MouseEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

                let loc = event.location
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    // 시스템이 메인 스레드 과부하로 tap을 비활성화하면 즉시 재활성화
                    if let tap = m.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)

                case .mouseMoved:
                    m.processMove(loc)
                    DispatchQueue.main.async { m.onMouseMove?(loc) }

                case .leftMouseDragged:
                    // 라디얼 메뉴를 잡아 끄는 중 — 메뉴 중심 이동. grab은 leftMouseDown(⌃⌥,로 연 경우)에서만 시작.
                    // 좌클릭 long-press로 연 경우는 down 시점에 radial이 꺼져 있어 grab되지 않음 → hold-drag는 sector 선택 유지.
                    if m.radialGrabbing {
                        let pdx = loc.x - m.radialPressStart.x
                        let pdy = loc.y - m.radialPressStart.y
                        let db = Tokens.Radial.longPressDeadband
                        if !m.radialDidDrag && (pdx * pdx + pdy * pdy) > (db * db) {
                            m.radialDidDrag = true
                        }
                        if m.radialDidDrag {
                            let ddx = loc.x - m.radialLastDrag.x
                            let ddy = loc.y - m.radialLastDrag.y
                            DispatchQueue.main.async {
                                m.onRadialMenuDrag?(CGPoint(x: ddx, y: ddy))   // 중심 이동
                                m.onMouseMove?(loc)                            // cursor 위치 갱신(선택은 center 따라 유지)
                            }
                        }
                        m.radialLastDrag = loc
                        return nil
                    }
                    m.processMove(loc)
                    DispatchQueue.main.async { m.onMouseMove?(loc) }
                    // Long-press deadband 초과 이동 → 드래그로 간주, timer cancel (라디얼 트리거 안 함)
                    if let work = m.longPressWorkItem {
                        let dx = loc.x - m.longPressStartPos.x
                        let dy = loc.y - m.longPressStartPos.y
                        if (dx * dx + dy * dy) > (Tokens.Radial.longPressDeadband * Tokens.Radial.longPressDeadband) {
                            work.cancel()
                            m.longPressWorkItem = nil
                        }
                    }
                    // 그리기 모드 — 드래그 위치를 그리기 콜백으로 라우팅 + underlying 차단
                    if m.isDrawingModeActive {
                        DispatchQueue.main.async { m.onDrawingDrag?(loc) }
                        return nil
                    }
                    let now = Date().timeIntervalSinceReferenceDate
                    if !m.inDrag {
                        m.inDrag = true
                        m.lastDragPos = loc
                        m.lastDragTime = now
                        DispatchQueue.main.async { m.onDragStart?(loc) }
                    } else {
                        let dx = loc.x - m.lastDragPos.x
                        let dy = loc.y - m.lastDragPos.y
                        if abs(dx) > 2 || abs(dy) > 2 {
                            let dt = now - m.lastDragTime
                            let dist = sqrt(dx * dx + dy * dy)
                            let velocity: CGFloat = dt > 0.001 ? dist / CGFloat(dt) : 0
                            let angle = atan2(dy, dx)
                            m.lastDragPos = loc
                            m.lastDragTime = now
                            DispatchQueue.main.async { m.onDragAngle?(angle, velocity) }
                        }
                    }

                case .leftMouseDown:
                    m.inDrag = false
                    let clickState = event.getIntegerValueField(.mouseEventClickState)
                    let isDouble = clickState >= 2
                    // 라디얼 메뉴 활성: 잡아 옮길 수 있게 click 판정을 up으로 미룸(down은 grab 시작만).
                    if m.shouldConsumeLeftClick {
                        m.radialGrabbing = true
                        m.radialPressStart = loc
                        m.radialLastDrag = loc
                        m.radialDidDrag = false
                        return nil
                    }
                    DispatchQueue.main.async { m.onLeftClick?(loc, isDouble) }
                    // Long-press 트리거 — 라디얼 메뉴 미활성 + 그리기 미활성일 때만 timer 시작
                    if m.canStartLongPress {
                        m.longPressStartPos = loc
                        let work = DispatchWorkItem { [weak m] in
                            guard let m else { return }
                            m.longPressWorkItem = nil
                            // canStartLongPress는 main에서 갱신되므로 fire 시점에 다시 확인 (race 안전망)
                            if m.canStartLongPress {
                                m.onLongPress?(m.longPressStartPos)
                            }
                        }
                        m.longPressWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Radial.longPressDuration, execute: work)
                    }
                    // Radial menu 또는 그리기 모드 활성 중에는 underlying app으로 click 전달 안 함
                    if m.shouldConsumeLeftClick || m.isDrawingModeActive {
                        return nil
                    }

                case .leftMouseUp:
                    // 라디얼 메뉴 grab 종료 — drag였으면 이동만(클릭 무시), 제자리였으면 click(실행/닫기).
                    if m.radialGrabbing {
                        m.radialGrabbing = false
                        if !m.radialDidDrag {
                            DispatchQueue.main.async { m.onLeftClick?(m.radialPressStart, false) }
                        }
                        return nil
                    }
                    // Long-press timer 살아있으면 cancel — 사용자가 threshold 전에 손 뗌 = 짧은 클릭
                    if let work = m.longPressWorkItem {
                        work.cancel()
                        m.longPressWorkItem = nil
                    }
                    if m.isDrawingModeActive {
                        DispatchQueue.main.async { m.onDrawingRelease?(loc) }
                        m.inDrag = false
                        return nil
                    }
                    if m.inDrag {
                        m.inDrag = false
                        DispatchQueue.main.async { m.onDragEnd?() }
                    }

                case .rightMouseDown:
                    DispatchQueue.main.async { m.onRightClick?(loc) }

                case .otherMouseDown:
                    // mouseEventButtonNumber: 0=left, 1=right, 2=middle, 3+=extra
                    let button = event.getIntegerValueField(.mouseEventButtonNumber)
                    if button == 2 {
                        DispatchQueue.main.async { m.onMiddleClick?(loc) }
                    }

                case .rightMouseDragged, .otherMouseDragged:
                    // 가운데(휠)·오른쪽 버튼 드래그 — 링이 커서를 따라가도록 위치만 갱신.
                    // 왼쪽 드래그 전용 시각 효과(jelly stretch·anchored line)는 적용하지 않는다.
                    m.processMove(loc)
                    DispatchQueue.main.async { m.onMouseMove?(loc) }

                case .scrollWheel:
                    let deltaV = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                    let deltaH = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                    let now = Date().timeIntervalSinceReferenceDate
                    let isVertical = abs(deltaV) >= abs(deltaH)
                    let delta = isVertical ? deltaV : deltaH
                    guard delta != 0 else { break }
                    // vertical: negative=up / horizontal: positive=right
                    let isPositive = isVertical ? (delta < 0) : (delta > 0)
                    // magnitude (absolute pt delta) — 트랙패드 1지손 ~5, 휠 한 칸 ~10, 강한 swipe ~50+
                    let magnitude = CGFloat(abs(delta))
                    let key = isVertical ? (isPositive ? "up" : "down") : (isPositive ? "right" : "left")
                    if key != m.lastScrollKey || now - m.lastScrollTime > 0.25 {
                        m.lastScrollTime = now
                        m.lastScrollKey = key
                        DispatchQueue.main.async { m.onScroll?(loc, isPositive, isVertical, magnitude) }
                    }

                default:
                    break
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            retained.release()
            selfPtr = nil
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // 메인 스레드 RunLoop과 완전히 격리된 전용 스레드에서 실행
        // NSMenu 트래킹, NSApp.activate 등 메인 스레드 상태 변화의 영향을 받지 않음
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Cluxo.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // 포트 무효화 → 백그라운드 스레드의 CFRunLoopRun()이 자동 종료됨
            CFMachPortInvalidate(tap)
        }
        if let ptr = selfPtr {
            Unmanaged<MouseEventMonitor>.fromOpaque(ptr).release()
            selfPtr = nil
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        inDrag = false
    }

    private func processMove(_ point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        if shakeState.record(x: point.x, y: point.y, at: now) {
            let capturedPoint = point
            DispatchQueue.main.async { [weak self] in self?.onShake?(capturedPoint) }
        }
    }

    deinit { stop() }
}
