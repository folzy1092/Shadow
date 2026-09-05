import Foundation

/// Reads the executable's embedded XML entitlement blob, never a provisioning
/// profile. This is inspection, not signature verification or a kernel query.
/// DER-only signatures are deliberately reported as unavailable.
public enum ShadowCodeSignature {
    public static func entitlements(executableURL: URL?) -> [String: Any]? {
        guard let url = executableURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return self.entitlements(data: data)
    }

    public static func entitlements(data: Data) -> [String: Any]? {
        func word(_ offset: Int, little: Bool = false) -> UInt32? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let bytes = (0 ..< 4).map { UInt32(data[offset + $0]) }
            if little { return bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24 }
            return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
        }

        var base = 0
        var end = data.count
        if word(0) == 0xcafebabe {
            guard let count = word(4), count > 0, count <= 64 else { return nil }
            var selected: (Int, Int)?
            for i in 0 ..< Int(count) {
                let entry = 8 + i * 20
                guard let cpu = word(entry), let offset = word(entry + 8), let size = word(entry + 12) else { return nil }
                if selected == nil || cpu == 0x0100000c {
                    selected = (Int(offset), Int(size))
                }
                if cpu == 0x0100000c { break }
            }
            guard let slice = selected, slice.0 <= data.count, slice.1 <= data.count - slice.0 else { return nil }
            base = slice.0
            end = base + slice.1
        }
        guard let magic = word(base), [UInt32(0xcffaedfe), 0xcefaedfe, 0xfeedfacf, 0xfeedface].contains(magic) else { return nil }
        let little = magic == 0xcffaedfe || magic == 0xcefaedfe
        let headerSize = (magic == 0xcffaedfe || magic == 0xfeedfacf) ? 32 : 28
        guard let count = word(base + 16, little: little), let commandBytes = word(base + 20, little: little), count <= 65536 else { return nil }
        var position = base + headerSize
        guard position <= end, Int(commandBytes) <= end - position else { return nil }
        let commandsEnd = position + Int(commandBytes)
        for _ in 0 ..< Int(count) {
            guard position <= commandsEnd - 8, let command = word(position, little: little), let size = word(position + 4, little: little), size >= 8, Int(size) <= commandsEnd - position else { return nil }
            if command == 0x1d {
                guard size >= 16, let offset = word(position + 8, little: little), let length = word(position + 12, little: little) else { return nil }
                let signature = base + Int(offset)
                guard signature <= end, length >= 12, Int(length) <= end - signature, word(signature) == 0xfade0cc0,
                      let blobLength = word(signature + 4), blobLength >= 12, blobLength <= length,
                      let slots = word(signature + 8), slots <= (blobLength - 12) / 8 else { return nil }
                for index in 0 ..< Int(slots) {
                    guard let relative = word(signature + 12 + index * 8 + 4), relative <= blobLength - 8 else { return nil }
                    let blob = signature + Int(relative)
                    guard let size = word(blob + 4), size >= 8, size <= blobLength - relative else { return nil }
                    if word(blob) == 0xfade7171 {
                        let xml = data.subdata(in: blob + 8 ..< blob + Int(size))
                        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)) as? [String: Any]
                    }
                }
                return nil
            }
            position += Int(size)
        }
        return nil
    }
}
