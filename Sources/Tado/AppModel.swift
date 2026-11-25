import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case signedOut
        case awaitingApproval(DeviceAuthorization)
        case signedIn
    }

    var phase: Phase = .loading
    var homes: [HomeRef] = []
    var selectedHomeID: Int? {
        didSet { UserDefaults.standard.set(selectedHomeID, forKey: "selectedHomeID") }
    }
    var zones: [Zone] = []
    var states: [Int: ZoneState] = [:]
    var lastUpdated: Date?
    var isRefreshing = false
    var errorMessage: String?

    var isAnyZoneHeating: Bool {
        states.values.contains { ($0.heatingPower ?? 0) > 0 }
    }

    private let auth = AuthManager()
    private var client: TadoClient { TadoClient(auth: auth) }
    private var signInTask: Task<Void, Never>?

    /// tado caps API calls per day (about 100 without an Auto-Assist subscription),
    /// so the app only refreshes when opened and at most once per this interval.
    private let minRefreshInterval: TimeInterval = 120

    init() {
        selectedHomeID = UserDefaults.standard.object(forKey: "selectedHomeID") as? Int
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        if await auth.hasStoredCredentials {
            phase = .signedIn
            await loadHomes()
        } else {
            phase = .signedOut
        }
    }

    // MARK: Sign in / out

    func signIn() {
        errorMessage = nil
        signInTask?.cancel()
        signInTask = Task {
            do {
                let authorization = try await auth.startDeviceAuthorization()
                phase = .awaitingApproval(authorization)
                NSWorkspace.shared.open(authorization.verificationURIComplete)
                try await auth.waitForApproval(authorization)
                phase = .signedIn
                await loadHomes()
            } catch is CancellationError {
                phase = .signedOut
            } catch {
                errorMessage = error.localizedDescription
                phase = .signedOut
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        phase = .signedOut
    }

    func signOut() {
        Task {
            await auth.signOut()
            homes = []; zones = []; states = [:]; lastUpdated = nil
            phase = .signedOut
        }
    }

    // MARK: Data

    private func loadHomes() async {
        do {
            homes = try await client.me().homes
            if selectedHomeID == nil || !homes.contains(where: { $0.id == selectedHomeID }) {
                selectedHomeID = homes.first?.id
            }
            await refresh(force: true)
        } catch {
            handle(error)
        }
    }

    func selectHome(_ id: Int) {
        guard id != selectedHomeID else { return }
        selectedHomeID = id
        zones = []; states = [:]
        Task { await refresh(force: true) }
    }

    func refresh(force: Bool = false) async {
        guard case .signedIn = phase, let home = selectedHomeID, !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < minRefreshInterval { return }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if zones.isEmpty {
                zones = try await client.zones(home: home)
            }
            states = try await client.zoneStates(home: home)
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    func setTemperature(_ celsius: Double, for zone: Zone) async {
        await mutate { try await $0.setOverlay(home: $1, zone: zone, celsius: celsius, termination: .nextTimeBlock) }
    }

    func turnOff(_ zone: Zone) async {
        await mutate { try await $0.setOverlay(home: $1, zone: zone, celsius: nil, termination: .nextTimeBlock) }
    }

    func resumeSchedule(_ zone: Zone) async {
        await mutate { try await $0.resumeSchedule(home: $1, zone: zone.id) }
    }

    private func mutate(_ action: (TadoClient, Int) async throws -> Void) async {
        guard let home = selectedHomeID else { return }
        do {
            try await action(client, home)
            await refresh(force: true)
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if case AuthError.notSignedIn = error {
            phase = .signedOut
            errorMessage = "Your tado session expired. Please sign in again."
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
