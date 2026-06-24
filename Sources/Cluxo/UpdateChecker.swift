import Foundation
import Combine

/// GitHub Releases에서 최신 버전을 백그라운드로 조회해 새 버전 유무를 알린다.
/// 시작 시 1회 + 24시간마다 체크. UserDefaults에 마지막 체크 시각을 저장해 과도한 요청을 막는다.
/// 실제 알림(메뉴바 배지·메뉴 항목)은 AppDelegate가 `availableVersion`을 구독해 갱신한다.
@MainActor
final class UpdateChecker: ObservableObject {
    /// 현재 버전보다 높은 release가 있으면 그 버전 문자열(예 "1.2.7"), 없으면 nil.
    @Published private(set) var availableVersion: String?

    private let currentVersion: String
    private let repo: String
    private var timer: Timer?

    private static let lastCheckKey = "lastUpdateCheck"
    /// 자동 체크 간격(초) — 하루 1회.
    private let checkInterval: TimeInterval = 24 * 60 * 60
    /// 주기 타이머가 due 여부를 재평가하는 간격 — 앱이 오래 떠 있어도 하루 단위로 체크되게.
    private let pollInterval: TimeInterval = 60 * 60

    init(currentVersion: String, repo: String = "kykim79/Cluxo") {
        self.currentVersion = currentVersion
        self.repo = repo
    }

    deinit { timer?.invalidate() }

    /// 시작 시 호출 — 직전 체크가 interval 이내면 건너뛰고, 이후 1시간마다 due 여부를 재평가한다.
    func start() {
        Task { await checkIfDue() }
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
        // 메뉴 트래킹·모달 중에도 동작하도록 common mode 등록.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func checkIfDue() async {
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < checkInterval {
            return
        }
        await check()
    }

    /// 즉시 체크(주기 무시). 네트워크 실패는 조용히 무시 — 다음 주기에 재시도한다.
    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct Release: Decodable { let tag_name: String }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            // numeric 비교 — 0.1.10 > 0.1.2 정확히 처리.
            availableVersion = (currentVersion.compare(latest, options: .numeric) == .orderedAscending) ? latest : nil
        } catch {
            // 무시 (오프라인 등)
        }
    }
}
