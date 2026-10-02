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
        print("Shadow device access: \(count) checks passed")
    }
}
