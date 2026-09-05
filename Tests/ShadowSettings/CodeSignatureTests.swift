import Foundation

@main
struct CodeSignatureTests {
    static func main() throws {
        func word(_ value: UInt32, little: Bool = false) -> [UInt8] {
            let bytes = [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
            return little ? Array(bytes.reversed()) : bytes
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["aps-environment": "production", "application-identifier": "TEST.example.app"], format: .xml, options: 0)
        let blob = word(0xfade7171) + word(UInt32(plist.count + 8)) + Array(plist)
        let signature = word(0xfade0cc0) + word(UInt32(20 + blob.count)) + word(1) + word(5) + word(20) + blob
        var thin = Data()
        for value in [UInt32(0xfeedfacf), 0x0100000c, 0, 2, 1, 16, 0, 0, 0x1d, 16, 48, UInt32(signature.count)] {
            thin.append(contentsOf: word(value, little: true))
        }
        thin.append(contentsOf: signature)
        precondition(ShadowCodeSignature.entitlements(data: thin)?["aps-environment"] as? String == "production")
        var fat = Data(word(0xcafebabe) + word(1) + word(0x0100000c) + word(0) + word(28) + word(UInt32(thin.count)) + word(0))
        fat.append(thin)
        precondition(ShadowCodeSignature.entitlements(data: fat)?["application-identifier"] as? String == "TEST.example.app")
        for size in 0 ..< thin.count {
            precondition(ShadowCodeSignature.entitlements(data: Data(thin.prefix(size))) == nil)
        }
        var broken = thin
        broken.replaceSubrange(44 ..< 48, with: [255, 255, 255, 255])
        precondition(ShadowCodeSignature.entitlements(data: broken) == nil)
        print("Code signature: thin/fat fixtures, truncation and bounds checks passed")
    }
}
