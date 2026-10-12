import MacRemoteCore
import RemoteProtocol
import SwiftUI

@main
struct VONVDARemoteApp: App {
    @StateObject private var controller = RemoteSessionController(
        transport: NVDAProtocolTransport(),
        soundPlayer: SystemRemoteSoundPlayer(
            soundDirectories: SystemRemoteSoundPlayer.bundledSoundDirectories + [developmentSoundDirectory]
        )
    )
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
