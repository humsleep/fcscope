import SwiftUI
import UserNotifications

/// 친구 리그 — 내 구단 + 즐겨찾기의 최근 7일 공식경기 순위. 캐시로 먼저 그리고 새로 받아 바꾼다.
struct LeagueView: View {
    @Environment(AppRouter.self) private var router
    @State private var rows: [LeagueEntry] = []
    @State private var loading = false
    @State private var notifStatus: UNAuthorizationStatus = .authorized   // 확인 전엔 카드를 숨긴다
    @AppStorage("fcscope.league.alertCardDismissed") private var alertCardDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    private var notifOn: Bool { [.authorized, .provisional, .ephemeral].contains(notifStatus) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("친구 리그", color: FC.tint)
                Text("나와 즐겨찾기 구단주의 최근 7일 공식경기 승률 순위예요. \(LeagueEntry.minGames)경기 이상 뛴 구단주만 순위에 들어가요.")
                    .fcFont(13).foregroundStyle(FC.muted)
                if FriendLeague.members.count < 2 {
                    emptyState
                } else {
                    if !notifOn, !alertCardDismissed, LocalPrefs.shared.myNickname != nil { alertCard }
                    Panel(padding: 8) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Rectangle().fill(FC.line).frame(height: 1).padding(.leading, 44) }
                                row(r, rank: r.qualified ? i + 1 : nil)
                            }
                        }
                    }
                    if loading { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("최신 기록 받는 중…").fcFont(12).foregroundStyle(FC.muted) } }
                    Text("친구를 더 넣으려면 전적 화면에서 ☆를 누르세요(최대 12명). 순위가 바뀌어 누가 나를 앞지르면 알림으로 알려 드려요.")
                        .fcFont(11).foregroundStyle(FC.muted)
                }
            }
            .padding(16)
        }
        .fcScreen().navigationTitle("친구 리그").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if FriendLeague.members.count >= 2, rows.contains(where: \.qualified) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("순위 공유")
                }
            }
        }
        .task {
            rows = await FriendLeague.cachedRows()
            await refresh()
        }
        .refreshable { await refresh() }
        .task { await refreshNotifStatus() }
        // iOS 설정에서 켜고 돌아오면 카드를 거둔다
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await refreshNotifStatus() } } }
    }

    private func refreshNotifStatus() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 추월 알림은 권한이 있어야 온다. 미결정이면 시스템 팝업, 이미 거절했으면 iOS 설정으로(팝업이 다시 뜨지 않는다).
    private var alertCard: some View {
        Panel(padding: 12, highlight: FC.tint.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("🔔 추월 알림 받기").fcFont(15, weight: .bold).foregroundStyle(FC.ink)
                Text("친구가 최근 7일 승률로 나를 앞지르면 바로 알려 드려요. 주간 성적표도 같이 받아요.")
                    .fcFont(13).foregroundStyle(FC.muted)
                HStack(spacing: 8) {
                    Button(notifStatus == .notDetermined ? "알림 켜기" : "설정에서 켜기") {
                        Task {
                            if notifStatus == .notDetermined {
                                await PushManager.shared.requestPermission()
                                await refreshNotifStatus()
                            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                    .buttonStyle(BrandButtonStyle(compact: true))
                    Button("괜찮아요") { alertCardDismissed = true }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func refresh() async {
        guard FriendLeague.members.count >= 2, !loading else { return }
        loading = true
        rows = await FriendLeague.refreshedRows()
        loading = false
        // 지금 본 순위가 다음 추월 알림의 기준 — 이미 본 변화는 다시 알리지 않는다.
        FriendLeague.noteStandings(rows)
    }

    private func row(_ r: LeagueEntry, rank: Int?) -> some View {
        Button { router.push(.user(r.nick)) } label: {
            HStack(spacing: 10) {
                Text(rank.map(String.init) ?? "–").fcScoreboard(15)
                    .foregroundStyle(rank.map { $0 <= 3 ? FC.gold : FC.muted } ?? FC.muted).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(r.nick).fcFont(15, weight: .semibold).foregroundStyle(FC.ink).lineLimit(1)
                        if r.isMe { Chip(text: "나", color: FC.tint, bg: FC.tint.opacity(0.15)) }
                    }
                    Text(r.games == 0 ? "최근 7일 기록 없음"
                         : r.qualified ? "\(r.win)승 \(r.draw)무 \(r.lose)패 · \(r.games)경기"
                         : "\(r.games)경기 · \(LeagueEntry.minGames)경기부터 순위")
                        .fcFont(12).foregroundStyle(FC.muted)
                }
                Spacer()
                if r.qualified {
                    Text("\(r.winRate)%").fcScoreboard(17).foregroundStyle(r.winRate >= 50 ? FC.win : FC.lose)
                }
            }
            .padding(.horizontal, 8).frame(minHeight: 56).contentShape(Rectangle())
            .background(r.isMe ? FC.tint.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("🏆 친구를 데려오면 리그가 열려요").fcFont(17, weight: .bold).foregroundStyle(FC.ink)
                Text("친구의 전적을 검색하고 ☆(즐겨찾기)를 누르면 이 순위표에 들어와요. 내 구단도 정해 두면 내 순위와 추월 알림을 볼 수 있어요.")
                    .fcFont(13).foregroundStyle(FC.muted)
                Button { router.tab = .home } label: { Text("친구 전적 검색하기").frame(maxWidth: .infinity) }
                    .buttonStyle(BrandButtonStyle(fullWidth: true, compact: true))
            }
        }
    }

    private var shareText: String {
        let lines = rows.filter(\.qualified).prefix(10).enumerated().map { i, r in
            "\(i + 1)위 \(r.nick) \(r.winRate)% (\(r.win)승 \(r.draw)무 \(r.lose)패)"
        }
        return (["🏆 FC Scope 친구 리그 · 최근 7일"] + lines + ["", "https://www.fcscope.xyz"]).joined(separator: "\n")
    }
}
