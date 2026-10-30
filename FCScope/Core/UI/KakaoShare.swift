import UIKit
import KakaoSDKCommon
import KakaoSDKShare
import KakaoSDKTemplate

/// 카카오톡 공유 (Kakao Developers 네이티브 앱 키 = Info.plist FCKakaoAppKey, URL 스킴 kakao{키}).
/// SwiftUI 의 Link·Button 과 이름이 겹쳐 SwiftUI 를 import 하지 않는 파일에 둔다.
enum KakaoShare {
    private static let appKey = Bundle.main.object(forInfoDictionaryKey: "FCKakaoAppKey") as? String

    static func configure() {
        if let appKey { KakaoSDK.initSDK(appKey: appKey) }
    }

    /// 앱이 있으면 `path`(fcscope:// 뒤 경로)로 열리고, 없으면 콘솔에 등록한 App Store 로 간다.
    private static func link(_ path: String?) -> Link {
        let web = path.flatMap { URL(string: $0, relativeTo: AppConfig.productionBase) } ?? AppConfig.productionBase
        return Link(webUrl: web, mobileWebUrl: web, iosExecutionParams: path.map { ["path": $0] })
    }

    /// 친구 리그 순위처럼 글만 보낼 때
    static func shareText(_ text: String, path: String?, button: String = "FC Scope 에서 보기") {
        send(TextTemplate(text: String(text.prefix(200)), link: link(path), buttonTitle: button))
    }

    /// 공유 카드 — 카카오 서버에 이미지를 올린 뒤(템플릿은 이미지 URL 만 받는다) 피드로 보낸다.
    static func shareImage(_ image: UIImage, title: String, completion: @escaping (Bool) -> Void = { _ in }) {
        ShareApi.shared.imageUpload(image: image) { result, _ in
            guard let url = result?.infos.original.url else { return DispatchQueue.main.async { completion(false) } }
            let l = link(nil)
            let content = Content(title: title, imageUrl: url,
                                  imageWidth: Int(image.size.width * image.scale), imageHeight: Int(image.size.height * image.scale),
                                  link: l)
            DispatchQueue.main.async {
                send(FeedTemplate(content: content, buttons: [Button(title: "FC Scope 에서 보기", link: l)]))
                completion(true)
            }
        }
    }

    /// 카카오톡이 없으면(시뮬레이터 포함) 웹 공유 화면으로.
    private static func send(_ t: Templatable) {
        if ShareApi.isKakaoTalkSharingAvailable() {
            ShareApi.shared.shareDefault(templatable: t) { r, _ in
                if let url = r?.url { UIApplication.shared.open(url) }
            }
        } else if let url = ShareApi.shared.makeDefaultUrl(templatable: t) {
            UIApplication.shared.open(url)
        }
    }

    /// 공유 메시지 버튼으로 열린 kakao{키}://kakaolink?path=... → fcscope://... (AppRouter 가 다시 검사한다)
    static func appURL(from url: URL) -> URL? {
        guard let appKey, url.scheme == "kakao\(appKey)", url.host == "kakaolink",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "path" })?.value
        else { return nil }
        return URL(string: "fcscope://\(path)")
    }
}
