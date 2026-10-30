#!/bin/bash
# 순수 함수(친구 리그 순위 LeagueRanking.swift · 수수료 FeeMath.swift) 단독 확인 — 테스트 타깃이 없어 swiftc 로 직접 돌린다.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
cat > "$tmp/main.swift" <<'SWIFT'
let me = LeagueEntry(nick: "나", isMe: true, games: 10, win: 5, draw: 0, lose: 5, winRate: 50)
let a = LeagueEntry(nick: "A", isMe: false, games: 10, win: 6, draw: 0, lose: 4, winRate: 60)
let b = LeagueEntry(nick: "B", isMe: false, games: 1, win: 1, draw: 0, lose: 0, winRate: 100)   // 3경기 미만 → 아래
let c = LeagueEntry(nick: "C", isMe: false, games: 20, win: 10, draw: 0, lose: 10, winRate: 50) // 승률 같으면 승 수
let none = LeagueEntry(nick: "D", isMe: false)
let r = rankLeague([b, none, me, c, a])
assert(r.map(\.nick) == ["A", "C", "나", "B", "D"] || r.map(\.nick) == ["A", "C", "나", "D", "B"], "\(r.map(\.nick))")
assert(r.firstIndex { $0.nick == "B" }! > 2, "3경기 미만은 순위 밖")
assert(leagueAboveMe(r)!.map(\.nick) == ["A", "C"])
var low = me; low.games = 2
assert(leagueAboveMe(rankLeague([a, low])) == nil, "내가 순위 밖이면 nil")
print("league ok")
// 수수료: 1억 · 40% · 할인 없음 → 4천만
assert(transferFee(FeeInput(price: 100_000_000)) == FeeResult(fee: 40_000_000, net: 60_000_000, effectiveRate: 40))
// PC방 30 + 쿠폰 30 = 60% 할인 → 수수료율 16%
let f = transferFee(FeeInput(price: 1_000_000_000_000, discounts: [30, 30]))
assert(f.fee == 160_000_000_000 && f.effectiveRate == 16, "\(f)")
// 할인 합이 100 넘으면 0원, 음수 가격은 0
assert(transferFee(FeeInput(price: 999, discounts: [100, 30])).fee == 0)
assert(transferFee(FeeInput(price: -5)).net == 0)
// 내림: 7 BP × 40% = 2.8 → 2
assert(transferFee(FeeInput(price: 7)).fee == 2)
print("fee ok")
SWIFT
swiftc -Onone FCScope/Core/Store/LeagueRanking.swift FCScope/Core/Store/FeeMath.swift "$tmp/main.swift" -o "$tmp/check" && "$tmp/check"
