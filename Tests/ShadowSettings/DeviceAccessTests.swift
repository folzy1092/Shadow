import Foundation

@main
struct DeviceAccessTests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(ShadowDeviceAccess.normalize(" ab12-cd34 ") == "AB12-CD34", "Normalize trims and uppercases")
        let json = """
        {"enabled":true,"devices":[{"id":"ab12-cd34-ef56-7890","note":"мой"},{"id":" "},{"note":"без id"}]}
        """
        let list = ShadowDeviceAccess.parse(Data(json.utf8))
        check(list?.enabled == true, "Enabled parsed")
        check(list?.devices.map { $0.id } == ["AB12-CD34-EF56-7890"], "Blank and missing ids dropped")
        check(list?.devices.first?.note == "мой", "Note kept")
        check(ShadowDeviceAccess.parse(Data("nope".utf8)) == nil, "Malformed JSON")
        check(ShadowDeviceAccess.parse(Data("{\"devices\":[]}".utf8))?.enabled == true, "Enabled by default")

        check(ShadowDeviceAccess.decide(deviceId: "ab12-cd34-ef56-7890", whitelist: list) == .allowed, "Listed device allowed, case-insensitive")
        check(ShadowDeviceAccess.decide(deviceId: "FFFF-0000-0000-0000", whitelist: list) == .denied, "Unlisted device denied")
        check(ShadowDeviceAccess.decide(deviceId: "FFFF-0000-0000-0000", whitelist: nil) == .unknown, "No list yet")
        let off = ShadowDeviceAccess.Whitelist(enabled: false, devices: [])
        check(ShadowDeviceAccess.decide(deviceId: "X", whitelist: off) == .allowed, "Disabled list lets everyone in")

        if let list {
            check(ShadowDeviceAccess.parse(Data(ShadowDeviceAccess.encode(list).utf8)) == list, "Encode round-trip")
        }
        check(list?.requestURL == nil, "No request endpoint by default")
        let withBot = ShadowDeviceAccess.parse(Data("{\"devices\":[],\"request_url\":\"https://bot.example.workers.dev/request\"}".utf8))
        check(withBot?.requestURL?.absoluteString == "https://bot.example.workers.dev/request", "Request endpoint parsed")
        if let withBot {
            check(ShadowDeviceAccess.parse(Data(ShadowDeviceAccess.encode(withBot).utf8)) == withBot, "Request endpoint survives copying the JSON")
        }
        check(ShadowDeviceAccess.parse(Data("{\"request_url\":\"http://insecure.example\"}".utf8))?.requestURL == nil, "Only https endpoints")

        // Admin devices and admin endpoint.
        let adminJSON = """
        {"enabled":true,"admin_url":"https://bot.example.workers.dev/admin","devices":[{"id":"aaaa-bbbb-cccc-dddd","note":"я","admin":true},{"id":"eeee-ffff-0000-1111","note":"друг"}]}
        """
        let adminList = ShadowDeviceAccess.parse(Data(adminJSON.utf8))
        check(adminList?.adminURL?.absoluteString == "https://bot.example.workers.dev/admin", "Admin endpoint parsed")
        check(adminList?.devices.first?.admin == true, "Admin device parsed")
        check(adminList?.devices.last?.admin == false, "Non-admin device defaults to false")
        check(ShadowDeviceAccess.isAdminDevice(adminList) == false, "This device is not the admin device in the fixture")
        if let adminList {
            check(ShadowDeviceAccess.parse(Data(ShadowDeviceAccess.encode(adminList).utf8)) == adminList, "Admin flag and endpoint survive copying the JSON")
        }
        check(ShadowDeviceAccess.hasAdminAccess(peerId: ShadowDeviceAccess.adminPeerId), "Owner always has admin access")
        check(!ShadowDeviceAccess.hasAdminAccess(peerId: 12345), "Random account has no admin access without an admin device")
        let body = ShadowDeviceAccess.accessRequestBody(deviceId: " ab12-cd34-ef56-7890 ", name: "  Вася  ", model: "iPhone16,1", system: "iOS 26.0", build: "34730")
        let decoded = (try? JSONSerialization.jsonObject(with: body)) as? [String: String]
        check(decoded?["id"] == "AB12-CD34-EF56-7890" && decoded?["name"] == "Вася", "Request body normalized")
        print("Shadow device access: \(count) checks passed")
    }
}
