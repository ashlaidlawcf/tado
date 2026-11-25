import Foundation
import os

let apiLog = Logger(subsystem: "local.tado.client", category: "api")

enum TadoAPIError: LocalizedError {
    case http(Int, String)
    case rateLimited
    case tadoXUnsupported

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            // tado errors look like {"errors":[{"code":"…","title":"…"}]}
            struct Envelope: Decodable { struct Item: Decodable { let code: String?; let title: String? }; let errors: [Item] }
            if let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)),
               let first = envelope.errors.first {
                let parts = [first.code, first.title].compactMap { $0 }
                return "tado rejected the request (HTTP \(code)): \(parts.joined(separator: " – "))"
            }
            return "tado API error \(code): \(body.prefix(300))"
        case .rateLimited:
            return "tado's daily API limit was reached. Try again later."
        case .tadoXUnsupported:
            return "This home uses tado X, which this app can't control yet."
        }
    }

    /// tado's machine-readable error code, e.g. "unsupportedOverlayTerminationType".
    var tadoCode: String? {
        guard case .http(_, let body) = self else { return nil }
        struct Envelope: Decodable { struct Item: Decodable { let code: String? }; let errors: [Item] }
        return (try? JSONDecoder().decode(Envelope.self, from: Data(body.utf8)))?.errors.first?.code
    }
}

/// Thin client for the (unofficial) tado v2 REST API at my.tado.com.
/// Note: tado X devices use a different API (hops.tado.com) and are not covered here.
struct TadoClient: Sendable {
    let auth: AuthManager
    private let base = URL(string: "https://my.tado.com/api/v2/")!

    func me() async throws -> Me {
        try await get("me")
    }

    func home(_ id: Int) async throws -> HomeDetail {
        try await get("homes/\(id)")
    }

    func zones(home: Int) async throws -> [Zone] {
        try await get("homes/\(home)/zones")
    }

    func zoneStates(home: Int) async throws -> [Int: ZoneState] {
        let response: ZoneStatesResponse = try await get("homes/\(home)/zoneStates")
        return Dictionary(uniqueKeysWithValues: response.zoneStates.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    /// Sets an override that ends at the next schedule change, or stays until changed
    /// if the zone has no upcoming schedule block (tado rejects NEXT_TIME_BLOCK then).
    func setOverlayUntilNextChange(home: Int, zone: Zone, celsius: Double?) async throws {
        do {
            try await setOverlay(home: home, zone: zone, celsius: celsius, termination: .nextTimeBlock)
        } catch let error as TadoAPIError where error.tadoCode == "unsupportedOverlayTerminationType" {
            try await setOverlay(home: home, zone: zone, celsius: celsius, termination: .manual)
        }
    }

    /// Sets a manual override (temperature or off) on a zone.
    func setOverlay(home: Int, zone: Zone, celsius: Double?, termination: OverlayTermination) async throws {
        var setting: [String: Any] = ["type": zone.type.rawValue, "power": celsius == nil ? "OFF" : "ON"]
        if let celsius {
            setting["temperature"] = ["celsius": celsius]
        }
        let body: [String: Any] = ["setting": setting, "termination": termination.json]
        _ = try await send("homes/\(home)/zones/\(zone.id)/overlay", method: "PUT",
                           body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Removes the manual override so the zone resumes its schedule.
    func resumeSchedule(home: Int, zone: Int) async throws {
        _ = try await send("homes/\(home)/zones/\(zone)/overlay", method: "DELETE")
    }

    // MARK: HTTP

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(path, method: "GET"))
    }

    private func send(_ path: String, method: String, body: Data? = nil, isRetry: Bool = false) async throws -> Data {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401 where !isRetry:
            await auth.invalidateAccessToken()
            return try await send(path, method: method, body: body, isRetry: true)
        case 429:
            throw TadoAPIError.rateLimited
        default:
            let responseBody = String(decoding: data, as: UTF8.self)
            let requestBody = body.map { String(decoding: $0, as: UTF8.self) } ?? "-"
            apiLog.error("""
                \(method, privacy: .public) \(path, privacy: .public) -> HTTP \(status) \
                request=\(requestBody, privacy: .public) response=\(responseBody, privacy: .public)
                """)
            throw TadoAPIError.http(status, responseBody)
        }
    }
}
