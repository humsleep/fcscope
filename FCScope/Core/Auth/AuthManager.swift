import Foundation
import UIKit
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
            #if DEBUG
            client = SupabaseClient(supabaseURL: url, supabaseKey: key, options: .init(global: .init(logger: SupabaseDebugLogger())))
            #else
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
            #endif
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
        // 메인 액터를 물려받는 Task 로 구독한다 — detached + MainActor.run 은 캡처한 self 를
        // 동시 실행 코드에서 참조해 Swift 6 에서 에러가 된다. 싱글턴이라 강한 참조여도 누수 없음.
        Task {
            for await (event, session) in client.auth.authStateChanges {
                handle(event: event, session: session)
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
        guard let client else { return nil }   // let 프로퍼티라 액터 홉 없이 읽힌다
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

    func signOut() async {
        try? await client?.auth.signOut()
        user = nil
    }

    /// App Store 5.1.1(v) — 서버에서 auth.users 삭제(cascade) 후 로컬 세션 정리.
    ///
    /// Apple 로그인 계정은 Apple 토큰도 폐기해야 한다. 앱은 refresh token 을 갖고 있지 않으므로
    /// 삭제 직전 Apple 재인증으로 authorizationCode(5분·1회용)를 받아 서버에 넘기고, 서버가 교환·폐기한다.
    /// 재인증 시트를 사용자가 취소하면 삭제도 멈춘다(취소 = 삭제 의사 철회). 그 밖의 실패는 코드 없이 삭제를 진행한다 —
    /// 삭제권이 토큰 폐기보다 우선이다.
    func deleteAccount() async throws {
        var body: [String: Any]?
        if isAppleUser {
            do {
                if let code = try await AppleReauth.authorizationCode() { body = ["appleAuthorizationCode": code] }
            } catch let e as ASAuthorizationError where e.code == .canceled {
                throw AuthError.deleteCancelled
            } catch {
                // 재인증 실패 — 폐기 없이 삭제
            }
        }
        let _: OkBody = try await APIClient.shared.send("/api/me/delete", method: "DELETE", json: body)
        Analytics.shared.track(.accountDelete)
        await Analytics.shared.flush()
        try? await client?.auth.signOut()
        user = nil
    }

    private var isAppleUser: Bool {
        guard let user else { return false }
        if case .string("apple") = user.appMetadata["provider"] { return true }
        return user.identities?.contains { $0.provider == "apple" } ?? false
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    enum AuthError: LocalizedError {
        case notConfigured, appleFailed, deleteCancelled
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "로그인 준비 중이에요. 전적 검색·스쿼드·픽 랭킹은 로그인 없이 쓸 수 있어요."
            case .appleFailed: return "Apple 로그인에 실패했어요."
            case .deleteCancelled: return "Apple 확인을 취소해 계정 삭제를 멈췄어요."
            }
        }
    }
}

/// 계정 삭제 직전 Apple 재인증 — authorizationCode 만 필요하므로 scope 없이 요청한다.
@MainActor
final class AppleReauth: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String?, Error>?
    /// 컨트롤러는 delegate 를 약하게 잡는다 — 요청이 끝날 때까지 여기서 붙잡아 둔다.
    private static var inFlight: AppleReauth?

    static func authorizationCode() async throws -> String? {
        let reauth = AppleReauth()
        inFlight = reauth
        defer { inFlight = nil }
        return try await withCheckedThrowingContinuation { cont in
            reauth.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
            controller.delegate = reauth
            controller.presentationContextProvider = reauth
            controller.performRequests()
        }
    }

    // ASAuthorizationController 는 delegate 를 메인 스레드에서 부른다.
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let code = (authorization.credential as? ASAuthorizationAppleIDCredential)?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        MainActor.assumeIsolated { continuation?.resume(returning: code); continuation = nil }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { continuation?.resume(throwing: error); continuation = nil }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

#if DEBUG
/// 개발 빌드 전용 — supabase-swift 내부 동작(PKCE 코드 교환 등)을 콘솔로 본다.
struct SupabaseDebugLogger: SupabaseLogger {
    func log(message: SupabaseLogMessage) {
        print("[supabase] \(message)")
    }
}
#endif
