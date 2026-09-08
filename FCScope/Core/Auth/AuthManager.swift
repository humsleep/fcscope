import Foundation
import Supabase
import AuthenticationServices
import CryptoKit
import Observation

/// Supabase 인증 — Apple(네이티브 시트 → signInWithIdToken), Google(PKCE, ASWebAuthenticationSession).
/// 세션은 SDK 가 Keychain 에 보관·자동 갱신. API 호출은 accessToken() 을 Bearer 로 싣는다.
@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()

    private(set) var user: User?
    private(set) var loading = true
    let client: SupabaseClient?
    private var currentNonce: String?

    private init() {
        // 값이 하나라도 비면 로그인 없이 동작(전적·스쿼드·픽 랭킹은 비로그인 기능).
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
        Task { await bootstrap() }
    }

    var isConfigured: Bool { client != nil }
    var isLoggedIn: Bool { user != nil }

    private func bootstrap() async {
        defer { loading = false }
        guard let client else { return }
        if let session = try? await client.auth.session { user = session.user }
        Task.detached { [weak self] in
            guard let client = await self?.client else { return }
            for await (event, session) in client.auth.authStateChanges {
                await MainActor.run { self?.handle(event: event, session: session) }
            }
        }
    }

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .signedIn, .tokenRefreshed, .initialSession, .userUpdated: user = session?.user
        case .signedOut, .userDeleted: user = nil
        default: break
        }
    }

    nonisolated func accessToken() async -> String? {
        guard let client = await client else { return nil }
        return try? await client.auth.session.accessToken
    }

    // MARK: Apple
    /// ASAuthorizationAppleIDRequest 에 넣을 해시 nonce. 원본은 Supabase 검증용으로 보관.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) async throws {
        guard let client else { throw AuthError.notConfigured }
        let auth = try result.get()
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else { throw AuthError.appleFailed }
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
        Haptic.success()
    }

    // MARK: Google (시스템 인증 세션 → fcscope://auth/callback)
    func signInWithGoogle() async throws {
        guard let client else { throw AuthError.notConfigured }
        try await client.auth.signInWithOAuth(provider: .google, redirectTo: AppConfig.oauthCallback)
        Haptic.success()
    }

    /// 앱이 fcscope://auth/callback?code=… 로 열렸을 때 (Google PKCE 복귀)
    func handleOpenURL(_ url: URL) async -> Bool {
        guard url.scheme == "fcscope", url.host == "auth", let client else { return false }
        do { try await client.auth.session(from: url); return true } catch { return false }
    }

    func signOut() async {
        try? await client?.auth.signOut()
        user = nil
    }

    /// App Store 5.1.1(v) — 서버에서 auth.users 삭제(cascade) 후 로컬 세션 정리
    func deleteAccount() async throws {
        let _: OkBody = try await APIClient.shared.send("/api/me/delete", method: "DELETE")
        try? await client?.auth.signOut()
        user = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    enum AuthError: LocalizedError {
        case notConfigured, appleFailed
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "로그인 준비 중이에요. 전적 검색·스쿼드·픽 랭킹은 로그인 없이 쓸 수 있어요."
            case .appleFailed: return "Apple 로그인에 실패했어요."
            }
        }
    }
}
