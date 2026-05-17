# TODOS

`/plan-eng-review` 리뷰(2026-05-17)에서 발견된 개선점 중 보류한 항목들. 우선순위는 `P1`(구조/안전) → `P2`(성능/DRY) → `P3`(배포/테스트) 순.

위치는 함수·섹션 단위로 기록 (코드 변경에 강함). 정확한 라인은 `grep` 또는 Xcode `⇧⌘O`.

---

## P1 — 구조 / 안전성

### #2 ScreenCaptureKit 마이그레이션
- **위치**: `AppDelegate.swift` (`startMagnifierCapture`, `requestScreenRecordingPermission`, `promptRelaunchIfNeeded`)
- **문제**: `CGWindowListCreateImage`가 macOS 14+에서 deprecated. 동작은 macOS 16(현재)까지 유지되나 향후 제거 가능. 돋보기가 앱의 핵심 기능 중 하나.
- **방향**: `SCStream` 기반으로 전환. 한 번 stream 켜놓고 cursor 주변 cropping이 20Hz 폴링보다 효율적.
- **상태**: 코드에 `// TODO:` 코멘트 표시됨. 별도 세션에서 ~1-2시간 작업.

### #4 CursorState God Object 분할
- **위치**: `CursorState.swift` 전체 (460줄, `@Published` **44개**)
- **문제**: 4가지 책임이 한 클래스에 묶임 (런타임 상태 / 설정 / 효과 큐 / 키스트로크 오버레이). 어느 `@Published` 하나만 바뀌어도 `ObservableObject` 전체가 재발행되어 무관한 view까지 재계산. **이번에 잡은 60% CPU 폭주와 같은 원리.**
- **방향**: 4개로 분리
  - `CursorSettings` — UserDefaults-backed 모든 설정
  - `CursorRuntimeState` — cursorPosition, isCursorVisible, drag, glow
  - `EffectsState` — click/scroll/trail/shake/clipboard 효과 큐
  - `KeystrokeOverlayState` — 키스트로크 + 상태 알림
- **영향**: 각 View가 필요한 객체만 `@ObservedObject` → 60Hz cursorPosition 변경이 ring 설정 view를 흔들지 않게 됨.

### #5 AppDelegate God Object 분할
- **위치**: `AppDelegate.swift` 전체 (~540줄)
- **문제**: 7가지 책임 (메뉴바 / 마우스 라우팅 / 키보드 / 권한 / 녹화 감지 / 돋보기 캡처 / 오버레이 lifecycle).
- **방향**: 최소 4개 분리
  - `MagnifierCaptureService`
  - `KeyboardHotkeyHandler`
  - `PermissionsManager`
  - `RecordingDetector`

---

## P2 — DRY / 성능

### #6 @Persisted PropertyWrapper로 UserDefaults DRY
- **위치**: `CursorState.swift` `init()` (40줄) + 28개 `@Published`의 `didSet` (60줄)
- **문제**: 같은 패턴이 28번 반복:
  ```swift
  @Published var foo: T = default { didSet { UserDefaults.standard.set(...) } }
  // init에서: let x = UserDefaults.standard.X(forKey:); if x > 0 { foo = x }
  ```
- **방향**: 커스텀 PropertyWrapper로 압축:
  ```swift
  @Persisted("ringOpacity", default: 1.0, debounce: 0.3) var ringOpacity: Double
  ```
- **임팩트**: init 40줄 + didSet 60줄 → ~10줄.

### #7 CursorRingView 매개변수 15개 → RingStyle struct
- **위치**: `OverlayContentView.swift` `CursorRingView`
- **문제**: 생성자 매개변수 16개 (position 포함). 옵션 추가 시 호출부도 매번 수정.
- **방향**: 설정 14개를 `RingStyle` struct로 묶기.

### #8 NSScreen.screens.first?.frame.height 캐시
- **위치**: `AppDelegate.swift` `handleMouseMove`, `startMagnifierCapture`
- **문제**: 60Hz throttle 후에도 매 호출마다 `NSScreen.screens` 배열 쿼리. 20Hz 돋보기 timer에서도 동일.
- **방향**: `screensChanged()`에서 `primaryScreenHeight` 캐시.

### #9 addScrollEffect의 removeAll 다중 모니터 race
- **위치**: `CursorState.swift` `addScrollEffect`
- **문제**: 한 화면에서 스크롤하면 모든 화면의 효과를 다 지움. 다중 모니터에서 다른 화면 효과가 살아 있을 때 같이 꺼짐.

### #10 saveCustomColor만 debounce 없음
- **위치**: `CursorState.swift` `customRingColor` `didSet` → `saveCustomColor()`
- **문제**: ColorPicker 슬라이더 드래그하는 동안 매 변경마다 NSColor 변환 + UserDefaults 호출. 다른 슬라이더는 다 `debouncedSet` 쓰는데 이것만 빠짐.

---

## P3 — 배포 / 테스트

### #11 테스트 인프라 (순수 함수만이라도)
- **위치**: 프로젝트 전체에 테스트 0개
- **문제**: 흔들기 감지 같은 알고리즘은 회귀 위험이 큰데 매번 직접 흔들어보며 검증해야 함.
- **방향**: GUI 이벤트 핸들링은 어렵지만 순수 함수는 충분히 테스트 가능:
  - `MouseEventMonitor.processMove` — 흔들기 감지 (시뮬레이션 데이터)
  - `AppDelegate.formatKey` — 키 포맷팅 (NSEvent mock)
  - `CursorState.updateDragAngle` — atan2 wrapping (±π 경계)
  - 좌표계 변환 (Quartz top-left ↔ Cocoa bottom-left)
- **시작**: `Tests/CursorHighlightTests/` 디렉토리 + `project.yml`에 test target 추가.

### #12 Notarization (Gatekeeper 마찰 제거)
- **위치**: 배포 절차, README
- **문제**: 사용자가 `xattr -dr com.apple.quarantine` 직접 실행해야 함. 큰 마찰.
- **방향**: Apple Developer Program 가입 ($99/년) + GitHub Actions에 notarization 자동화. 더블클릭으로 설치 가능해짐.
- **트레이드오프**: 비용 + 매년 갱신 vs 사용자 경험.

### #13 "업데이트 확인" 버튼 실제 동작
- **위치**: `PreferencesView.swift` `InfoTab` (`Section("업데이트")`)
- **문제**: 버튼을 누르면 무조건 "최신 버전입니다"만 출력. 실제 체크 없음.
- **방향 (택1)**:
  - **A.** [Sparkle](https://sparkle-project.org/) 통합 — 자동 업데이트
  - **B.** GitHub Releases API 폴링 — 최신 태그와 `CFBundleShortVersionString` 비교
  - **C.** 버튼 일시 숨김 (정직)

---

## 기타

### git author 글로벌 설정
- **현재 상태**: `ktoy <ktoy@ktoyui-Macmini.local>` / `ktoy@ktoyui-MacBookPro.local`로 자동 잡힘 → GitHub contribution 그래프에 안 잡힐 수 있음.
- **방향**:
  ```bash
  git config --global user.name "kykim79"
  git config --global user.email "kykim79@gmail.com"
  ```
- **참고**: 이전 두 커밋의 author 재작성은 `git filter-branch` 또는 `rebase` 필요한데 이미 push된 상태라 위험. 앞으로의 커밋만 정리하는 게 안전.

---

## 완료된 작업 (참고)

`aaa8dcb fix: 환경설정 닫을 때 view tree 해제로 CPU 폭주 수정`에 묶여서 처리:

- ✅ **#1** Force cast 방어 — `AppDelegate.isPasswordFieldFocused`
- ✅ **#3** EventTap enum 분기 — `MouseEventMonitor.start` callback
- ✅ **#7 (Preferences leak)** view tree 해제 — `AppDelegate.openPreferences` (CPU 60% → 0%)
- 📝 **#2** ScreenCaptureKit TODO 코멘트만 추가 (위 P1 #2 참조)
