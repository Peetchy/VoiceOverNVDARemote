import MacRemoteCore
import RemoteProtocol
import SwiftUI

@main
struct VONVDARemoteApp: App {
    // Built in a helper: Swift 6.1 crashes in SILGen when the StateObject
    // autoclosure itself contains the nested sound player construction.
    @StateObject private var controller = makeRemoteSessionController()
    @StateObject private var sparkleController = SparkleController()

    var body: some Scene {
        WindowGroup("VO NVDA Remote") {
            ContentView(controller: controller)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 560, idealHeight: 720)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    sparkleController.checkForUpdates()
                }
            }
        }
    }
}

/// Lets `swift run` find the NVDA waves, which are only copied into packaged app bundles.
private let developmentSoundDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sounds", isDirectory: true)

@MainActor
private func makeRemoteSessionController() -> RemoteSessionController {
    var soundDirectories = SystemRemoteSoundPlayer.bundledSoundDirectories
    soundDirectories.append(developmentSoundDirectory)
    let soundPlayer = SystemRemoteSoundPlayer(soundDirectories: soundDirectories)
    return RemoteSessionController(transport: NVDAProtocolTransport(), soundPlayer: soundPlayer)
}
