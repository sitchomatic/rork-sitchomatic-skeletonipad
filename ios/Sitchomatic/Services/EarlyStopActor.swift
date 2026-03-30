import Foundation

actor EarlyStopActor {
    private var state: SessionGlobalState = .active
    private var terminatingSite: String?
    private var terminatingOutcome: LoginOutcome?

    var currentState: SessionGlobalState {
        state
    }

    var isActive: Bool {
        state == .active
    }

    var triggerInfo: (site: String, outcome: LoginOutcome)? {
        guard let site = terminatingSite, let outcome = terminatingOutcome else { return nil }
        return (site, outcome)
    }

    func signalSuccess(from site: String) {
        guard state == .active else { return }
        state = .success
        terminatingSite = site
        terminatingOutcome = .success
    }

    func signalPermBan(from site: String) {
        guard state == .active else { return }
        state = .abortPerm
        terminatingSite = site
        terminatingOutcome = .permDisabled
    }

    func signalTempLock(from site: String) {
        guard state == .active else { return }
        state = .abortTemp
        terminatingSite = site
        terminatingOutcome = .tempDisabled
    }

    func signalExhausted() {
        guard state == .active else { return }
        state = .exhausted
    }

    func reset() {
        state = .active
        terminatingSite = nil
        terminatingOutcome = nil
    }
}
