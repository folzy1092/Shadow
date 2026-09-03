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
        print("Peer name tests passed")
    }
}
