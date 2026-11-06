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

        // The request frame must match m1ddc's byte for byte: message length 0x82,
        // command 0x01, the VCP code, then the checksum over 0x6E^0x51^message bytes.
        precondition(DDC.vcpRequest(.brightness) == [0x82, 0x01, 0x10, 0xAC],
                     "the Get VCP request for brightness must be 82 01 10 AC")
        precondition(DDC.vcpRequest(.volume) == [0x82, 0x01, 0x62, 0xDE],
                     "the Get VCP request for volume must be 82 01 62 DE")
        for code in VCP.allCases {
            let request = DDC.vcpRequest(code)
            precondition(request.count == 4 && request[0] == 0x82 && request[1] == 0x01 && request[2] == code.rawValue,
                         "malformed request frame for \(code)")
            precondition(request.prefix(3).reduce(UInt8(0x6E ^ 0x51), ^) == request[3],
                         "bad request checksum for \(code)")
        }

        // A real reply captured from a Dell U2720QM, and the reply a single request
        // write used to produce (the old frame's tail still in the read buffer).
        let real = [UInt8]([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x8B, 0x04])
        let parsedReal = DDC.decodeVCPReply(real, code: .brightness)
        precondition(parsedReal?.current == 75, "the real luminance reply must decode to 75")
        precondition(parsedReal?.max == 100, "the real luminance reply must decode to a maximum of 100")
        let stale = [UInt8]([0x6E, 0x80, 0xBE, 0x00, 0x01, 0x00, 0x00, 0x00, 0x07, 0x1A, 0x01, 0x04])
        precondition(DDC.decodeVCPReply(stale, code: .brightness) == nil,
                     "a stale read buffer must not be accepted as a reply")

        // The input-source shortcut toggles between a pair of inputs.
        let pair = [0x1B, 0x11]  // USB-C and HDMI 1
        precondition(DDC.toggleTarget(current: 0x1B, pair: pair) == 0x11, "must switch to the other input")
        precondition(DDC.toggleTarget(current: 0x11, pair: pair) == 0x1B, "must switch back")
        precondition(DDC.toggleTarget(current: 0x0F, pair: pair) == 0x1B, "an input outside the pair goes to the first of it")
        precondition(DDC.toggleTarget(current: nil, pair: pair) == nil, "without a current input there is no target")
        precondition(DDC.toggleTarget(current: 0x1B, pair: [0x1B]) == nil, "one input alone is not a pair")

        print("DDC/CI 帧解析测试全部通过（无需连接显示器）")
    }
}
