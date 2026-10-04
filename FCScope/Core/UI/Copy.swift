import Foundation

/// 화면 문구 톤 — 10~20대 기준(docs/store-v2/UX-AUDIT-GENZ.md §8, USER-PANEL-GENZ.md).
///
/// 원칙: 본문은 '~해요'. **결과 한 줄 코멘트**(경기 판정·티어)만 가볍게 밈을 허용한다.
/// 선생님 말투("분발 필요")·공지사항체("처음이신가요?")·경기 내용과 따로 노는 문구("4:4 무난한 경기")는 쓰지 않는다.
///
/// 서버 문구는 웹도 같이 쓰고 `/api/v1` 계약 대상이라 서버에서 바꾸지 않는다 — 앱이 표시 직전에 바꿔 읽는다.
/// 모르는 문구는 그대로 둔다(서버가 새 문구를 추가해도 깨지지 않게).
enum FCCopy {
    /// 서버 FC Scope 스코어 티어 라벨(lib/nexon/score.ts scoreTier) → 표시 문구
    static func tier(_ label: String) -> String {
        switch label {
        case "분발 필요": return "반등 준비 중"
        case "평범": return "딱 평균"
        default: return label
        }
    }

    /// 경기 한 줄 코멘트. 서버 oneLiner 는 **내 평점만** 보고 정해져서 4:4 난타전에도 "무난한 경기"가 붙었다.
    /// 결과·스코어를 먼저 보고, 해당 없으면 서버 문구를 결과에 맞춰 다시 쓴다.
    static func matchLiner(result: String, myGoals: Int, oppGoals: Int?, forfeit: Bool, server: String) -> String {
        if forfeit { return result == "승" ? "상대가 먼저 나갔어요" : result == "패" ? "중간에 끊긴 경기예요" : server }
        if result == "무", let o = oppGoals {
            if myGoals + o >= 6 { return "\(myGoals):\(o) 난타전 무승부" }
            if myGoals == 0 && o == 0 { return "0:0, 서로 골문 꽁꽁 잠근 판" }
            if myGoals + o >= 4 { return "\(myGoals):\(o) 치고받은 무승부" }
            return "팽팽하게 비긴 판"
        }
        let won = result == "승"
        switch server {
        case "완벽한 경기력": return won ? "경기력까지 완벽했어요 🔥" : "경기력은 완벽했는데 아쉽…"
        case "안정적인 경기": return won ? "안정감 있게 챙긴 승리" : "내용은 괜찮았던 판"
        case "무난한 경기": return won ? "깔끔하게 챙긴 승리" : "한 끗이 모자랐어요"
        case "고전한 경기": return won ? "꾸역꾸역 이겨냈어요" : "오늘은 좀 꼬였던 판"
        case "기록 집계 안 됨": return "기록이 아직 안 잡혔어요"
        default: return server
        }
    }

    /// 서버 폼 라벨(lib/nexon/streak-card.ts streakLabel) → 표시 문구. nil 이면 싣지 않는다.
    ///
    /// 서버는 연승·연패·모멘텀이 없으면 승률과 상관없이 "안정적인 폼"을 준다 — 승률 30% 화면에 "반등 준비 중",
    /// 같은 사람 카드에 "안정적인 폼"이 함께 떠 모순으로 읽혔다(유저 패널 B·C). 승률이 반 아래면 싣지 않는다.
    static func streak(_ s: StreakInfo, winRate: Int) -> String? {
        if s.color == "lose" { return nil }
        if s.text == "안정적인 폼" { return winRate >= 50 ? "꾸준한 폼" : nil }
        return s.text
    }

    /// 스쿼드 클리닉 band 코드(lib/squad-clinic.ts BAND_LABEL) → 표시 문구. 모르는 코드는 그대로.
    static func squadBand(_ band: String) -> String {
        ["top": "최상위 스쿼드 👑", "strong": "상위권 스쿼드", "balanced": "안정권 스쿼드",
         "building": "성장 중인 스쿼드 🌱", "rebuild": "손볼 곳 있는 스쿼드"][band] ?? band
    }
}

extension MatchDetailResponse {
    /// 스탯에서 뽑는 한 줄 스토리(매치 리포트·매치 카드 공용). 조건에 안 맞으면 nil → `FCCopy.matchLiner`.
    /// 슛 4 대 17로 밀리고 이긴 경기는 "효율 승리"다 — 평점만 보는 서버 문구로는 이게 안 나온다.
    var storyTag: String? {
        guard let o = opponent, !me.forfeit else { return nil }
        let won = me.result == "승", lost = me.result == "패"
        let margin = me.goals - o.goals
        if won {
            if let p = potm, p.positionLabel == "GK", p.side == me.nickname { return "GK \(p.name) 선방쇼로 지킨 승리" }
            if me.stats.shots > 0, me.stats.shots * 2 <= o.stats.shots { return "슛 \(me.stats.shots)개로 \(me.goals)골, 효율 승리" }
            if margin >= 3 { return "\(margin)골 차 대승" }
            if me.possession <= 45 { return "점유 \(me.possession)%로 따낸 역습승" }
            if o.goals == 0 { return "무실점 승리" }
            if margin == 1 { return "1골 차 접전 승리" }
        } else if lost {
            if margin == -1 { return "1골 차, 아깝다" }
            if me.stats.shots > o.stats.shots { return "슛 \(me.stats.shots) 대 \(o.stats.shots), 내용은 이겼다" }
        } else {
            if me.goals + o.goals >= 6 { return "\(me.goals):\(o.goals) 난타전 무승부" }
        }
        return nil
    }

    /// 진 경기의 "왜 졌는지" — 이 경기 데이터에서 **증명할 수 있는 문장만**, 최대 2줄.
    /// 위로 문구("꼬였던 판")만 있어 진 날엔 앱을 안 연다는 지적(유저 패널 2R A).
    ///
    /// 원칙(QA 3R P1-1·P2-3 — "83분 실점 — 막판 한 골에 갈렸어요"가 사실이 아니었다):
    /// - 숫자는 넥슨 집계(stats)나 슛 기록(shots)에서 그대로 온 것만 쓴다.
    /// - 슛 기록을 쓰는 문장은 **기록이 스코어·집계와 맞을 때만** 낸다(기록 슛 수 = 집계 슛 수, 기록 골 = 스코어).
    ///   자책골은 득점한 쪽의 슛 기록에 없어서 "유효슛 5개로 5골"이 실제로는 슛 4골 + 자책골 1이었다.
    /// - 결승골 문장은 골 기록으로 스코어 흐름을 다시 세워, **동점에서 들어가 끝까지 유지된 골**일 때만 낸다.
    ///   (같은 분에 양 팀 골이 있으면 순서를 알 수 없어 내지 않는다.)
    /// - 몰수·상대 없음·이기거나 비긴 경기는 빈 배열 — 화면은 블록을 숨긴다.
    var lossReasons: [String] {
        guard me.result == "패", !me.forfeit, let o = opponent, me.goals < o.goals else { return [] }
        let ms = me.stats, os = o.stats
        let myLogGoals = me.shots.filter(\.isGoal).count, oppLogGoals = o.shots.filter(\.isGoal).count
        let myLogOK = me.shots.count == ms.shots && myLogGoals == me.goals
        let oppLogOK = o.shots.count == os.shots && oppLogGoals == o.goals
        var out: [String] = []
        // 1) 슛 자체가 적다(집계)
        if ms.shots <= 4, ms.shots < os.shots {
            out.append("슛 \(ms.shots)개로는 어려웠어요 — 상대는 \(os.shots)개")
        }
        // 2) 쐈지만 골문으로 안 갔다(집계)
        if ms.shots >= 6, ms.effectiveShots <= ms.shots, ms.effectiveShots * 3 <= ms.shots {
            out.append("슛 \(ms.shots)개 중 유효슛 \(ms.effectiveShots)개 — 골문으로 간 슛이 적었어요")
        }
        // 3) 박스 밖에서 많이 쐈다(슛 기록 — 기록이 집계와 맞고 모든 슛에 위치가 있을 때)
        if myLogOK, ms.shots >= 5, me.shots.allSatisfy({ $0.inPenalty != nil }) {
            let box = me.shots.filter { $0.inPenalty == true }.count
            if box * 2 < me.shots.count { out.append("슛 \(me.shots.count)개 중 박스 안 \(box)개 — 먼 거리 슛이 많았어요") }
        }
        // 4) 골문으로 갔는데 안 들어갔다 — 내 골이 전부 내 슛에서 나왔을 때만(상대 자책골이 섞이면 "유효슛 N개에 G골"이 틀린다)
        if myLogOK, ms.effectiveShots >= 5, me.goals <= ms.effectiveShots, me.goals * 4 <= ms.effectiveShots {
            out.append("유효슛 \(ms.effectiveShots)개에 \(me.goals)골 — 마무리가 아쉬웠어요")
        }
        // 5) 상대 마무리 — 상대 골이 전부 상대 슛에서 나왔을 때만
        if oppLogOK, o.goals >= 2, o.goals <= os.effectiveShots, o.goals * 2 >= os.effectiveShots {
            out.append("상대는 유효슛 \(os.effectiveShots)개로 \(o.goals)골 — 상대 마무리가 날카로웠어요")
        }
        // 5b) 상대 슛 기록에 없는 실점(자책골 등) — 기록 슛 수는 집계와 맞는데 골만 모자랄 때
        if o.shots.count == os.shots, oppLogGoals < o.goals {
            let n = o.goals - oppLogGoals
            out.append("\(o.goals)실점 중 \(n)골은 상대 슛이 아닌 골(자책골 등)이었어요")
        }
        // 6) 공을 못 잡았다(집계)
        if me.possession <= 40 {
            out.append("점유 \(me.possession)% — 공을 오래 못 잡았어요")
        }
        // 7) 동점에서 내준 늦은 결승골
        if let w = decidingGoal, w.minute >= 80 {
            out.append("\(w.tie):\(w.tie) 동점이던 \(w.minute)분, 결승골을 내줬어요")
        }
        return Array(out.prefix(2))
    }

    /// 한 골 차 패배에서 **동점을 깬 마지막 상대 골**(= 결승골)과 그 직전 동점 스코어.
    /// 양 팀 슛 기록이 스코어와 맞고 모든 골에 분이 있을 때만 계산한다. 상대의 (내 최종 득점 + 1)번째 골 직전에
    /// 내 골이 전부 들어가 있어야(그 뒤로 내 골이 없어야) 동점 → 리드 → 종료가 성립한다.
    /// 같은 분에 양 팀 골이 있으면 순서를 알 수 없어 nil. 분은 넥슨 기록 그대로(추가시간·연장은 90 이상).
    var decidingGoal: (minute: Int, tie: Int)? {
        guard let o = opponent, o.goals - me.goals == 1, !me.forfeit else { return nil }
        let mine = me.shots.filter(\.isGoal), theirs = o.shots.filter(\.isGoal)
        guard mine.count == me.goals, theirs.count == o.goals,
              me.shots.count == me.stats.shots, o.shots.count == o.stats.shots else { return nil }
        let myMins = mine.compactMap(\.minute), oppMins = theirs.compactMap(\.minute).sorted()
        guard myMins.count == mine.count, oppMins.count == theirs.count else { return nil }
        let k = me.goals                      // 0부터 — 상대의 (k+1)번째 골
        let g = oppMins[k]
        // 같은 분 골이 있으면 순서를 모른다
        if myMins.contains(g) { return nil }
        if k > 0, oppMins[k - 1] == g { return nil }
        // 그 골 전에 내 골이 전부 들어가 있어야 직전 스코어가 k:k 동점이고, 이후 내 골이 없어 끝까지 유지된다
        guard myMins.allSatisfy({ $0 < g }) else { return nil }
        return (g, k)
    }

    /// 화면·카드에 실제로 띄우는 한 줄
    var liner: String {
        storyTag ?? FCCopy.matchLiner(result: me.result, myGoals: me.goals, oppGoals: opponent?.goals, forfeit: me.forfeit, server: verdict.oneLiner)
    }

    /// 바로 옆에 이미 큰 결과 라벨·스코어가 있을 때 — **맨 앞에 붙은** 같은 말(스코어 "3:3", 결과 낱말)만 뺀다.
    /// "3:3 난타전 무승부" → "난타전 무승부", "0:0, 서로 골문…" → "서로 골문…".
    ///
    /// 낱말(띄어쓰기 단위)로만 비교한다. 예전에는 `replacingOccurrences`로 글자를 지워서 "승"이
    /// "대승"·"역습승"·"챙긴 승리" 안에서까지 빠졌다("승리 · 3골 차 대" — QA 2R P1-1).
    /// 다 빼면 아무것도 안 남으면 원문 그대로.
    func liner(after shown: [String]) -> String {
        let full = liner
        let score = opponent.map { "\(me.goals):\($0.goals)" }
        let drop = Set(shown.filter { !$0.isEmpty } + [score].compactMap { $0 })
        var words = full.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let first = words.first, drop.contains(first.trimmingCharacters(in: CharacterSet(charactersIn: ",·"))) {
            words.removeFirst()
        }
        let t = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,·"))
        return t.isEmpty ? full : t
    }

    /// 매치 히어로 결과 줄. 한 줄 코멘트가 이미 결과 낱말("…챙긴 승리", "난타전 무승부")을 품고 있으면
    /// 앞에 "승리 · "를 또 붙이지 않는다. 아니면 "승리 · 3골 차 대승"처럼 결과를 앞에 둔다.
    func heroLine(resultWord: String) -> String {
        let rest = liner(after: [resultWord])
        let hasResult = rest.split(separator: " ").contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",·")) == resultWord }
        return hasResult ? rest : "\(resultWord) · \(rest)"
    }
}

/// 한국어 조사 — 받침에 따라 "을/를". "세루 기라시을(를)"처럼 괄호 조사가 그대로 보였다(QA P2-9).
enum Josa {
    /// 마지막 글자가 한글이면 받침으로 고르고, 아니면(영문·숫자) "을(를)"을 그대로 쓴다.
    static func eulReul(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "\(word)을(를)" }
        return (last.value - 0xAC00) % 28 == 0 ? "\(word)를" : "\(word)을"
    }
}
