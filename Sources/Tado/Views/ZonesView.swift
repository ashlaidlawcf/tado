import SwiftUI

struct ZonesView: View {
    @Environment(AppModel.self) private var model

    private var heatingZones: [Zone] { model.zones.filter { $0.type == .heating } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if heatingZones.isEmpty && model.isRefreshing {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            }

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(heatingZones) { zone in
                        ZoneCard(zone: zone, state: model.states[zone.id])
                    }
                }
            }
        }
        .task { await model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if model.homes.count > 1 {
                    Menu {
                        ForEach(model.homes) { home in
                            Button(home.name) { model.selectHome(home.id) }
                        }
                    } label: {
                        Text(currentHomeName).font(.title2.weight(.bold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(currentHomeName).font(.title2.weight(.bold))
                }

                Group {
                    if let updated = model.lastUpdated {
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                    } else {
                        Text("Loading…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isRefreshing)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(model.isRefreshing)
            .help("Refresh")
        }
    }

    private var currentHomeName: String {
        model.homes.first { $0.id == model.selectedHomeID }?.name ?? "tado°"
    }
}

struct ZoneCard: View {
    @Environment(AppModel.self) private var model
    let zone: Zone
    let state: ZoneState?

    /// Target shown while the user is still tapping +/−; sent after a short pause
    /// so a run of taps costs one API call instead of many.
    @State private var pendingTarget: Double?
    @State private var debounce: Task<Void, Never>?
    @State private var isBusy = false

    private var isOn: Bool { state?.setting.isOn == true }
    private var serverTarget: Double? { isOn ? state?.setting.temperature?.celsius : nil }
    private var displayedTarget: Double? { pendingTarget ?? serverTarget }
    private var heatingPower: Double { state?.heatingPower ?? 0 }
    private var isHeating: Bool { heatingPower > 0 }

    private var tint: Color {
        if !isOn { return .gray }
        return isHeating ? .orange : .teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: isHeating ? "flame.fill" : (isOn ? "thermometer.medium" : "power"))
                    .font(.title3)
                    .foregroundStyle(tint.gradient)
                    .symbolEffect(.pulse, isActive: isHeating)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.tint(tint.opacity(0.2)), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.name).font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }

                Spacer()

                if let inside = state?.insideTemperature {
                    let degrees = Text("°")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(inside, format: .number.precision(.fractionLength(1)))\(degrees)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: inside))
                }
            }

            HStack(spacing: 8) {
                targetStepper

                if let humidity = state?.humidity {
                    Label("\(Int(humidity))%", systemImage: "humidity.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                Spacer()

                Menu {
                    Button("Turn Off", systemImage: "power") { run { await model.turnOff(zone) } }
                        .disabled(!isOn)
                    Button("Resume Schedule", systemImage: "calendar") { run { await model.resumeSchedule(zone) } }
                        .disabled(state?.hasOverlay != true)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .fixedSize()
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(tint.opacity(isOn ? 0.12 : 0.04)), in: .rect(cornerRadius: 22))
        .disabled(isBusy || state == nil)
        .animation(.smooth, value: state)
        .animation(.snappy, value: pendingTarget)
    }

    private var targetStepper: some View {
        HStack(spacing: 2) {
            Button { nudge(by: -0.5) } label: {
                Image(systemName: "minus").frame(width: 22, height: 22)
            }
            .disabled((displayedTarget ?? 5) <= 5)

            Group {
                if let target = displayedTarget {
                    Text("\(target, format: .number.precision(.fractionLength(1)))°")
                } else {
                    Text("Off")
                }
            }
            .font(.system(.body, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText(value: displayedTarget ?? 0))
            .frame(minWidth: 48)

            Button { nudge(by: 0.5) } label: {
                Image(systemName: "plus").frame(width: 22, height: 22)
            }
            .disabled((displayedTarget ?? 0) >= 25)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var statusText: String {
        guard let state else { return "Loading…" }
        if !isOn { return state.hasOverlay ? "Off · manual" : "Off" }
        let mode = state.hasOverlay ? "Manual until next change" : "Following schedule"
        return isHeating ? "Heating \(Int(heatingPower))% · \(mode)" : mode
    }

    private func nudge(by delta: Double) {
        let next = min(max((displayedTarget ?? 18) + delta, 5), 25)   // tado heating range
        pendingTarget = next
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await model.setTemperature(next, for: zone)
            pendingTarget = nil
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        isBusy = true
        Task {
            await action()
            isBusy = false
        }
    }
}
