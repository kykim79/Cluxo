import Foundation

// SwiftUI의 LocalizedStringKey 자동 추출은 **정적 리터럴**만 인식한다 — `Text("노란색")`은 자동
// localized되지만, `Text(enum.label)`처럼 String 변수를 넘기면 fixed로 표시된다. 우리는 enum.label
// /Persisted enum/동적 값을 UI에 자주 노출하므로, label 안에서 명시적으로 NSLocalizedString을 통해
// String Catalog lookup을 수행한다.
//
// 사용:
//   var label: String { "노란색".loc }       // enum body 안
//   desc(text.loc)                          // 동적 desc 텍스트
//
// 한국어 source key는 Localizable.xcstrings("sourceLanguage": "ko")에 그대로 들어 있어야 영어로 변환된다.
extension String {
    var loc: String { NSLocalizedString(self, comment: "") }
}
