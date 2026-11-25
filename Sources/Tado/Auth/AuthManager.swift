import Foundation

/// tado's public client ID for the OAuth device code flow (RFC 8628).
/// Shared by all third-party integrations; not a secret. Keep it in one place in case tado rotates it.
let tadoClientID = "1bb50063-6b0c-4d11-bd99-387f4a91cc46"

struct DeviceAuthorization: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum AuthError: LocalizedError {
    case notSignedIn
    case expired
    case denied
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Not signed in to tado."
        case .expired: "The sign-in code expired. Please try again."
        case .denied: "Sign-in was denied."
        case .server(let message): message
        }
    }
}

/// Owns the OAuth tokens. Access token lives in memory; the refresh token is in the Keychain.
/// tado rotates refresh tokens, so every refresh must persist the new one or the user is logged out.
actor AuthManager {
    private static let refreshTokenKey = "refresh_token"
    private let tokenURL = URL(string: "https://login.tado.com/oauth2/token")!
    private let deviceURL = URL(string: "https://login.tado.com/oauth2/device_authorize")!

    private var accessToken: String?
    private var accessTokenExpiry: Date = .distantPast
    private var refreshTask: Task<String, Error>?

    var hasStoredCredentials: Bool {
        Keychain.read(Self.refreshTokenKey) != nil
    }

    // MARK: Device code flow

    func startDeviceAuthorization() async throws -> DeviceAuthorization {
        let data = try await postForm(deviceURL, [
            "client_id": tadoClientID,
            "scope": "offline_access",
        ])
        return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
    }

    /// Polls the token endpoint until the user approves in the browser, the code expires, or the task is cancelled.
    func waitForApproval(_ auth: DeviceAuthorization) async throws {
        var interval = max(auth.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(auth.expiresIn))

        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            do {
                let data = try await postForm(tokenURL, [
                    "client_id": tadoClientID,
                    "device_code": auth.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
                store(try JSONDecoder().decode(TokenResponse.self, from: data))
                return
            } catch let OAuthFailure.oauth(code, _) where code == "authorization_pending" {
                continue
            } catch let OAuthFailure.oauth(code, _) where code == "slow_down" {
                interval += 5
            } catch let OAuthFailure.oauth(code, _) where code == "expired_token" {
                throw AuthError.expired
            } catch let OAuthFailure.oauth(code, _) where code == "access_denied" {
                throw AuthError.denied
            }
        }
        throw AuthError.expired
    }

    // MARK: Tokens

    /// Returns a valid access token, refreshing if needed. Concurrent callers share one refresh.
    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry.timeIntervalSinceNow > 30 {
            return accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// Forces the next request to refresh (e.g. after a 401).
    func invalidateAccessToken() {
        accessToken = nil
        accessTokenExpiry = .distantPast
    }

    func signOut() {
        accessToken = nil
        accessTokenExpiry = .distantPast
        Keychain.delete(Self.refreshTokenKey)
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = Keychain.read(Self.refreshTokenKey) else {
            throw AuthError.notSignedIn
        }
        do {
            let data = try await postForm(tokenURL, [
                "client_id": tadoClientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            store(token)
            return token.accessToken
        } catch OAuthFailure.oauth(let code, _) where code == "invalid_grant" {
            // Refresh token expired (30 days) or was already used.
            signOut()
            throw AuthError.notSignedIn
        }
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        Keychain.write(token.refreshToken, for: Self.refreshTokenKey)
    }

    // MARK: HTTP

    private enum OAuthFailure: Error {
        case oauth(String, String?)
    }

    private func postForm(_ url: URL, _ fields: [String: String]) async throws -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let err = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthFailure.oauth(err.error, err.errorDescription)
            }
            throw AuthError.server("tado login returned HTTP \(status).")
        }
        return data
    }
}
