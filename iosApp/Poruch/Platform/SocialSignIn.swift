import AuthenticationServices
import GoogleSignIn
import UIKit

/// Вхід через Google й Apple: обидва дають ID-токен з nonce від спільного шару (`idTokenNonce`),
/// далі його приймає Supabase Auth.
enum SocialSignIn {
    /// Кнопка Google є, лише коли збірка знає iOS client ID (`GOOGLE_IOS_CLIENT_ID` у Config.xcconfig).
    static var googleAvailable: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) ?? "").isEmpty
    }

    /// ID-токен Google. Nil — людина закрила вікно; решта збоїв — винятки.
    @MainActor static func googleIdToken(nonce: String) async throws -> String? {
        guard let presenter = topViewController() else { return nil }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: nonce
            )
            return result.user.idToken?.tokenString
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }

    /// Токен з відповіді Apple і імʼя, яке Apple дає лише при першому вході.
    static func appleToken(_ credential: ASAuthorizationAppleIDCredential) -> (token: String, name: String?)? {
        guard let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else { return nil }
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
        return (token, name?.isEmpty == false ? name : nil)
    }

    /// Людина закрила аркуш сама — не помилка, мовчимо.
    static func isCancel(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// Вхід живе в шиті: показуємо поверх найвищого контролера, а не кореня.
    @MainActor private static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Запит до Apple без кнопки `SignInWithAppleButton`: перед видаленням акаунта людина ще раз
/// підтверджує, що це вона, а свіжий `authorizationCode` дає серверу відкликати токени Apple.
final class AppleReauthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Подвійний тап, поки перший запит ще йде: другий — як скасування, відповідь отримає перший.
    @MainActor func authorizationCode() async throws -> String? {
        guard continuation == nil else { throw ASAuthorizationError(.canceled) }
        let credential = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [ASAuthorizationAppleIDProvider().createRequest()])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
        return credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(.success(credential))
        } else {
            finish(.failure(ASAuthorizationError(.unknown)))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}
