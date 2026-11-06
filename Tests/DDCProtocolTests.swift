// Offline regression tests for DDC/CI VCP responses.
// These tests never open a monitor or send any I²C command.
import Foundation

@main
struct DDCProtocolTests {
    static func main() {
        // 12-byte IOAVServiceReadI2C reply: an 11-byte MCCS frame plus padding.
        var valid: [UInt8] = [
            0x6E, 0x88, 0x02, 0x00, VCP.brightness.rawValue,
            0x00, 0x00, 0x64, 0x00, 0x4B, 0x00, 0x00
        ]
        valid[10] = valid[..<10].reduce(UInt8(0x50), ^)
        let parsed = DDC.decodeVCPReply(valid, code: .brightness)
        precondition(parsed?.current == 75, "brightness must decode to 75")
        precondition(parsed?.max == 100, "maximum brightness must decode to 100")

        var badChecksum = valid
        badChecksum[10] ^= 1
        precondition(DDC.decodeVCPReply(badChecksum, code: .brightness) == nil,
                     "corrupted checksums must not be accepted")
        var rejected = valid
        rejected[3] = 1
        precondition(DDC.decodeVCPReply(rejected, code: .brightness) == nil,
                     "unsupported-feature replies must not be accepted")
        precondition(DDC.decodeVCPReply(valid, code: .contrast) == nil,
                     "a different VCP code must not be mistaken for brightness")
        precondition(DDC.decodeVCPReply(Array(valid.prefix(10)), code: .brightness) == nil,
                     "truncated replies must not be accepted")

        print("DDC/CI 帧解析测试全部通过（无需连接显示器）")
    }
}
