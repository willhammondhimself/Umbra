import AuthenticationServices
import Foundation
import Security

@MainActor
@Observable
final class AuthManager: NSObject {
    static let shared = AuthManager()

    private(set) var currentUser: User?
    private(set) var isAuthenticated = false
    private(set) var isLoading = false

    private let baseURL = URL(string: "http://localhost:8000")!

    private override init() {
        super.init()
        loadTokensFromKeychain()
    }

    // MARK: - Sign In with Apple

    func signInWithApple() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Sign In with Google (via ASWebAuthenticationSession)

    func signInWithGoogle() {
        // Google OAuth via system browser session
        // In production, configure with real client ID and redirect URI
        isLoading = true

        // Placeholder: Google Sign-In requires ASWebAuthenticationSession
        // with proper client ID configuration. For now, this is stubbed.
        isLoading = false
    }

    // MARK: - Token Exchange with Backend

    private func exchangeToken(provider: String, identityToken: String) async {
        isLoading = true
        defer { isLoading = false }

        let url = baseURL.appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "provider": provider,
            "identity_token": identityToken,
        ]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Auth failed: bad status code")
                return
            }

            let decoder = JSONDecoder()
            let tokenResponse = try decoder.decode(TokenResponse.self, from: data)
            saveTokensToKeychain(access: tokenResponse.accessToken, refresh: tokenResponse.refreshToken)
            await fetchCurrentUser()
        } catch {
            print("Auth token exchange failed: \(error)")
        }
    }

    // MARK: - Fetch Current User

    func fetchCurrentUser() async {
        guard let accessToken = getAccessToken() else { return }

        let url = baseURL.appendingPathComponent("auth/me")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 {
                // Try refresh
                if await refreshAccessToken() {
                    await fetchCurrentUser()
                } else {
                    logout()
                }
                return
            }

            guard httpResponse.statusCode == 200 else { return }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            currentUser = try decoder.decode(User.self, from: data)
            isAuthenticated = true
        } catch {
            print("Failed to fetch user: \(error)")
        }
    }

    // MARK: - Token Refresh

    func refreshAccessToken() async -> Bool {
        guard let refreshToken = getRefreshToken() else { return false }

        let url = baseURL.appendingPathComponent("auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            saveTokensToKeychain(access: tokenResponse.accessToken, refresh: tokenResponse.refreshToken)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Logout

    func logout() {
        deleteTokensFromKeychain()
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Keychain

    private let accessTokenKey = "com.umbra.accessToken"
    private let refreshTokenKey = "com.umbra.refreshToken"

    func getAccessToken() -> String? {
        readKeychain(key: accessTokenKey)
    }

    private func getRefreshToken() -> String? {
        readKeychain(key: refreshTokenKey)
    }

    private func saveTokensToKeychain(access: String, refresh: String) {
        writeKeychain(key: accessTokenKey, value: access)
        writeKeychain(key: refreshTokenKey, value: refresh)
    }

    private func deleteTokensFromKeychain() {
        deleteKeychain(key: accessTokenKey)
        deleteKeychain(key: refreshTokenKey)
    }

    private func loadTokensFromKeychain() {
        if getAccessToken() != nil {
            // We have stored tokens — attempt to validate on next run loop
            Task {
                await fetchCurrentUser()
            }
        }
    }

    private func writeKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            return
        }

        Task { @MainActor in
            await exchangeToken(provider: "apple", identityToken: identityToken)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        print("Apple Sign In failed: \(error)")
    }
}

// MARK: - Token Response

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}
