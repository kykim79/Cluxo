import Foundation
import CoreGraphics
import SwiftUI
import ServiceManagement

// MARK: - CursorSettings
//
// UserDefaults에 영구 저장되는 모든 사용자 설정.
// @Persisted PropertyWrapper로 init/didSet boilerplate 없음.
// customRingColor만 Color→RGBA 변환이 필요해 별도 처리.
@MainActor
final class CursorSettings: ObservableObject {
    // MARK: - Persisted Settings
    // v1.0.0: 첫 실행 default는 minimalist preset — 효과 절제, ring 자체로 강조.
    // 발견 가능한 옵션은 환경설정에서 ON. (글로우·정지펄스·앵커라인 등 default OFF로 변경)
    @Persisted("ringColor", default: RingColor.cyan) var ringColor: RingColor
    @Persisted("ringShape", default: RingShape.circle) var ringShape: RingShape
    @Persisted("ringSize", default: RingSize.medium) var ringSize: RingSize
    @Persisted("ringOpacity", default: 1.0, debounce: 0.3) var ringOpacity: Double
    @Persisted("animationSpeed", default: AnimationSpeed.normal) var animationSpeed: AnimationSpeed
    @Persisted("keystrokeTimeout", default: 3.0, debounce: 0.3) var keystrokeTimeout: Double
    @Persisted("spotlightKeyCode", default: UInt16(1)) var spotlightKeyCode: UInt16
    @Persisted("keystrokeKeyCode", default: UInt16(40)) var keystrokeShortcutKeyCode: UInt16
    @Persisted("spotlightRadius", default: CGFloat(130), debounce: 0.3) var spotlightRadius: CGFloat
    @Persisted("spotlightEdgeSoftness", default: CGFloat(0.4), debounce: 0.3) var spotlightEdgeSoftness: CGFloat  // 0=선명한 경계, 1=매우 부드러운 feather
    @Persisted("idleTimeout", default: 3.0, debounce: 0.3) var idleTimeout: TimeInterval
    @Persisted("scrollIndicator", default: true) var isScrollIndicatorEnabled: Bool
    @Persisted("rightClickUsesRingColor", default: false) var rightClickUsesRingColor: Bool
    @Persisted("autoEnableOnRecording", default: false) var autoEnableOnRecording: Bool
    @Persisted("magnifierZoom", default: 2.0, debounce: 0.3) var magnifierZoom: Double
    @Persisted("magnifierSize", default: CGFloat(200), debounce: 0.3) var magnifierSize: CGFloat
    @Persisted("magnifierKeyCode", default: UInt16(46)) var magnifierShortcutKeyCode: UInt16  // M key
    // v0.7.0 추가 — 충돌 회피용 재정의
    @Persisted("radialMenuKeyCode", default: UInt16(43)) var radialMenuKeyCode: UInt16   // , key (콤마)
    @Persisted("drawingKeyCode", default: UInt16(2)) var drawingKeyCode: UInt16          // D key
    @Persisted("inspectorKeyCode", default: UInt16(34)) var inspectorKeyCode: UInt16     // I key
    // 그리기 toolbar 위치 (좌측 padding / 하단 padding, pt). 사용자가 drag로 이동 가능.
    @Persisted("drawingToolbarLeading", default: CGFloat(28)) var drawingToolbarLeading: CGFloat
    @Persisted("drawingToolbarBottom", default: CGFloat(110)) var drawingToolbarBottom: CGFloat
    @Persisted("borderWeight", default: BorderWeight.thin) var borderWeight: BorderWeight
    @Persisted("borderStyle", default: BorderStyle.solid) var borderStyle: BorderStyle
    @Persisted("perspectiveWarping", default: false) var isPerspectiveWarping: Bool
    @Persisted("hasInnerRing", default: false) var hasInnerRing: Bool
    @Persisted("isRingFillEnabled", default: true) var isRingFillEnabled: Bool
    @Persisted("isGlowEnabled", default: false) var isGlowEnabled: Bool
    @Persisted("isKeystrokeEnabled", default: false) var isKeystrokeEnabled: Bool
    @Persisted("isTrailEnabled", default: false) var isTrailEnabled: Bool
    @Persisted("isAnchoredLineEnabled", default: false) var isAnchoredLineEnabled: Bool  // #17 — 자동 임계 기반, 평소 비-intrusive
    @Persisted("isCometTailEnabled", default: false) var isCometTailEnabled: Bool  // #18 — 드래그 streak, 임팩트 커서 default off
    @Persisted("isDragAngleLabelEnabled", default: false) var isDragAngleLabelEnabled: Bool  // 드래그 중 각도 표시 (도면용 — default off)
    @Persisted("isIdlePulseEnabled", default: true) var isIdlePulseEnabled: Bool  // 1.5초 정지 시 1회 펄스 — "여기 보세요" 자연스러운 강조
    @Persisted("isTrackpadGesturesEnabled", default: false) var isTrackpadGesturesEnabled: Bool  // 4핀치/3·4 swipe 효과 — 비공식 API(MultitouchSupport), default off
    @Persisted("isShakeEnabled", default: true) var isShakeEnabled: Bool  // 마우스 흔들어서 강조 (퍼지는 링) — "커서 어디 갔지?" 찾기용, default on
    @Persisted("shakeSensitivity", default: ShakeSensitivity.normal) var shakeSensitivity: ShakeSensitivity  // 흔들기 감지 민감도 (방향 전환 횟수)
    @Persisted("radialOpenTrigger", default: RadialOpenTrigger.middleClick) var radialOpenTrigger: RadialOpenTrigger  // 라디얼 메뉴를 여는 마우스 동작 (⌃⌥,는 항상 동작)
    @Persisted("radialThreeFingerTap", default: true) var radialThreeFingerTap: Bool  // 트랙패드 세 손가락 탭으로 라디얼 메뉴 열기 (가운데 버튼 없는 트랙패드용)

    // 앱 UI 언어 강제 — .system이면 macOS 시스템 언어 따름.
    // 실제 적용은 main.swift에서 NSApplication 생성 전 AppleLanguages override.
    @Persisted("preferredLanguage", default: PreferredLanguage.system) var preferredLanguage: PreferredLanguage

    // 낯선 외장 모니터(신뢰 목록에 없는) 연결 시 키스트로크 표시 자동 ON — 발표·회의 상황 감지.
    // 자주 쓰는 데스크탑 모니터는 trustedMonitorUUIDs에 등록해 제외.
    @Persisted("autoKeystrokeOnUnknownMonitor", default: false) var autoKeystrokeOnUnknownMonitor: Bool

    // 발표/녹화용 일시 토글 — overlay window의 sharingType을 .readOnly로 풀어 외부 screencapture/OBS가 잡을 수 있게.
    // 평소 .none이라야 Cluxo 자체 돋보기가 자기 overlay를 다시 capture하지 않음. 앱 재시작 시 항상 false.
    @Published var isScreenshotMode: Bool = false

    // 신뢰 모니터 UUID 목록 — 자동 키스트로크 활성화에서 제외할 모니터. [String]이라 @Persisted 미지원, 별도 처리.
    @Published var trustedMonitorUUIDs: [String] = [] {
        didSet { UserDefaults.standard.set(trustedMonitorUUIDs, forKey: "trustedMonitorUUIDs") }
    }

    func isTrustedMonitor(_ uuid: String) -> Bool { trustedMonitorUUIDs.contains(uuid) }

    func setTrusted(_ uuid: String, trusted: Bool) {
        if trusted {
            if !trustedMonitorUUIDs.contains(uuid) { trustedMonitorUUIDs.append(uuid) }
        } else {
            trustedMonitorUUIDs.removeAll { $0 == uuid }
        }
    }

    // customRingColor는 Color → NSColor → [Double] RGBA 변환 필요해서 @Persisted 미지원, 별도 처리
    @Published var customRingColor: Color = Color(red: 1, green: 0.5, blue: 0) {
        didSet { scheduleCustomColorSave() }
    }

    /// 사용자가 설정한 active accent color — ringColor가 .custom이면 customRingColor, 아니면 미리 정의된 색.
    /// 클릭/드래그/radial accent/그리기 stroke 등 모든 Active 효과가 이 값을 따른다 (DESIGN.md Color Rule).
    var effectiveRingColor: Color {
        ringColor == .custom ? customRingColor : ringColor.color
    }

    // ColorPicker 드래그 중 매 변화마다 NSColor 변환+UserDefaults set 회피 (@Persisted와 동일한 0.3초 debounce)
    private var saveCustomColorTask: DispatchWorkItem?

    init() {
        if let rgba = UserDefaults.standard.array(forKey: "customRingColor") as? [Double], rgba.count >= 3 {
            customRingColor = Color(red: rgba[0], green: rgba[1], blue: rgba[2],
                                    opacity: rgba.count > 3 ? rgba[3] : 1.0)
        }
        if let uuids = UserDefaults.standard.array(forKey: "trustedMonitorUUIDs") as? [String] {
            trustedMonitorUUIDs = uuids
        }
    }

    private func scheduleCustomColorSave() {
        saveCustomColorTask?.cancel()
        let color = customRingColor
        let task = DispatchWorkItem {
            let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .orange
            UserDefaults.standard.set([
                Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent)
            ], forKey: "customRingColor")
        }
        saveCustomColorTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    // MARK: - Launch at Login
    var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch { print("LaunchAtLogin: \(error)") }
    }

    // MARK: - Enums
    /// 단축키 순서로 정렬 (⌃⌥1~7) — toolbar dot 자동 정렬, ⌃⌥C 순환도 같은 순.
    /// custom은 환경설정에서 별도 선택, allCases.filter { $0 != .custom }로 제외.
    enum RingColor: String, CaseIterable, Identifiable {
        case yellow, red, blue, green, cyan, purple, white, custom
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .yellow: return .yellow
            case .red:    return Color(red: 1, green: 0.3, blue: 0.3)
            case .blue:   return Color(red: 0.3, green: 0.6, blue: 1)
            case .green:  return Color(red: 0.3, green: 1, blue: 0.5)
            case .white:  return .white
            case .cyan:   return Color(red: 0, green: 0.9, blue: 1)
            case .purple: return Color(red: 0.8, green: 0.3, blue: 1)
            case .custom: return .orange  // placeholder; actual via customRingColor
            }
        }
        var label: String {
            switch self {
            case .yellow: return "노란색".loc
            case .red:    return "빨간색".loc
            case .blue:   return "파란색".loc
            case .green:  return "초록색".loc
            case .white:  return "흰색".loc
            case .cyan:   return "하늘색".loc
            case .purple: return "보라색".loc
            case .custom: return "커스텀".loc
            }
        }

        /// 색 위에 어두운 텍스트가 가독성 좋은가 — Color.needsDarkText에 위임 (휘도 기준, custom 색도 자동).
        var needsDarkText: Bool { color.needsDarkText }
    }

    /// Radial Menu (⌃⌥,) 8개 메인 sector — rawValue = sector index (12시=0, 시계방향 45°).
    /// 서브 라벨은 marking menu fan에 표시되고, 없으면 메인 액션(토글/cycle)만 실행.
    enum RadialMenuItem: Int, CaseIterable {
        case spotlight = 0   // 12시
        case magnifier       // 1:30
        case glow            // 3시
        case ringSize        // 4:30
        case color           // 6시
        case ringShape       // 7:30
        case inspector       // 9시
        case keystroke       // 10:30

        var subCount: Int { subItems.count }

        /// 메인 sector SF Symbol — RadialMenuView 메인 wedge 및 중심 컨텍스트에 표시.
        var icon: String {
            switch self {
            case .spotlight: return "flashlight.on.fill"
            case .magnifier: return "plus.magnifyingglass"
            case .glow:      return "sparkles"
            case .ringSize:  return "circle.dashed"
            case .color:     return "paintpalette.fill"
            case .ringShape: return "square.on.circle"
            case .inspector: return "ruler.fill"
            case .keystroke: return "keyboard.fill"
            }
        }

        /// 메인 sector 한글 라벨.
        var label: String {
            switch self {
            case .spotlight: return "스포트라이트".loc
            case .magnifier: return "돋보기".loc
            case .glow:      return "효과".loc
            case .ringSize:  return "링 외형".loc
            case .color:     return "링 색".loc
            case .ringShape: return "링 모양".loc
            case .inspector: return "좌표/각도".loc
            case .keystroke: return "키 입력".loc
            }
        }

        /// 항목 위에 커서가 잠시 머무르면(dwell) 표시되는 설명 한 줄 — 메뉴 하단 캡슐.
        /// sub/leaf 자체 desc가 없으면 이 sector desc로 폴백된다(RadialMenuView.hoverDescription).
        var desc: String {
            switch self {
            case .spotlight: return "커서 주변만 밝히고 나머지 화면을 어둡게 덮어 시선을 모읍니다.".loc
            case .magnifier: return "커서 주변을 실시간 확대해 작은 글씨·UI를 키워 봅니다.".loc
            case .glow:      return "글로우·트레일·정지 펄스·코멧 등 커서 강조 효과를 켜고 끕니다.".loc
            case .ringSize:  return "커서를 감싸는 링의 크기·투명도·두께·선 스타일을 조절합니다.".loc
            case .color:     return "커서 강조 링의 색을 바꿉니다.".loc
            case .ringShape: return "링의 형태(원·둥근 사각형·마름모·육각형)를 바꿉니다.".loc
            case .inspector: return "커서 좌표와 드래그 각도를 화면에 표시합니다.".loc
            case .keystroke: return "누른 단축키를 화면에 자막처럼 표시합니다.".loc
            }
        }

        /// 현재 설정/상태값을 짧게 표현 (radial menu 중심에 "라벨 / 값"으로 표시).
        @MainActor
        func currentValue(settings: CursorSettings, runtime: CursorRuntimeState) -> String {
            switch self {
            case .spotlight: return runtime.isSpotlightActive ? "\("켜짐".loc) · \(Int(settings.spotlightRadius))pt" : "꺼짐".loc
            case .magnifier: return runtime.isMagnifierActive ? "\("켜짐".loc) · \(String(format: "%.1f", settings.magnifierZoom))×" : "꺼짐".loc
            case .glow:
                // ✨ 효과는 독립 토글 묶음이라 단일 ON/OFF 부정확 — 켜진 개수 노출
                let on = [settings.isGlowEnabled, settings.isTrailEnabled,
                          settings.isIdlePulseEnabled, settings.isCometTailEnabled].filter { $0 }.count
                return "\(on)/4 \("켜짐".loc)"
            case .ringSize:  return settings.ringSize.label
            case .color:     return settings.ringColor.label
            case .ringShape: return settings.ringShape.label
            case .inspector:
                // 📐 좌표/각도는 2개 독립 토글 묶음
                let on = [runtime.isInspectorActive, settings.isDragAngleLabelEnabled].filter { $0 }.count
                return "\(on)/2 \("켜짐".loc)"
            case .keystroke: return settings.isKeystrokeEnabled ? "\("켜짐".loc) · \(Int(settings.keystrokeTimeout))\("초".loc)" : "꺼짐".loc
            }
        }

        /// 서브 항목 i가 현재 설정/상태와 일치하는가 — radial menu에서 "지금 어떤 게 활성인지" 시각 강조용.
        /// 토글류(spotlight/magnifier/keystroke의 sub 0, glow의 모든 sub)는 isEnabled 직접 반영,
        /// 값 선택류는 현재 값과 sub i의 값이 일치할 때 true.
        @MainActor
        func isSubCurrent(at i: Int, settings: CursorSettings, runtime: CursorRuntimeState) -> Bool {
            switch self {
            case .spotlight:
                return i == 0 ? runtime.isSpotlightActive : false   // sub 1·2는 branch(자식 강조는 isSubSubCurrent)
            case .magnifier:
                return i == 0 ? runtime.isMagnifierActive : false
            case .glow:
                switch i {
                case 0: return settings.isGlowEnabled
                case 1: return settings.isTrailEnabled
                case 2: return settings.isIdlePulseEnabled
                case 3: return settings.isCometTailEnabled
                default: return false
                }
            case .ringSize:
                return false   // 전부 branch(크기/투명도/두께/스타일) — 자식 강조는 isSubSubCurrent
            case .color:
                let cases = RingColor.allCases.filter { $0 != .custom }
                return i < cases.count && cases[i] == settings.ringColor
            case .ringShape:
                let cases = RingShape.allCases
                return i < cases.count && cases[i] == settings.ringShape
            case .keystroke:
                if i == 0 { return settings.isKeystrokeEnabled }
                let times: [Double] = [1, 2, 4, 8]
                guard i - 1 < times.count else { return false }
                return abs(settings.keystrokeTimeout - times[i - 1]) < 0.05
            case .inspector:
                switch i {
                case 0: return runtime.isInspectorActive
                case 1: return settings.isDragAngleLabelEnabled
                default: return false
                }
            }
        }

        // branch sub의 자식 값들 — 데이터(children 라벨)·isSubSubCurrent·실행이 공유.
        static let spotlightRadii: [CGFloat] = [60, 100, 140, 180, 220]
        static let spotlightSoftnesses: [CGFloat] = [0, 0.4, 0.8]   // 또렷/보통/부드럽게
        static let magnifierZooms: [Double] = [1.5, 2, 2.5, 3, 4]
        static let magnifierSizes: [CGFloat] = [160, 200, 260, 320] // 작게/보통/크게/매우 크게
        static let ringOpacities: [Double] = [1.0, 0.8, 0.6, 0.4, 0.2]  // 100/80/60/40/20%

        /// branch sub의 자식 j가 현재 설정과 일치하는가 — subSub fan 강조용.
        @MainActor
        func isSubSubCurrent(sub: Int, subSub j: Int, settings: CursorSettings, runtime: CursorRuntimeState) -> Bool {
            switch self {
            case .spotlight:
                if sub == 1 { return j < Self.spotlightRadii.count && abs(settings.spotlightRadius - Self.spotlightRadii[j]) < 0.5 }
                if sub == 2 { return j < Self.spotlightSoftnesses.count && abs(settings.spotlightEdgeSoftness - Self.spotlightSoftnesses[j]) < 0.05 }
                return false
            case .magnifier:
                if sub == 1 { return j < Self.magnifierZooms.count && abs(settings.magnifierZoom - Self.magnifierZooms[j]) < 0.05 }
                if sub == 2 { return j < Self.magnifierSizes.count && abs(settings.magnifierSize - Self.magnifierSizes[j]) < 0.5 }
                return false
            case .ringSize:   // 링 외형: 크기/투명도/두께/스타일
                switch sub {
                case 0: let c = RingSize.allCases; return j < c.count && c[j] == settings.ringSize
                case 1: return j < Self.ringOpacities.count && abs(settings.ringOpacity - Self.ringOpacities[j]) < 0.025
                case 2: let c = BorderWeight.allCases; return j < c.count && c[j] == settings.borderWeight
                case 3: let c = BorderStyle.allCases; return j < c.count && c[j] == settings.borderStyle
                default: return false
                }
            default: return false
            }
        }

        /// 서브 fan 각도(°) — 항목 개수가 아니라 **라벨 내용 폭**에 맞춘다. 긴 라벨("매우 크게"/"Extra Large")이면
        /// 적은 개수라도 넓혀 라벨이 붙지 않게. 옆 sector 침범하지만 활성 sector만 표시라 시각 충돌 없음.
        /// 렌더(이 값)와 hittest(주입)가 같은 함수를 쓰도록 RadialMenuItem이 단일 source.
        var subSpan: Double {
            Self.contentSpan(labels: subItems.map(\.label),
                             radius: (Tokens.Radial.mainOuter + Tokens.Radial.subOuter) / 2)
        }

        /// branch sub의 자식 fan 각도 — 자식 라벨 내용 기반.
        func subSubSpan(of subIndex: Int) -> Double {
            guard subIndex < subItems.count, let kids = subItems[subIndex].children, !kids.isEmpty else { return 0 }
            return Self.contentSpan(labels: kids.map(\.label),
                                    radius: (Tokens.Radial.subOuter + Tokens.Radial.subSubOuter) / 2)
        }

        /// 라벨 폭(추정) × 개수를 반경에서 각도로 환산한 fan span. 각 항목이 자기 라벨을 담을 호 길이를
        /// 갖도록 — maxWidth 기준 균등 분할. 50°~150° clamp.
        static func contentSpan(labels: [String], radius: CGFloat) -> Double {
            let n = labels.count
            guard n > 0, radius > 1 else { return 50 }
            let maxW = labels.map(estLabelWidth).max() ?? 20
            let perItemDeg = (maxW + 14) / Double(radius) * 180 / .pi   // 호 길이(라벨폭+gap) → 각도
            return min(150, max(50, perItemDeg * Double(n)))
        }

        /// 라벨 폭 추정(pt) — CJK(한글 등)는 wide(~12pt), 그 외(숫자·영문)는 narrow(~7pt). branch ▸ 여유 포함은 gap에서 흡수.
        static func estLabelWidth(_ s: String) -> Double {
            s.unicodeScalars.reduce(0) { acc, u in
                let v = u.value
                let wide = (0xAC00...0xD7A3).contains(v) || (0x3000...0x9FFF).contains(v) || (0xFF00...0xFFEF).contains(v)
                return acc + (wide ? 12.0 : 7.0)
            }
        }

        /// 서브 항목 — 아이콘(optional SF Symbol)이 있으면 라벨 앞에 렌더링.
        /// 값 선택형 sub(spotlight/magnifier/ringSize/color/ringShape/keystroke)는 icon=nil — 순수 텍스트.
        /// 카테고리형 sub(glow 효과 4종, inspector 좌표/각도 2종)은 SF Symbol로 시각 단서 제공.
        ///
        /// children이 있으면 branch(2단계) — 클릭 대신 더 바깥으로 drag하면 자식 값들이 3번째 ring에
        /// fan으로 펼쳐진다. nil/빈 배열이면 leaf로, 클릭 시 즉시 액션(기존 1단계 동작).
        struct SubItem {
            let icon: String?
            let label: String
            let children: [SubItem]?
            /// dwell 설명 — branch/토글 leaf처럼 라벨만으론 모호한 항목에만 채운다.
            /// nil이면 상위(branch→sector) desc로 폴백. 색/모양/숫자 leaf는 자명해 nil.
            let desc: String?
            var isBranch: Bool { children?.isEmpty == false }

            init(icon: String? = nil, label: String, desc: String? = nil, children: [SubItem]? = nil) {
                self.icon = icon
                self.label = label
                self.desc = desc
                self.children = children
            }
        }

        var subItems: [SubItem] {
            switch self {
            case .spotlight: return [
                SubItem(label: "토글".loc, desc: "스포트라이트를 켜거나 끕니다.".loc),   // leaf — 클릭 즉시 토글
                SubItem(label: "반경".loc, desc: "밝게 남길 원의 반경을 정합니다.".loc, children: [
                    SubItem(label: "60pt"), SubItem(label: "100pt"), SubItem(label: "140pt"),
                    SubItem(label: "180pt"), SubItem(label: "220pt"),
                ]),
                SubItem(label: "경계".loc, desc: "밝은 영역과 어두운 영역 사이 경계의 부드러움을 정합니다.".loc, children: [
                    SubItem(label: "또렷".loc), SubItem(label: "보통".loc), SubItem(label: "부드럽게".loc),
                ]),
            ]
            case .magnifier: return [
                SubItem(label: "토글".loc, desc: "돋보기를 켜거나 끕니다.".loc),
                SubItem(label: "배율".loc, desc: "확대 배율을 정합니다.".loc, children: [
                    SubItem(label: "1.5×"), SubItem(label: "2×"), SubItem(label: "2.5×"),
                    SubItem(label: "3×"), SubItem(label: "4×"),
                ]),
                SubItem(label: "크기".loc, desc: "돋보기 창의 크기를 정합니다.".loc, children: [
                    SubItem(label: "작게".loc), SubItem(label: "보통".loc),
                    SubItem(label: "크게".loc), SubItem(label: "매우 크게".loc),
                ]),
            ]
            case .glow: return [
                SubItem(icon: "lightbulb.fill", label: "글로우".loc, desc: "커서 주위에 은은한 빛 번짐을 더합니다.".loc),
                SubItem(icon: "wind",           label: "트레일".loc, desc: "커서가 지나간 자리에 짧은 잔상을 남깁니다.".loc),
                SubItem(icon: "target",         label: "정지펄스".loc, desc: "커서가 잠시 멈추면 물결 펄스로 위치를 알립니다.".loc),
                SubItem(icon: "sparkle",        label: "코멧".loc, desc: "드래그할 때 혜성 같은 꼬리를 그립니다.".loc),
            ]
            case .ringSize: return [   // "링 외형" — 4개 branch
                SubItem(label: "크기".loc, desc: "링의 지름을 정합니다.".loc, children: RingSize.allCases.map { SubItem(label: $0.label) }),
                SubItem(label: "투명도".loc, desc: "링의 불투명도를 정합니다.".loc, children: Self.ringOpacities.map { SubItem(label: "\(Int($0 * 100))%") }),
                SubItem(label: "두께".loc, desc: "링 외곽선의 두께를 정합니다.".loc, children: BorderWeight.allCases.map { SubItem(label: $0.label) }),
                SubItem(label: "스타일".loc, desc: "링 외곽선의 선 종류(실선·점선 등)를 정합니다.".loc, children: BorderStyle.allCases.map { SubItem(label: $0.label) }),
            ]
            case .color:     return RingColor.allCases.filter { $0 != .custom }.map { SubItem(icon: nil, label: $0.label) }
            case .ringShape: return RingShape.allCases.map { SubItem(icon: nil, label: $0.label) }
            case .inspector: return [
                SubItem(icon: "viewfinder",     label: "좌표".loc, desc: "커서의 화면 좌표(x, y)를 실시간 표시합니다.".loc),
                SubItem(icon: "arrow.up.right", label: "드래그각도".loc, desc: "드래그 중 이동 방향의 각도를 표시합니다.".loc),
            ]
            case .keystroke: return [
                SubItem(icon: nil, label: "토글".loc),
                SubItem(icon: nil, label: "1초".loc),
                SubItem(icon: nil, label: "2초".loc),
                SubItem(icon: nil, label: "4초".loc),
                SubItem(icon: nil, label: "8초".loc),
            ]
            }
        }
    }

    enum RingShape: String, CaseIterable, Identifiable {
        case circle, squircle, rhombus, hexagon
        var id: String { rawValue }
        var label: String {
            switch self {
            case .circle:   return "원형".loc
            case .squircle: return "둥근 사각형".loc
            case .rhombus:  return "둥근 마름모".loc
            case .hexagon:  return "둥근 육각형".loc
            }
        }
    }

    enum RingSize: String, CaseIterable, Identifiable {
        case small, medium, large, xlarge
        var id: String { rawValue }

        var diameter: CGFloat {
            switch self {
            case .small:  return 36
            case .medium: return 54
            case .large:  return 72
            case .xlarge: return 96
            }
        }
        var label: String {
            switch self {
            case .small:  return "작게 (36pt)".loc
            case .medium: return "보통 (54pt)".loc
            case .large:  return "크게 (72pt)".loc
            case .xlarge: return "매우 크게 (96pt)".loc
            }
        }
    }

    enum AnimationSpeed: String, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: String { rawValue }

        var multiplier: Double {
            switch self {
            case .slow:   return 1.7
            case .normal: return 1.0
            case .fast:   return 0.5
            }
        }
        var label: String {
            switch self {
            case .slow:   return "느리게".loc
            case .normal: return "보통".loc
            case .fast:   return "빠르게".loc
            }
        }
    }

    /// 흔들기 감지 민감도 — 방향 전환 횟수로 매핑. 적을수록 살짝 흔들어도 발동(민감), 많을수록 둔감.
    /// 라디얼 메뉴를 여는 마우스 동작. `⌃⌥,` 단축키는 이 설정과 무관하게 항상 동작한다.
    /// 좌클릭 길게는 드래그·텍스트 선택 등과 충돌이 잦아 기본값은 가운데 버튼.
    /// (트랙패드엔 가운데 버튼이 없으므로 트랙패드 사용자는 '좌클릭 길게' 또는 `⌃⌥,`를 쓴다.)
    enum RadialOpenTrigger: String, CaseIterable, Identifiable {
        case middleClick, longPress, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .middleClick: return "가운데 버튼".loc
            case .longPress:   return "좌클릭 길게".loc
            case .off:         return "끄기 (단축키만)".loc
            }
        }
    }

    enum ShakeSensitivity: String, CaseIterable, Identifiable {
        case sensitive, normal, insensitive
        var id: String { rawValue }

        /// 감지에 필요한 0.5초 내 방향 전환 횟수.
        var requiredDirChanges: Int {
            switch self {
            case .sensitive:   return 3
            case .normal:      return 5
            case .insensitive: return 8
            }
        }
        var label: String {
            switch self {
            case .sensitive:   return "민감".loc
            case .normal:      return "보통".loc
            case .insensitive: return "둔감".loc
            }
        }
    }

    enum BorderWeight: String, CaseIterable, Identifiable {
        case thin, normal, bold, heavy
        var id: String { rawValue }
        var lineWidth: CGFloat {
            switch self {
            case .thin:   return 1.5
            case .normal: return 3.0
            case .bold:   return 5.5
            case .heavy:  return 9.0
            }
        }
        var label: String {
            switch self {
            case .thin:   return "얇게".loc
            case .normal: return "보통".loc
            case .bold:   return "굵게".loc
            case .heavy:  return "두껍게".loc
            }
        }
    }

    enum BorderStyle: String, CaseIterable, Identifiable {
        case solid, dashed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .solid:  return "실선".loc
            case .dashed: return "대시".loc
            }
        }
    }

    /// UI 표시 언어 — .system이면 macOS 시스템 설정 따름.
    /// 실제 적용은 main.swift에서 NSApplication 인스턴스 생성 전에 AppleLanguages override.
    enum PreferredLanguage: String, CaseIterable, Identifiable {
        case system, ko, en
        var id: String { rawValue }

        /// AppleLanguages override에 사용할 코드. .system은 nil — override 해제.
        var languageCode: String? {
            switch self {
            case .system: return nil
            case .ko:     return "ko"
            case .en:     return "en"
            }
        }

        /// 환경설정·메뉴 표시용 라벨 — 자기 언어로 표기 (사용자가 모르는 언어로 적혀 있어도 알아볼 수 있게).
        var label: String {
            switch self {
            case .system: return "시스템 기본"
            case .ko:     return "한국어"
            case .en:     return "English"
            }
        }
    }
}
