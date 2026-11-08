import SwiftUI

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

            if !appLock.message.isEmpty {
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

    private func register() {
        appLock.register {
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
