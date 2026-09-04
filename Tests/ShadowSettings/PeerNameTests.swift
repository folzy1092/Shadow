import Foundation

@main
struct PeerNameTests {
    static func main() {
        func title(_ username: String?, _ enabled: Bool = true, _ isContact: Bool? = false, _ isSelf: Bool = false) -> String? {
            return ShadowPeerName.username(username, enabled: enabled, isContact: isContact, isSelf: isSelf)
        }
        precondition(title("folzy") == "\u{2066}@folzy\u{2069}")
        precondition(title("folzy", false) == nil)
        precondition(title("folzy", true, true) == nil)
        precondition(title("folzy", true, nil) == nil)
        precondition(title("folzy", true, false, true) == nil)
        precondition(title(nil) == nil)
        precondition(title("") == nil)
        precondition(title("Case_Preserved") == "\u{2066}@Case_Preserved\u{2069}")
        for enabled in [false, true] {
            for botsEnabled in [false, true] {
                for isBot in [false, true] {
                    let name = ShadowPeerName.username("helper_bot", enabled: enabled, isContact: false, isSelf: false, isBot: isBot, botsEnabled: botsEnabled)
                    precondition((name != nil) == (enabled && (!isBot || botsEnabled)))
                }
            }
        }
        precondition(ShadowPeerName.username("helper_bot", enabled: true, isContact: true, isSelf: false, isBot: true, botsEnabled: true) == nil)
        precondition(ShadowPeerName.username("helper_bot", enabled: true, isContact: nil, isSelf: false, isBot: true, botsEnabled: true) == nil)
        precondition(ShadowPeerName.username(nil, enabled: true, isContact: false, isSelf: false, isBot: true, botsEnabled: true) == nil)
        print("Peer name tests passed")
    }
}
