#if DEBUG
import Foundation

/// 개발 전용 목 데이터 — `-communityMock full|legacy|empty` 로 실행하면 커뮤니티가 서버 대신 이걸 쓴다.
/// - full: v2 서버(조회·추천·답글·hot·mine·shortLabel 있음)
/// - legacy: 0023 마이그레이션 전 서버(v2 키가 전부 없음) — UI 가 조용히 숨는지 검수
/// - hybrid: **스키마 v2 + 코드 v1**(2026-10 프로덕션 실측, QA P0-1) — like_count·view_count 는 오지만(0)
///   목록에 sort·hot 없음, 추천 라우트 404, parent_id 는 버려진다. 앱은 추천을 숨기고 답글을 "@닉 "으로 보내야 한다.
/// - empty: 글 0개(빈 상태)
/// 추가 인자: `-communityScreen detail|battle|compose|comments`, `-communityPost <id>` — 바로 해당 화면을 연다.
/// 릴리스 빌드에는 컴파일되지 않는다.
@MainActor
final class CommunityMock {
    enum Mode: String { case full, legacy, hybrid, empty }
    static let active: CommunityMock? = {
        guard let raw = UserDefaults.standard.string(forKey: "communityMock"), let m = Mode(rawValue: raw) else { return nil }
        return CommunityMock(mode: m)
    }()

    let mode: Mode
    private var posts: [[String: Any]] = []
    private var comments: [String: [[String: Any]]] = [:]
    private var likedPosts: Set<String> = []
    private var likedComments: Set<String> = []
    private var votes: [String: (a: Int, b: Int, mine: String?)] = [:]
    private var seq = 100
    private let me = "u-me"

    private init(mode: Mode) {
        self.mode = mode
        if mode != .empty { seed() }
    }

    private func ago(_ minutes: Double) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date().addingTimeInterval(-minutes * 60))
    }

    private static let typeInfo: [(String, String, String, String, [String])] = [
        ("squad_show", "스쿼드 자랑", "자랑", "🏆", ["squad"]),
        ("squad_rate", "스쿼드 평가 요청", "평가", "🧐", ["squad", "budget"]),
        ("squad_battle", "스쿼드 배틀", "배틀", "⚔️", ["squad", "squad_b"]),
        ("squad_make", "스쿼드 만들어줘", "만들어줘", "🛠️", ["budget"]),
        ("club_recruit", "클럽원 모집", "클럽모집", "🤝", ["region", "positions", "contact"]),
        ("club_match", "클럽전 상대 구함", "클럽전", "🥅", ["region", "schedule", "contact"]),
        ("tournament", "대회", "대회", "🏟️", ["date", "format", "entry", "contact"]),
    ]
    private var types: [[String: Any]] {
        Self.typeInfo.map { t in
            var d: [String: Any] = [
                "type": t.0, "label": t.1, "emoji": t.3, "accent": "tint", "fields": t.4,
                "blurb": t.0 == "club_recruit" ? "함께할 클럽원을 찾아요. 지역·포지션을 적으면 빨리 모여요." : t.0 == "squad_rate" ? "스쿼드를 올리면 다른 유저가 평가해 줘요. 예산을 적으면 더 정확해요." : "\(t.1) 글을 올려요.",
                "template": t.0 == "squad_rate" ? "■ 예산:\n■ 주 포메이션:\n■ 고민되는 포지션:\n" : t.0 == "club_recruit" ? "■ 클럽 이름:\n■ 활동 시간:\n■ 조건:\n" : "",
                "bodyLabel": "내용",
                "bodyPlaceholder": t.0 == "club_recruit" ? "어떤 클럽인지, 어떤 분을 찾는지 적어 주세요.\n예) 주 3회 저녁 9시 · 월클 이상 · 디코 필수" : "내용을 적어 주세요.",
            ]
            if mode == .full { d["shortLabel"] = t.2 }
            return d
        }
    }

    private func post(_ id: String, _ type: String, _ title: String, nick: String, verified: Bool = false, op: Bool = false,
                      min: Double, comments: Int, views: Int, likes: Int, squad: String? = nil, squadB: String? = nil,
                      region: String? = nil, body: String = "", meta: [String: String] = [:], author: String? = nil,
                      positions: [String] = [], contact: String? = nil) -> [String: Any] {
        let label = Self.typeInfo.first { $0.0 == type }?.1 ?? type
        var metaRows: [[String: String]] = []
        let names = ["budget": "예산", "schedule": "가능 시간", "date": "일정", "format": "형식", "entry": "참가 방법", "formation": "포메이션"]
        for (k, v) in meta.sorted(by: { $0.key < $1.key }) where k != "squad_b" && !k.hasPrefix("attach_") { metaRows.append(["key": k, "label": names[k] ?? k, "value": v]) }
        var p: [String: Any] = [
            "id": id, "author_id": author ?? "u-\(nick)", "type": type, "title": title,
            "body": body.isEmpty ? "\(title)\n\n본문 예시입니다. 실제 서버 데이터가 아닌 개발용 목 데이터예요." : body,
            "positions": positions, "meta": meta, "status": "open", "created_at": ago(min), "comment_count": comments,
            "author": ["id": author ?? "u-\(nick)", "nickname": nick, "verifiedNickname": verified ? nick as Any : NSNull(), "isOperator": op],
            "typeLabel": label, "typeEmoji": "📝", "preview": "미리보기", "metaRows": metaRows,
        ]
        if let squad { p["squad_id"] = squad }
        if let squadB { p["squadB"] = squadB }
        if let region { p["region"] = region }
        if let contact { p["contact"] = contact }
        if mode == .full { p["view_count"] = views; p["like_count"] = likes; p["viewerLiked"] = false }
        // 혼합 서버: 컬럼 기본값(0)만 오고 조회·추천은 늘지 않는다
        if mode == .hybrid { p["view_count"] = 0; p["like_count"] = 0 }
        return p
    }

    private func seed() {
        posts = [
            post("p1", "squad_rate", "도르트문트 팀컬러 4-2-3-1 평가 부탁드려요", nick: "보엠", verified: true, min: 3, comments: 12, views: 248, likes: 9, squad: "bvb1",
                 body: "팀컬러 맞추느라 미드필더 쪽이 좀 약한 거 같아요. 지금 월클 2부 왔다 갔다 하는데 1부 가려면 어디부터 바꾸는 게 좋을까요?\n\n로이스는 애정픽이라 빼기 싫고 ㅎㅎ 수비형 미드가 제일 고민이에요.",
                 meta: ["budget": "센터백 1명분", "formation": "4-2-3-1"]),
            post("p2", "squad_battle", "EPL 올스타 vs 라리가 올스타, 어디가 더 셈?", nick: "피파탐색이", verified: true, min: 12, comments: 47, views: 12_400, likes: 61, squad: "epl", squadB: "laliga",
                 body: "둘 다 예산 비슷하게 맞췄어요. 어느 쪽이 랭겜에서 더 잘 먹힐까요?"),
            post("p3", "squad_make", "3천억으로 EPL 4-3-3 짜줘요 (월클 목표)", nick: "몽키스패누", min: 25, comments: 5, views: 310, likes: 2,
                 meta: ["budget": "3천억"].merging(PostAttach(kind: .record, me: "SEPTEMBERSKY").metaEntries) { a, _ in a }),
            post("p4", "squad_show", "드디어 맞춘 리버풀 풀금카 ㅋㅋㅋ 인증", nick: "신카레49", verified: true, min: 41, comments: 31, views: 2104, likes: 38, squad: "bvb1"),
            post("p5", "club_recruit", "경기권 월클 이상 클럽원 2명 구해요 (주 3회)", nick: "낭만축구동호회", min: 62, comments: 3, views: 187, likes: 0, region: "경기",
                 positions: ["CB", "CDM"], contact: "디스코드 nangman#1234"),
            post("p6", "tournament", "10월 3주차 FC Scope 컵 — 32강 토너먼트 모집", nick: "보엠", op: true, min: 125, comments: 88, views: 5812, likes: 104,
                 meta: ["date": "10/18(토) 21시", "format": "32강 싱글 엘리미네이션", "entry": "댓글로 구단주명"]),
            post("p7", "squad_rate", "보엠 vs 팔디 — 누가 요즘 더 잘하나요", nick: "R카를로스UFO슛팅", min: 130, comments: 3, views: 96, likes: 0,
                 meta: PostAttach(kind: .versus, me: "보엠", with: "팔디").metaEntries),
            post("p8", "squad_make", "손흥민·이강인·김민재 넣은 국대 스쿼드, 나머지 자리 추천해 주세요 예산은 넉넉합니다", nick: "SEPTEMBERSKY", verified: true, min: 190, comments: 0, views: 74, likes: 0),
            post("p9", "squad_show", "화폐개혁 후 첫 1조 스쿼드 완성했습니다", nick: "데용인데용", min: 1500, comments: 64, views: 8930, likes: 212, squad: "bvb1"),
            post("p10", "club_match", "토요일 밤 클럽전 상대 구해요 (5:5)", nick: "새벽FC", min: 1700, comments: 2, views: 120, likes: 1, region: "서울", meta: ["schedule": "토 22시"]),
            post("p11", "squad_rate", "4-1-2-1-2 좁은 전술 평가 좀", nick: "투볼란치", min: 2000, comments: 7, views: 401, likes: 4, squad: "bvb1"),
            post("p12", "squad_show", "맨시티 팀컬러 완성 기념", nick: "하늘색", min: 2600, comments: 9, views: 655, likes: 12, squad: "bvb1"),
            // 2페이지(무한 스크롤 검수) — 예전엔 1페이지 글을 id 만 바꿔 다시 줘서 같은 행이 두 번 보였다(디자인 리뷰)
            post("p13", "squad_rate", "4-4-2 다이아 투톱 조합 어떤가요", nick: "투톱러버", min: 3100, comments: 4, views: 210, likes: 3, squad: "bvb1"),
            post("p14", "club_recruit", "부산 클럽 '해운대FC' 미드필더 구합니다", nick: "해운대FC", min: 3600, comments: 2, views: 98, likes: 1, region: "부산",
                 positions: ["CM", "CAM"], contact: "오픈채팅 해운대FC"),
            post("p15", "squad_show", "첫 금카 강화 성공 기념 스쿼드", nick: "강화왕", min: 4300, comments: 11, views: 870, likes: 15, squad: "bvb1"),
            post("p16", "squad_make", "1천억으로 라리가 팀컬러 가능할까요", nick: "엘클라시코", min: 5000, comments: 6, views: 260, likes: 2, meta: ["budget": "1천억"]),
            post("p17", "tournament", "주말 번개 16강 컵 (참가비 없음)", nick: "주말리그", min: 5800, comments: 14, views: 640, likes: 9,
                 meta: ["date": "10/12(일) 20시", "format": "16강 싱글", "entry": "댓글로 구단주명"]),
            post("p18", "squad_rate", "수비가 너무 약한데 어디부터 바꿀까요", nick: "실점머신", min: 6500, comments: 8, views: 330, likes: 4, squad: "bvb1"),
        ]
        var c1: [[String: Any]] = []
        func c(_ id: String, _ nick: String, _ body: String, min: Double, likes: Int, parent: String? = nil, author: String? = nil, op: Bool = false, squad: String? = nil, own: Bool = false, verified: Bool = false) -> [String: Any] {
            var d: [String: Any] = ["id": id, "post_id": "p1", "author_id": author ?? "u-\(nick)", "body": body, "created_at": ago(min),
                                    "author": ["id": author ?? "u-\(nick)", "nickname": nick, "isOperator": op, "verifiedNickname": verified ? nick as Any : NSNull()], "isOwn": own]
            if let squad { d["squad_id"] = squad }
            if mode == .full {
                d["like_count"] = likes; d["viewerLiked"] = false
                if let parent { d["parent_id"] = parent }
            }
            if mode == .hybrid { d["like_count"] = 0 }
            return d
        }
        c1 = [
            c("c1", "신카레49", "수미 자리에 24UCL 카세미루 박으세요. 예산 안에서 체감 제일 큼", min: 2, likes: 14),
            c("c2", "보엠", "@신카레49 오 카세미루 생각 못 했네요 바로 찾아볼게요 감사합니다!!", min: 1, likes: 2, parent: "c1", author: "u-보엠", verified: true),
            c("c3", "피파탐색이", "로이스 애정픽이면 인정이죠 ㅋㅋ 대신 풀백 금카 강화가 먼저일 듯. 제가 짜본 거 첨부해요", min: 8, likes: 6, squad: "bvb1", verified: true),
            c("c3r1", "투볼란치", "풀백 동의합니다", min: 7, likes: 1, parent: "c3"),
            c("c3r2", "하늘색", "저도 풀백부터 바꿨는데 체감 큼", min: 6, likes: 0, parent: "c3"),
            c("c3r3", "새벽FC", "@하늘색 어떤 풀백 쓰셨어요?", min: 5, likes: 0, parent: "c3"),
            c("c3r4", "데용인데용", "알폰소 데이비스 추천", min: 4, likes: 3, parent: "c3"),
            c("c3r5", "몽키스패누", "ㅇㅈ", min: 3, likes: 0, parent: "c3"),
            c("c4", "몽키스패누", "스쿼드 클리닉 돌려보면 약점 포지션이 바로 나와요. 전적 탭 → 스쿼드 진단 👀", min: 10, likes: 3, op: true),
            c("c5", "호나우지성", "팀컬러 감성 미쳤다...", min: 15, likes: 1),
            c("c6", "개발자", "내가 쓴 댓글(삭제 메뉴 검수용)", min: 0.5, likes: 0, author: me, own: true),
        ]
        // 시간순(등록순) — 서버도 created_at 오름차순으로 준다
        c1.sort { ($0["created_at"] as! String) < ($1["created_at"] as! String) }
        comments["p1"] = c1
        // 시드 댓글이 없는 글은 목록의 comment_count 만큼 채운다 — 목록 [47] 인데 상세 "댓글 1"이던 목 불일치(유저 패널 C)
        let fillers = ["EPL 압박이 랭겜에선 더 셈", "라리가 미드 퀄리티가 다름", "둘 다 좋은데 저는 A", "B 수비라인이 더 단단해 보여요",
                       "이건 투표 박빙이겠네", "ㅋㅋㅋ 둘 다 갖고 싶다", "공격은 A, 밸런스는 B", "랭겜이면 무조건 A", "와 스쿼드 미쳤다"]
        let nicks = ["압박장인", "티키타카", "역습의신", "수미장인", "골넣는GK", "카세미루팬", "윙어사랑", "볼란치"]
        for p in posts where comments[p["id"] as! String] == nil {
            let id = p["id"] as! String
            let n = min(12, (p["comment_count"] as? Int) ?? 0)
            comments[id] = (0..<n).map { i in
                var d: [String: Any] = ["id": "\(id)-c\(i)", "post_id": id, "author_id": "u-f\(i % nicks.count)", "body": fillers[i % fillers.count],
                                        "created_at": ago(Double(60 - i)), "author": ["id": "u-f\(i % nicks.count)", "nickname": nicks[i % nicks.count]], "isOwn": false]
                if mode == .full { d["like_count"] = (i * 7) % 5; d["viewerLiked"] = false }
                if mode == .hybrid { d["like_count"] = 0 }
                return d
            }
            // 목록 숫자 = 실제로 받는 댓글 수(채움 상한 12)
            if let i = posts.firstIndex(where: { ($0["id"] as! String) == id }) { posts[i]["comment_count"] = n }
        }
        votes["p2"] = (193, 119, UserDefaults.standard.string(forKey: "communityVoted"))
    }

    private func decode<T: Decodable>(_ obj: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: 엔드포인트

    func list(_ q: [String: String]) async throws -> PostListResponse {
        // -communitySlow YES — 스켈레톤 검수용으로 목록 응답을 늦춘다
        try? await Task.sleep(for: .milliseconds(UserDefaults.standard.bool(forKey: "communitySlow") ? 60_000 : 350))
        var rows = posts
        let filter: Set<String>? = q["types"].map { Set($0.split(separator: ",").map(String.init)) } ?? q["type"].map { [$0] }
        if mode == .full, let filter { rows = rows.filter { filter.contains($0["type"] as! String) } }
        else if let t = q["type"] { rows = rows.filter { ($0["type"] as! String) == t } }
        // empty 는 "글이 없는 v2 서버" — full 과 같은 칩 구성(전체 칩·정렬)이 나오게 sort 를 준다(디자인 리뷰 재캡처 요청 3)
        let sort = (mode == .full || mode == .empty) ? (q["sort"] ?? "new") : nil
        if sort == "hot" { rows.sort { (($0["like_count"] as? Int) ?? 0) > (($1["like_count"] as? Int) ?? 0) } }
        if sort == "comments" { rows.sort { (($0["comment_count"] as? Int) ?? 0) > (($1["comment_count"] as? Int) ?? 0) } }
        let page = Int(q["page"] ?? "1") ?? 1
        // 페이지네이션 — 한 장 12개. 필터로 글이 적으면 1장뿐이다(같은 글을 두 번 주지 않는다).
        let pageSize = 12
        let totalPages = max(1, Int((Double(rows.count) / Double(pageSize)).rounded(.up)))
        let slice = Array(rows.dropFirst((page - 1) * pageSize).prefix(pageSize))
        var res: [String: Any] = ["page": page, "totalPages": totalPages, "types": types, "posts": slice]
        if let sort { res["sort"] = sort }
        if mode == .full, page == 1, q["types"] == nil, q["type"] == nil, sort == "new" {
            res["hot"] = ["p2", "p9", "p6"].compactMap { id in posts.first { ($0["id"] as! String) == id } }
        }
        // 실서버(0023 적용)는 글이 없어도 1페이지에 `hot: []` 를 준다 — 빼면 1차 탭에서 "인기"가 사라졌다(디자인 2R N-5)
        if mode == .empty, page == 1 { res["hot"] = [Any]() }
        return try decode(res)
    }

    func detail(_ rawId: String) async throws -> PostDetailResponse {
        try? await Task.sleep(for: .milliseconds(300))
        let id = rawId
        guard var p = posts.first(where: { ($0["id"] as! String) == id }) else {
            throw APIError.server(code: "not_found", message: "삭제됐거나 숨겨진 글이에요.", status: 404, retryAfter: nil)
        }
        if mode == .full { p["viewerLiked"] = likedPosts.contains(id) }
        var cs = comments[id] ?? []
        if mode == .full { cs = cs.map { var c = $0; c["viewerLiked"] = likedComments.contains(c["id"] as! String); return c } }
        // p1 은 서버 카운터가 신고로 숨겨진 댓글 1개를 더 세는 실제 상황을 흉내 낸다(목록 12 → 상세 11).
        // 앱은 상세를 본 뒤 목록 [N] 을 상세 기준으로 맞춰야 한다.
        p["comment_count"] = cs.count + (id == "p1" ? 1 : 0)
        let own = (p["author_id"] as? String) == me
        return try decode(["post": p, "comments": cs, "viewer": ["loggedIn": true, "isOwner": own, "canComment": true]])
    }

    func squad(_ id: String) throws -> Squad {
        let (name, fid): (String, String) = id == "epl" ? ("EPL 올스타", "433") : id == "laliga" ? ("라리가 올스타", "4231") : ("BVB 꿀벌 스쿼드", "4231")
        let names = ["GK": "코벨", "LB": "벤세바이니", "CB": "후멜스", "RB": "류에르손", "CDM": "잔", "CM": "벨링엄", "LAM": "로이스",
                     "CAM": "브란트", "RAM": "산초", "ST": "할란드", "LW": "아데예미", "RW": "말런"]
        let slots = Formation.get(fid).slots.map { ["slotId": $0.id, "spid": 101000001, "name": names[$0.pos] ?? $0.pos] as [String: Any] }
        return try decode(["id": id, "name": name, "formation": fid, "slots": slots])
    }

    func battle(_ postId: String) -> BattleVotes {
        let v = votes[postId] ?? (0, 0, nil)
        return BattleVotes(a: v.a, b: v.b, mine: mode == .full ? v.mine : nil)
    }
    func vote(_ postId: String, _ pick: String) -> BattleVotes {
        var v = votes[postId] ?? (0, 0, nil)
        if pick == "A" { v.a += 1 } else { v.b += 1 }
        v.mine = pick
        votes[postId] = v
        return BattleVotes(a: v.a, b: v.b, mine: mode == .full ? pick : nil)
    }

    func like(_ target: CommunityAPI.LikeTarget, _ id: String, on: Bool) throws -> LikeResponse {
        if mode == .hybrid { throw APIError.server(code: "not_found", message: "Not Found", status: 404, retryAfter: nil) }
        guard mode == .full else { throw APIError.server(code: "not_ready", message: "아직 준비 중인 기능이에요.", status: 503, retryAfter: nil) }
        func bump(_ arr: inout [[String: Any]]) -> Int? {
            guard let i = arr.firstIndex(where: { ($0["id"] as! String) == id }) else { return nil }
            let n = max(0, ((arr[i]["like_count"] as? Int) ?? 0) + (on ? 1 : -1))
            arr[i]["like_count"] = n
            return n
        }
        if target == .post {
            if on { likedPosts.insert(id) } else { likedPosts.remove(id) }
            return LikeResponse(ok: true, liked: on, likeCount: bump(&posts))
        }
        if on { likedComments.insert(id) } else { likedComments.remove(id) }
        for k in comments.keys { if let n = bump(&comments[k]!) { return LikeResponse(ok: true, liked: on, likeCount: n) } }
        return LikeResponse(ok: true, liked: on, likeCount: nil)
    }

    func addComment(postId: String, json: [String: Any]) -> String {
        seq += 1
        let id = "n\(seq)"
        var d: [String: Any] = ["id": id, "post_id": postId, "author_id": me, "body": json["body"] ?? "", "created_at": ago(0),
                                "author": ["id": me, "nickname": "개발자"], "isOwn": true]
        if let s = json["squad_id"] { d["squad_id"] = s }
        if mode == .full { d["like_count"] = 0; d["viewerLiked"] = false; if let p = json["parent_id"] { d["parent_id"] = p } }
        // 구 코드(legacy·hybrid)는 parent_id 를 버린다 — 실서버와 같게
        if mode == .hybrid { d["like_count"] = 0 }
        comments[postId, default: []].append(d)
        if let i = posts.firstIndex(where: { ($0["id"] as! String) == postId }) { posts[i]["comment_count"] = ((posts[i]["comment_count"] as? Int) ?? 0) + 1 }
        return id
    }
    func deleteComment(postId: String, commentId: String) {
        comments[postId]?.removeAll { ($0["id"] as! String) == commentId }
    }
    func deletePost(_ id: String) { posts.removeAll { ($0["id"] as! String) == id } }

    func createPost(_ json: [String: Any]) -> String {
        seq += 1
        let id = "new\(seq)"
        var p = post(id, json["type"] as? String ?? "squad_show", json["title"] as? String ?? "", nick: "개발자", min: 0, comments: 0, views: 0, likes: 0,
                     squad: json["squad_id"] as? String, body: json["body"] as? String ?? "",
                     meta: (json["attach"] as? [String: Any]).flatMap(Self.attachMeta) ?? [:], author: me)
        p["author_id"] = me
        posts.insert(p, at: 0)
        return id
    }

    /// 작성 요청의 attach → meta(서버 lib/community/attach.ts 와 같은 평평한 키)
    static func attachMeta(_ j: [String: Any]) -> [String: String]? {
        guard let k = (j["kind"] as? String).flatMap(PostAttach.Kind.init(rawValue:)), let me = j["me"] as? String else { return nil }
        return PostAttach(kind: k, me: me, with: j["with"] as? String, mode: j["mode"] as? Int ?? 50).metaEntries
    }

    func profile() throws -> ProfileResponse {
        try decode(["profile": ["id": me, "nickname": "개발자"], "posts": [], "squads": [
            ["id": "bvb1", "name": "BVB 꿀벌 스쿼드", "formation": "4231"],
            ["id": "epl", "name": "EPL 올스타", "formation": "433"],
        ], "snapshots": []])
    }

    func notifications() -> NotificationsResponse {
        NotificationsResponse(total: 3, items: [.init(postId: "p1", title: "도르트문트 팀컬러 4-2-3-1 평가 부탁드려요", count: 3)])
    }
}
#endif

#if DEBUG
import SwiftUI

/// 개발 전용 — 실행 인자로 커뮤니티 화면을 바로 연다(시뮬레이터 스크린샷 검수용).
/// `-communityMock full -communityScreen detail|battle|compose|comments -communityTab squad|club -communityChip tournament`
@MainActor
enum CommunityDebugLaunch {
    private static var done = false
    private static var arg: (String) -> String? = { UserDefaults.standard.string(forKey: $0) }

    /// 앱 시작 직후(AppDelegate) — 온보딩을 건너뛰고 커뮤니티 탭으로
    static func prepare() {
        guard arg("communityMock") != nil || arg("communityScreen") != nil else { return }
        LocalPrefs.shared.onboardingDone = true
        AppRouter.shared.tab = .community
        // `-openURL fcscope://user/…` — 캡처 검수용 딥링크(시스템 "열겠습니까?" 확인 창 없이)
        if let raw = arg("openURL"), let url = URL(string: raw) { AppRouter.shared.handle(url: url) }
    }

    static var scrollTarget: String? { arg("communityScroll") ?? (arg("communityScreen") == "comments" ? "comments" : nil) }

    static func runOnce(router: AppRouter, model: CommunityModel, compose: @escaping (String?) -> Void) {
        guard !done else { return }
        done = true
        if let t = arg("communityTab").flatMap(CommunityTab.init(rawValue:)) {
            model.tab = t
            model.chip = arg("communityChip")
        }
        switch arg("communityScreen") {
        case "detail", "comments": router.push(.post(arg("communityPost") ?? "p1"))
        case "battle": router.push(.post("p2"))
        case "compose": Task { try? await Task.sleep(for: .milliseconds(800)); compose(arg("communityChip") ?? "squad_rate") }
        default: break
        }
    }
}
#endif
