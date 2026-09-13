import SwiftUI
import AuthenticationServices

struct MyPageView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var auth = AuthManager.shared
    @State private var prefs = LocalPrefs.shared
    @State private var profile: ProfileResponse?
    @State private var notif: NotificationsResponse?
    @State private var showLogin = false
    @State private var showSetup = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                accountCard
                if let s = profile?.snapshot { snapshotCard(s) }
                if let n = notif, n.total > 0 {
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel("💬 새 댓글 \(n.total)")
                            ForEach(n.items) { i in Button { router.push(.post(i.postId)) } label: { HStack { Text(i.title).fcFont(14).foregroundStyle(FC.ink).lineLimit(1); Spacer(); Text("+\(i.count)").fcScoreboard(13).foregroundStyle(FC.accent) } }.buttonStyle(.plain) }
                        }
                    }
                }
                myClubCard
                if !prefs.favorites.isEmpty { favoritesCard }
                if let sq = profile?.squads, !sq.isEmpty {
                    Panel(padding: 12) { VStack(alignment: .leading, spacing: 6) { SectionLabel("내 스쿼드"); ForEach(sq) { s in Button { router.push(.squad(s.id)) } label: { HStack { Text(s.name).foregroundStyle(FC.ink); Spacer(); Text(s.formation).fcScoreboard(12).foregroundStyle(FC.muted) }.padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) } } }
                }
                if let posts = profile?.posts, !posts.isEmpty {
                    Panel(padding: 12) { VStack(alignment: .leading, spacing: 6) { SectionLabel("내가 쓴 글"); ForEach(posts) { p in Button { router.push(.post(p.id)) } label: { HStack { Text(p.title).foregroundStyle(FC.ink).lineLimit(1); Spacer(); Image(systemName: "chevron.right").foregroundStyle(FC.muted) }.padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) } } }
                }
                if prefs.streak.current >= 2 { Text("🔥 \(prefs.streak.current)일 연속 방문 (최고 \(prefs.streak.best)일)").fcFont(13, weight: .semibold).foregroundStyle(FC.gold) }
                NavigationLink { SettingsView() } label: { Panel(padding: 12) { HStack { Label("설정 · 약관 · 계정", systemImage: "gearshape").foregroundStyle(FC.ink); Spacer(); Image(systemName: "chevron.right").foregroundStyle(FC.muted) } } }.buttonStyle(.plain)
            }.padding(16)
        }
        .fcScreen().navigationTitle("내 정보").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { LoginView(reason: nil) }
        .sheet(isPresented: $showSetup) { ProfileSetupView(current: profile?.profile) { Task { await load() } } }
        .task(id: auth.user?.id) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard auth.isLoggedIn else { profile = nil; notif = nil; return }
        profile = try? await APIClient.shared.get("/api/profile")
        notif = try? await APIClient.shared.get("/api/me/notifications", query: ["since": ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86_400))])
        await PushManager.shared.registerIfAuthorized()
    }

    private var accountCard: some View {
        Panel {
            if !auth.isLoggedIn {
                HStack { Text("로그인하면 연동 구단주·내 글·댓글 알림을 한 곳에서 볼 수 있어요.").fcFont(13).foregroundStyle(FC.muted); Spacer(); Button("로그인") { showLogin = true }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk) }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.profile?.nickname ?? "닉네임 미등록").fcFont(18, weight: .bold).foregroundStyle(FC.ink)
                        if let v = profile?.profile?.verifiedNickname { Text("✓ 구단주 \(v)").fcFont(13).foregroundStyle(FC.accent) } else { Text("구단주명 미연동").fcFont(13).foregroundStyle(FC.muted) }
                    }
                    Spacer()
                    Button(profile?.profile?.nickname == nil ? "닉네임 등록" : "프로필 설정") { showSetup = true }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func snapshotCard(_ s: ProfileResponse.Snapshot) -> some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("지난 방문 대비")
                HStack(spacing: 20) {
                    VStack(alignment: .leading) { Text("최근 \(s.played)경기 승률").font(.fcFont(12, typeSize)).foregroundStyle(FC.muted); (Text("\(s.winRate)%").foregroundStyle(FC.accent) + Text(s.deltaWinRate.map { $0 > 0 ? " ▲\($0)%p" : $0 < 0 ? " ▼\(-$0)%p" : " ±0" } ?? "").font(.fcScoreboard(13, typeSize)).foregroundStyle((s.deltaWinRate ?? 0) >= 0 ? FC.win : FC.lose)).font(.fcScoreboard(24, typeSize)) }
                    VStack(alignment: .leading) { Text("평균 평점").fcFont(12).foregroundStyle(FC.muted); Text(String(format: "%.2f", s.avgRating)).fcScoreboard(24).foregroundStyle(FC.gold) }
                }
                Text(s.prevDate.map { "\($0) 방문 대비" } ?? "내일 다시 방문하면 변화를 보여드려요.").fcFont(11).foregroundStyle(FC.muted)
            }
        }
    }

    private var myClubCard: some View {
        Panel(padding: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("내 구단 (기기)")
                    if let n = prefs.myNickname { Text(n).fcFont(16, weight: .bold).foregroundStyle(FC.ink) } else { Text("전적 페이지에서 '내 구단으로'를 누르면 홈·위젯에 고정돼요.").fcFont(13).foregroundStyle(FC.muted) }
                }
                Spacer()
                if let n = prefs.myNickname { Button("전적") { router.push(.user(n)) }.buttonStyle(.borderedProminent).tint(FC.accent).foregroundStyle(FC.accentInk) }
            }
        }
    }

    private var favoritesCard: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("⭐ 즐겨찾기 구단주")
                ForEach(prefs.favorites, id: \.self) { n in
                    HStack {
                        Button { router.push(.user(n)) } label: { Text(n).foregroundStyle(FC.ink) }.buttonStyle(.plain)
                        Spacer()
                        if let s = prefs.snapshot(for: n) { Text("\(s.winRate)%").fcScoreboard(12).foregroundStyle(FC.accent) }
                        Button { prefs.toggleFavorite(n) } label: { Image(systemName: "xmark").fcFont(11).foregroundStyle(FC.muted) }.accessibilityLabel("\(n) 즐겨찾기 해제")
                    }.padding(8).background(FC.surface2, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

struct LoginView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var reason: String?
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthManager.shared
    @State private var agreed = false
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                (Text("FC ").foregroundStyle(FC.accent) + Text("SCOPE").foregroundStyle(FC.ink)).font(.fcScoreboard(26, typeSize))
                if let r = reason { Text(r).fcFont(14, weight: .semibold).foregroundStyle(FC.accent) }
                Text("클럽 모집·커뮤니티 참여에는 로그인이 필요해요. 전적 검색·진단·스쿼드는 로그인 없이 쓸 수 있어요.").fcFont(13).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                if !auth.isConfigured {
                    Text("로그인 준비 중이에요.").fcFont(13).foregroundStyle(FC.muted)
                } else {
                    // 스위치는 탭이 잘 먹지 않았다(드래그로만 켜짐). 동의는 설정이 아니라 행위이므로
                    // 체크박스가 의미상으로도 맞고, 줄 전체가 탭 영역이라 훨씬 누르기 쉽다.
                    Button {
                        agreed.toggle()
                        Haptic.light()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(agreed ? FC.accent : FC.muted)
                            (Text("이용약관").underline() + Text("과 ") + Text("개인정보처리방침").underline() + Text("에 동의하며, 만 14세 이상입니다."))
                                .font(.fcFont(13, typeSize)).foregroundStyle(FC.muted)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())   // 글자 사이 빈 곳도 탭 영역
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("이용약관 및 개인정보처리방침 동의")
                    .accessibilityAddTraits(agreed ? [.isSelected] : [])
                    HStack(spacing: 12) { Link("이용약관", destination: AppConfig.termsURL); Link("개인정보처리방침", destination: AppConfig.privacyURL) }.fcFont(12)
                    SignInWithAppleButton(.continue) { req in auth.prepareAppleRequest(req) } onCompletion: { result in
                        guard agreed else { error = "약관에 동의해 주세요."; return }
                        Task { do { try await auth.completeApple(result); dismiss() } catch { if !"\(error)".contains("1001") { self.error = error.localizedDescription } } }
                    }
                    .signInWithAppleButtonStyle(.white).frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                    Button { guard agreed else { error = "약관에 동의해 주세요."; return }; busy = true; Task { do { try await auth.signInWithGoogle(); dismiss() } catch { self.error = error.localizedDescription }; busy = false } } label: {
                        HStack { Image(systemName: "g.circle.fill"); Text(busy ? "이동 중…" : "Google로 계속하기") }.frame(maxWidth: .infinity).frame(height: 48)
                    }.buttonStyle(.bordered).disabled(busy)
                }
                if let e = error { Text(e).fcFont(13).foregroundStyle(FC.lose) }
                Text("로그인 시 서비스 이용에 필요한 최소 정보(이메일·프로필)만 사용합니다.").fcFont(12).foregroundStyle(FC.muted).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(24).background(FC.bg.ignoresSafeArea())
            .navigationTitle("로그인").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

struct ProfileSetupView: View {
    var current: ProfileResponse.MyProfile?
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var fc = ""
    @State private var msg: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("커뮤니티 닉네임 (2~16자)") {
                    TextField("닉네임", text: $nickname)
                    Button(busy ? "저장 중…" : "닉네임 저장") { Task { await saveNick() } }.disabled(busy || nickname.trimmingCharacters(in: .whitespaces).count < 2)
                }
                Section("FC온라인 구단주명 연동 (선택)") {
                    TextField("구단주명", text: $fc)
                    Button("연동") { Task { await verify() } }.disabled(busy || fc.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("연동은 구단주명이 게임에 존재함을 확인하는 기능이며, 계정 소유를 증명하지 않아요.").fcFont(12).foregroundStyle(FC.muted)
                }
                if let m = msg { Text(m).fcFont(13).foregroundStyle(FC.accent) }
            }
            .navigationTitle("프로필 설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { onDone(); dismiss() } } }
            .onAppear { nickname = current?.nickname ?? ""; fc = current?.verifiedNickname ?? "" }
        }
    }
    private func saveNick() async {
        busy = true; defer { busy = false }
        do { let _: OkBody = try await APIClient.shared.send("/api/profile", method: "POST", json: ["nickname": nickname.trimmingCharacters(in: .whitespaces)]); msg = "닉네임을 저장했어요."; Haptic.success() } catch { msg = error.localizedDescription }
    }
    private func verify() async {
        busy = true; defer { busy = false }
        do { let _: OkBody = try await APIClient.shared.send("/api/profile/verify", method: "POST", json: ["nickname": fc.trimmingCharacters(in: .whitespaces)]); msg = "구단주명을 연동했어요."; LocalPrefs.shared.myNickname = fc.trimmingCharacters(in: .whitespaces); Haptic.success() } catch { msg = error.localizedDescription }
    }
}

struct SettingsView: View {
    @State private var auth = AuthManager.shared
    @State private var prefs = LocalPrefs.shared
    @State private var confirmDelete = false
    @State private var confirmDelete2 = false
    @State private var msg: String?
    @State private var baseURL = AppConfig.baseURL.absoluteString
    @State private var cacheBytes = 0
    private var cacheSizeLabel: String {
        cacheBytes < 1024 ? "0KB" : ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)
    }
    private func refreshCacheSize() async { cacheBytes = await ResponseCache.shared.sizeBytes() }
    var body: some View {
        Form {
            Section("내 구단") {
                TextField("구단주명", text: Binding(get: { prefs.myNickname ?? "" }, set: { prefs.myNickname = $0.isEmpty ? nil : $0 }))
            }
            Section("차단한 사용자") {
                if prefs.blockedUsers.isEmpty { Text("없음").foregroundStyle(FC.muted) }
                else { Button("차단 \(prefs.blockedUsers.count)명 전체 해제") { prefs.blockedUsers = [] } }
            }
            Section("알림") {
                Button("주간 성적표·메타 요약 알림 켜기") { Task { await PushManager.shared.requestPermission() } }
                Text("일요일 밤 주간 리캡, 금요일 메타 한 줄, 내 글 새 댓글만 보내요.").fcFont(12).foregroundStyle(FC.muted)
            }
            Section("약관 · 문의") {
                Link("이용약관", destination: AppConfig.termsURL)
                Link("개인정보처리방침", destination: AppConfig.privacyURL)
                Link("문의 \(AppConfig.contactEmail)", destination: URL(string: "mailto:\(AppConfig.contactEmail)")!)
            }
            if auth.isLoggedIn {
                Section("계정") {
                    Button("로그아웃") { Task { await auth.signOut() } }
                    Button("계정 삭제", role: .destructive) { confirmDelete = true }
                    Text("닉네임·구단주 연동·내 글·댓글·전적 스냅샷이 즉시 삭제되며 되돌릴 수 없어요.").fcFont(12).foregroundStyle(FC.muted)
                }
            }
            Section("저장 공간") {
                LabeledContent("선수 데이터", value: PlayerIndex.shared.isReady ? "\(PlayerIndex.shared.count)명 · \(PlayerIndex.shared.date)" : "미탑재")
                Button("전적 캐시 비우기 (\(cacheSizeLabel))") {
                    Task { await ResponseCache.shared.clear(); await refreshCacheSize() }
                }
                Text("전적·픽 랭킹 응답을 기기에 저장해 재방문 시 즉시 표시하고 서버 조회를 줄여요.")
                    .fcFont(12).foregroundStyle(FC.muted)
            }
            #if DEBUG
            Section("개발 — 카드 렌더 검증") {
                ShareCardButton(spec: ShareCardSpec(
                    kicker: "전적 카드",
                    title: "62%",
                    subtitle: "샘플구단주 · Lv.120 · 챔피언스",
                    stamp: CardStamp(text: "18승 4무 8패", color: CardPalette.lime),
                    badges: [
                        CardBadge(label: "FC 스코어", value: "6.8", color: CardPalette.gold),
                        CardBadge(label: "최근 경기", value: "30"),
                        CardBadge(label: "득실", value: "54:41"),
                    ],
                    filename: "fcscope-sample"
                ), label: "샘플 전적 카드")
                ShareCardButton(squad: SquadCardData(
                    name: "샘플 스쿼드",
                    formationId: "433",
                    slots: [
                        "st1": SquadSlotModel(slotId: "st1", spid: 866200104, name: "손흥민", season: "26 TOTS", x: nil, y: nil),
                        "cm2": SquadSlotModel(slotId: "cm2", spid: 100000041, name: "이니에스타", season: "아이콘", x: nil, y: nil),
                    ],
                    shareCode: "sample"
                ), label: "샘플 스쿼드 카드")
            }
            Section("개발") {
                TextField("백엔드 URL", text: $baseURL).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("적용") { UserDefaults.standard.set(baseURL, forKey: "fcscope.baseURL") }
                Button("온보딩 다시 보기") { prefs.onboardingDone = false }
            }
            #endif
            Section { Text("FC Scope iOS v\(AppConfig.appVersion)\nFC Scope은 비공식 팬 서비스입니다. Data based on NEXON Open API. 게임 데이터의 저작권은 NEXON·EA에 있습니다.").fcFont(12).foregroundStyle(FC.muted) }
        }
        .navigationTitle("설정")
        .task { await refreshCacheSize() }
        .alert("계정을 삭제할까요?", isPresented: $confirmDelete) { Button("계속", role: .destructive) { confirmDelete2 = true }; Button("취소", role: .cancel) {} } message: { Text("닉네임·구단주 연동·내가 쓴 글과 댓글·전적 스냅샷이 모두 삭제되며 되돌릴 수 없어요.") }
        .alert("정말 삭제할까요?", isPresented: $confirmDelete2) { Button("삭제", role: .destructive) { Task { do { try await auth.deleteAccount(); msg = "계정이 삭제됐어요. 그동안 이용해 주셔서 감사합니다." } catch { msg = error.localizedDescription } } }; Button("취소", role: .cancel) {} }
        .alert("알림", isPresented: Binding(get: { msg != nil }, set: { _ in msg = nil })) { Button("확인") {} } message: { Text(msg ?? "") }
    }
}
