import MacRemoteCore
import RemoteProtocol
import SwiftUI

@main
struct VONVDARemoteApp: App {
    @StateObject private var controller = RemoteSessionController(
        transport: NVDAProtocolTransport()
    )

    var body: some Scene {
        WindowGroup("VO NVDA Remote") {
            ContentView(controller: controller)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
