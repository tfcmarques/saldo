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
                    .font(.largeTitle.weight(.bold))
                Text(SaldoBrand.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullName).font(.headline)
                    Text("Mac user \u{201C}\(NSUserName())\u{201D}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Text(
                "Saldo will be registered to this Mac user. From now on you unlock it with your fingerprint or your Mac password."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(width: 380)

            Button {
                appLock.register { store.registerCurrentUser() }
            } label: {
                Label("Register and continue", systemImage: "touchid")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appLock.isAuthenticating)

            if !appLock.message.isEmpty {
                Text(appLock.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 380)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LockScreen: View {
    let store: LedgerStore
    let appLock: AppLock

    var body: some View {
        VStack(spacing: 18) {
            SaldoMark(size: 64)
            VStack(spacing: 4) {
                Text("Welcome back, \(store.settings.ownerFirstName)")
                    .font(.title.weight(.semibold))
                Text(SaldoBrand.tagline)
                    .foregroundStyle(.secondary)
            }
            Text(appLock.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 360)
            Button {
                appLock.authenticate()
            } label: {
                Label("Unlock", systemImage: "touchid")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appLock.isAuthenticating)
            Text("Fingerprint or Mac password")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "This Saldo belongs to \(store.settings.ownerName)",
            isPresented: Binding(
                get: { appLock.pendingOwnerChange },
                set: { if !$0 { appLock.declineOwnerChange() } }
            )
        ) {
            Button("Continue as \(NSFullUserName())") {
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
