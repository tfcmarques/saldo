import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

/// Apple's Touch ID glyph, placed in the window so a fingerprint check needs no system popup.
/// Wrapped in a clipping container: on its own the glyph draws far outside its frame.
struct FingerprintView: NSViewRepresentable {
    let context: LAContext

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        let glyph = LAAuthenticationView(context: context, controlSize: .regular)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glyph.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glyph.topAnchor.constraint(equalTo: container.topAnchor),
            glyph.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_: NSView, context _: Context) {}
}

/// The fingerprint glyph in a round badge with a caption; it pulses while Saldo waits for a finger.
struct FingerprintPrompt: View {
    let appLock: AppLock
    let caption: String

    var body: some View {
        VStack(spacing: DS.Space.m) {
            FingerprintView(context: appLock.fingerprintContext)
                .id(ObjectIdentifier(appLock.fingerprintContext))
                .frame(width: 52, height: 52)
                .frame(width: 96, height: 96)
                .background(DS.Palette.surface, in: Circle())
                .accessibilityLabel("Touch ID")
            Text(caption)
                .font(DS.Typeface.small)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 360)
        }
    }
}

/// Cancels the in-app fingerprint check and opens the Mac password window instead.
struct UsePasswordButton: View {
    let appLock: AppLock
    let usePassword: () -> Void

    var body: some View {
        if appLock.fingerprintAvailable {
            Button("Use Password") {
                appLock.cancelFingerprint()
                usePassword()
            }
            .buttonStyle(.pill(.tertiary))
            .help("Unlock with your Mac password instead")
        }
    }
}

enum SaldoBrand {
    static let name = "Saldo"
    static let tagline = "Know where your money goes."
}

struct WelcomeScreen: View {
    let store: LedgerStore
    let appLock: AppLock

    private var fullName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? NSUserName() : name
    }

    var body: some View {
        VStack(spacing: 22) {
            SaldoMark(size: 72)
            VStack(spacing: 6) {
                Text("Welcome to \(SaldoBrand.name)")
                    .font(DS.Typeface.display)
                    .tracking(-0.5)
                Text(SaldoBrand.tagline)
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            HStack(spacing: 12) {
                IconBubble(systemName: "person", tint: DS.Palette.accent, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullName).font(DS.Typeface.title3)
                    Text("Mac user \u{201C}\(NSUserName())\u{201D}")
                        .formHint()
                }
            }
            .padding(DS.Space.m)
            .frame(width: 320, alignment: .leading)
            .background(
                DS.Palette.surface,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))

            Text(
                "Saldo will be registered to this Mac user. The ledger is encrypted on this Mac and unlocks with your fingerprint or your Mac password."
            )
            .font(DS.Typeface.small)
            .foregroundStyle(DS.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(width: 380)

            if appLock.fingerprintAvailable && appLock.isAuthenticating {
                FingerprintPrompt(appLock: appLock, caption: "Touch ID to register")
                UsePasswordButton(appLock: appLock) { register(usingFingerprint: false) }
            } else {
                Button {
                    register()
                } label: {
                    Label("Register and continue", systemImage: "touchid")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.pill(.primary))
                .controlSize(.large)
                .disabled(appLock.isAuthenticating)
                .help("Confirm with Touch ID or your Mac password")
            }

            if !appLock.message.isEmpty && !appLock.isAuthenticating {
                Text(appLock.message)
                    .formHint()
                    .multilineTextAlignment(.center)
                    .frame(width: 380)
            }
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .onAppear {
            if TestDataMode.isActive { register() }
        }
    }

    private func register(usingFingerprint: Bool = true) {
        appLock.register(usingFingerprint: usingFingerprint) {
            if let error = store.open(using: appLock.authorization) {
                appLock.message = error
                return false
            }
            store.registerCurrentUser()
            return true
        }
    }
}

struct LockScreen: View {
    let store: LedgerStore
    let appLock: AppLock

    var body: some View {
        VStack(spacing: 18) {
            SaldoMark(size: 64)
            VStack(spacing: 4) {
                Text(
                    store.settings.ownerFirstName.isEmpty
                        ? "Welcome back" : "Welcome back, \(store.settings.ownerFirstName)")
                    .font(DS.Typeface.title1)
                Text(SaldoBrand.tagline)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            if appLock.fingerprintAvailable {
                FingerprintPrompt(
                    appLock: appLock,
                    caption: appLock.isAuthenticating ? "Touch ID to unlock" : appLock.message
                )
                .padding(.vertical, DS.Space.m)
                VStack(spacing: DS.Space.s) {
                    if !appLock.isAuthenticating {
                        Button("Try Touch ID Again") { appLock.authenticate() }
                            .buttonStyle(.pill(.primary))
                            .controlSize(.large)
                    }
                    UsePasswordButton(appLock: appLock) {
                        appLock.authenticate(usingFingerprint: false)
                    }
                }
            } else {
                Text(appLock.message)
                    .font(DS.Typeface.small)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
                Button {
                    appLock.authenticate()
                } label: {
                    Label("Unlock", systemImage: "touchid")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.pill(.primary))
                .controlSize(.large)
                .disabled(appLock.isAuthenticating)
                .help("Unlock with Touch ID or your Mac password")
                Text("Fingerprint or Mac password")
                    .formHint()
            }
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
        .alert(
            "This Saldo belongs to \(store.settings.ownerName)",
            isPresented: Binding(
                get: { appLock.pendingOwnerChange },
                set: { if !$0 { appLock.declineOwnerChange() } }
            )
        ) {
            Button("Continue as \(NSFullUserName())") {
                if let error = store.open(using: appLock.authorization) {
                    appLock.message = error
                    appLock.declineOwnerChange()
                    return
                }
                appLock.confirmOwnerChange { store.registerCurrentUser() }
            }
            Button("Cancel", role: .cancel) { appLock.declineOwnerChange() }
        } message: {
            Text(
                "It was registered to the Mac user \u{201C}\(store.settings.ownerUsername)\u{201D}. You are signed in as \u{201C}\(NSUserName())\u{201D}. Continuing registers you as the owner instead."
            )
        }
    }
}
