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

    /// 화면·카드에 실제로 띄우는 한 줄
    var liner: String {
        storyTag ?? FCCopy.matchLiner(result: me.result, myGoals: me.goals, oppGoals: opponent?.goals, forfeit: me.forfeit, server: verdict.oneLiner)
    }
}
