import MacRemoteCore
import RemoteProtocol
import SwiftUI

@main
struct VONVDARemoteApp: App {
    @StateObject private var controller = RemoteSessionController(
        transport: NVDAProtocolTransport()
    )
    @StateObject private var sparkleController = SparkleController()

    var body: some Scene {
        WindowGroup("VO NVDA Remote") {
            ContentView(controller: controller, sparkleController: sparkleController)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
