import AppKit
import MacRemoteCore

@MainActor
final class SessionSoundPlayer: ObservableObject {
    func playTransition(from oldPhase: RemoteSessionPhase, to newPhase: RemoteSessionPhase) {
        guard oldPhase != newPhase else { return }
        switch newPhase {
        case .connected:
            if oldPhase == .connecting || oldPhase == .idle {
                play(named: "Glass")
            }
        case .idle:
            if oldPhase == .connected || oldPhase == .controlling || oldPhase == .connecting {
                play(named: "Basso")
            }
        case .failed:
            play(named: "Sosumi")
        case .connecting, .controlling:
            break
        }
    }

    private func play(named name: String) {
        NSSound(named: .init(name))?.play()
    }
}
