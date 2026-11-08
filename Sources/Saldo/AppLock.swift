import AppKit
@preconcurrency import LocalAuthentication
import Observation

@MainActor
@Observable
final class AppLock {
    var isUnlocked = false
    var isAuthenticating = false
    var message = "Use your fingerprint or your Mac password to unlock Saldo."
    /// Mac username Saldo is registered to; empty until first-run registration.
    var ownerUsername = ""
    var pendingOwnerChange = false
    /// Context from the latest successful unlock.
    @ObservationIgnored var authorization: LAContext?
    /// Set when unlock succeeded but the database could not be opened. Stops the active-notification from prompting again.
    var pausesAutomaticUnlock = false
    /// 0 disables auto-lock; kept in sync with the saved setting.
    var autoLockMinutes = 5
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var activityMonitor: Any?
    @ObservationIgnored private var idleTimer: Timer?

    func authenticate() {
        pausesAutomaticUnlock = false
        guard !isAuthenticating, !ownerUsername.isEmpty else { return }
        evaluate(reason: "Unlock Saldo.") { [weak self] success, context in
            guard let self, success, let context else { return }
            self.authorization = context
            if self.ownerUsername == NSUserName() {
                self.unlockVerified()
            } else {
                self.pendingOwnerChange = true
            }
        }
    }

    /// First launch: the current Mac user proves who they are, then becomes the owner.
    /// `onSuccess` returns false when the database could not be opened; the app stays locked.
    func register(onSuccess: @escaping @MainActor () -> Bool) {
        guard !isAuthenticating else { return }
        evaluate(reason: "Register \(NSFullUserName()) as the owner of Saldo.") {
            [weak self] success, context in
            guard let self, success, let context else { return }
            self.authorization = context
            guard onSuccess() else { return }
            self.unlockVerified()
        }
    }

    /// Data registered to another Mac user is being opened by the current one.
    func confirmOwnerChange(register: () -> Void) {
        pendingOwnerChange = false
        register()
        unlockVerified()
    }

    func declineOwnerChange() {
        pendingOwnerChange = false
    }

    func unlockVerified() {
        isUnlocked = true
        noteActivity()
    }

    func authenticateForDestructiveAction(
        reason: String = "Confirm deletion of all Saldo data.",
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard !isAuthenticating else { return }
        evaluate(reason: reason) { success, _ in completion(success) }
    }

    func lock() {
        guard isUnlocked else { return }
        isUnlocked = false
        authorization = nil
        message = "Saldo is locked. Authenticate to continue."
    }

    func noteLockedOut(_ message: String) {
        self.message = message
        authorization = nil
        pausesAutomaticUnlock = true
        isUnlocked = false
    }

    func noteStillUnlocked(_ message: String) {
        self.message = message
        isUnlocked = true
    }

    func noteActivity() {
        lastActivity = Date()
    }

    func lockIfIdle() {
        guard isUnlocked, autoLockMinutes > 0 else { return }
        if Date().timeIntervalSince(lastActivity) >= Double(autoLockMinutes) * 60 { lock() }
    }

    func startActivityMonitoring() {
        guard activityMonitor == nil else { return }
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.noteActivity() }
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lockIfIdle() }
        }
    }

    // Password fallback keeps a Mac without a working Touch ID sensor from being locked out.
    private func evaluate(
        reason: String, completion: @escaping @MainActor (Bool, LAContext?) -> Void
    ) {
        isAuthenticating = true
        let context = LAContext()
        if TestDataMode.isActive {
            isAuthenticating = false
            completion(true, context)
            return
        }
        var evaluationError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            isAuthenticating = false
            message = "This Mac can't verify your identity. Set up Touch ID or a login password."
            completion(false, nil)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) {
            [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if !success {
                    self.message =
                        error?.localizedDescription ?? "Authentication failed. Try again."
                }
                completion(success, success ? context : nil)
            }
        }
    }
}
