import Foundation
import MacRemoteCore

@main
struct RelayProbe {
    static func main() async {
        let arguments = CommandLine.arguments
        let host = arguments.dropFirst().first ?? "nvdaremote.com"
        let key = arguments.dropFirst(2).first ?? "0871234321"
        let port = UInt16(arguments.dropFirst(3).first ?? "6837") ?? 6837

        let controller = RemoteSessionController(transport: NVDAProtocolTransport())
        await controller.connect(host: host, port: port, key: key)
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("phase=\(controller.snapshot.phase)")
        print("peers=\(controller.snapshot.peers.count)")
        for event in controller.snapshot.eventLog.reversed() {
            print(event.message)
        }

        await controller.disconnect()
    }
}
