import Foundation

/**
 최적화: 넥슨 CDN 직접 접근.

 웹은 CORS 때문에 `/api/player-image/:spid` 서버 프록시를 거쳐야 하지만,
 **네이티브 앱에는 CORS가 없다.** 실측 결과 넥슨 CDN 은 인증·핫링크 차단 없이 200 을 반환한다.

 프록시를 거치면 선수 이미지 1장(액션샷 ≈ 48KB)마다 서버 함수 호출 + 대역폭이 발생하고,
 전적 화면 1회(선수 18~28장)에 0.9~1.3MB 가 서버를 통과한다. 앱이 CDN 을 직접 부르면 0 이 된다.

 폴백 체인은 서버 프록시와 동일: 액션샷(spid) → 기본 이미지(pid) → 실루엣.
 */
enum NexonCDN {
    static let base = "https://fco.dn.nexoncdn.co.kr/live/externalAssets/common"

    /// spid → 시도 순서대로의 이미지 URL. 앞에서부터 성공한 것을 쓴다.
    static func playerImageURLs(spid: Int) -> [URL] {
        let pid = spid % 1_000_000
        return [
            "\(base)/playersAction/p\(spid).png",
            "\(base)/players/p\(pid).png",
        ].compactMap(URL.init(string:))
    }

    /// spid = seasonId * 1_000_000 + pid
    static func seasonId(of spid: Int) -> Int { spid / 1_000_000 }
    static func pid(of spid: Int) -> Int { spid % 1_000_000 }

    /// 서버가 내려주는 `/api/player-image/123` 경로에서 spid 추출 (구버전 응답 호환).
    static func spid(fromProxyPath path: String) -> Int? {
        guard let last = path.split(separator: "/").last else { return nil }
        return Int(last)
    }
}
