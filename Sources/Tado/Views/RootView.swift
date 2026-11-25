import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                case .signedOut:
                    SignInView()
                case .awaitingApproval(let authorization):
                    ApprovalView(authorization: authorization)
                case .signedIn:
                    ZonesView()
                }
            }
            .transition(.blurReplace)

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            FooterBar()
        }
        .padding(14)
        .animation(.smooth, value: phaseKey)
        .animation(.smooth, value: model.errorMessage)
    }

    private var phaseKey: Int {
        switch model.phase {
        case .loading: 0
        case .signedOut: 1
        case .awaitingApproval: 2
        case .signedIn: 3
        }
    }
}

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if case .signedIn = model.phase {
                    Button {
                        model.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .help("Sign out of tado")
                }
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .help("Quit")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)   // wrap instead of truncating
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy error")
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .help("Dismiss")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.red.opacity(0.25)), in: .rect(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.orange.gradient)
                .symbolEffect(.breathe)
                .frame(width: 84, height: 84)
                .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .circle)

            VStack(spacing: 4) {
                Text("Connect your tado° account")
                    .font(.title3.weight(.semibold))
                Text("You sign in on tado's website, so this app never sees your password.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.signIn()
            } label: {
                Text("Sign In with tado°").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct ApprovalView: View {
    @Environment(AppModel.self) private var model
    let authorization: DeviceAuthorization

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Approve in Your Browser")
                    .font(.title3.weight(.semibold))
                Text("If the page didn't open, visit the link below and enter this code.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(authorization.userCode)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .kerning(4)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(authorization.userCode, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Link(destination: authorization.verificationURIComplete) {
                Label(authorization.verificationURI.host() ?? "Open tado login", systemImage: "safari")
            }
            .font(.callout)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelSignIn() }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
