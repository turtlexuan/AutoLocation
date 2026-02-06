import Foundation

struct Device: Identifiable, Codable, Hashable {
    var id: String { udid }
    let udid: String
    let name: String
    let productType: String
    let osVersion: String
    let connectionType: String
    let tunnelStatus: String  // "not_needed", "not_connected", "connected"
    let needsTunnel: Bool

    var isTunnelReady: Bool {
        !needsTunnel || tunnelStatus == "connected"
    }
}
