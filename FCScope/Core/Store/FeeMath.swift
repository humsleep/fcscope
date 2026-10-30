import Foundation

/// 이적시장 판매 수수료 — 의존성 없는 순수 함수(scripts/check-pure.sh 가 단독 확인).
///
/// ⚠️ 공식 근거는 "수수료 할인 쿠폰 30%"(fconline 공지 n4ArticleSN=5799)와 "무료 즉시 판매엔 할인 미적용"뿐이다.
/// 기본 40%·PC방 30%·TOP CLASS 20%, 할인 합산 방식, 내림은 커뮤니티 통설(2026-10-30 조사) — 화면에서 사용자가 고칠 수 있게 둔다.
struct FeeInput: Equatable {
    var price: Int64
    /// 기본 수수료율(%)
    var baseRate = 40
    /// 할인율(%) — 합산해서 100% 에서 멈춘다
    var discounts: [Int] = []
}

struct FeeResult: Equatable {
    let fee: Int64
    let net: Int64
    /// 적용된 실제 수수료율(%, 소수 1자리용 Double)
    let effectiveRate: Double
}

func transferFee(_ i: FeeInput) -> FeeResult {
    let price = max(0, i.price)
    let discount = min(100, max(0, i.discounts.reduce(0, +)))
    let rate = Double(min(100, max(0, i.baseRate))) * Double(100 - discount) / 100   // %
    // 정수 연산으로 내림 — 억 단위 BP 에서 Double 오차가 1 BP 씩 틀리지 않게
    let fee = price * Int64(min(100, max(0, i.baseRate))) * Int64(100 - discount) / 10_000
    return FeeResult(fee: fee, net: price - fee, effectiveRate: rate)
}
