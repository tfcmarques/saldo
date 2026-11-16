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
    /// Shown inside the lock screens by FingerprintView, so Touch ID needs no system window.
    var fingerprintContext = LAContext()
    var fingerprintAvailable = LAContext().canEvaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics, error: nil)
    /// Set when unlock succeeded but the database could not be opened. Stops the active-notification from prompting again.
    var pausesAutomaticUnlock = false
    /// 0 disables auto-lock; kept in sync with the saved setting.
    var autoLockMinutes = 5
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var activityMonitor: Any?
    @ObservationIgnored private var idleTimer: Timer?

    func authenticate(usingFingerprint: Bool = true) {
        pausesAutomaticUnlock = false
        guard !isAuthenticating, !ownerUsername.isEmpty else { return }
        evaluate(reason: "Unlock Saldo.", usingFingerprint: usingFingerprint) { [weak self] success, context in
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
    func register(usingFingerprint: Bool = true, onSuccess: @escaping @MainActor () -> Bool) {
        guard !isAuthenticating else { return }
        evaluate(
            reason: "Register \(NSFullUserName()) as the owner of Saldo.",
            usingFingerprint: usingFingerprint
        ) {
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

    /// Stops a pending in-app fingerprint check so the password window can take over.
    func cancelFingerprint() {
        let pending = fingerprintContext
        fingerprintContext = LAContext()  // its callback sees it was replaced and does nothing
        pending.invalidate()
        isAuthenticating = false
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
        lockWhenMacIsLeft()
    }

    /// Lock as soon as the Mac sleeps, its screen locks, or another user takes over, so
    /// the ledger is never open behind the login window. Runs whatever the auto-lock setting.
    private func lockWhenMacIsLeft() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }
    }

    // Password fallback keeps a Mac without a working Touch ID sensor from being locked out.
    private func evaluate(
        reason: String, usingFingerprint: Bool = false,
        completion: @escaping @MainActor (Bool, LAContext?) -> Void
    ) {
        isAuthenticating = true
        if TestDataMode.isActive {
            isAuthenticating = false
            completion(true, LAContext())
            return
        }
        fingerprintAvailable = fingerprintContext.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil)
        if usingFingerprint && fingerprintAvailable {
            evaluateFingerprint(reason: reason, completion: completion)
            return
        }
        let context = LAContext()
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

    private func evaluateFingerprint(
        reason: String, completion: @escaping @MainActor (Bool, LAContext?) -> Void
    ) {
        let context = fingerprintContext
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
            [weak self] success, error in
            Task { @MainActor in
                guard let self, context === self.fingerprintContext else { return }
                self.isAuthenticating = false
                // A used context can't start a new check; the view rebuilds around the fresh one.
                self.fingerprintContext = LAContext()
                if !success {
                    let code = (error as? LAError)?.code
                    if code != .userCancel && code != .systemCancel && code != .appCancel {
                        self.message =
                            error?.localizedDescription ?? "Fingerprint not recognised. Try again."
                    }
                }
                completion(success, success ? context : nil)
            }
        }
    }
}
