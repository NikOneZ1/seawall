import Foundation
import Testing
@testable import SeawallCore

struct UpdateKeyTests {
    @Test func realKeyIsUsable() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        #expect(key.count == 44)
        #expect(UpdateKey.isUsable(key))
        #expect(UpdateKey.isUsable("  \(key)\n"))
    }

    @Test func theKeyInInfoPlistIsUsable() {
        // Resources/Info.plist on main (generate_keys, account com.nikitaverba.Seawall).
        #expect(UpdateKey.isUsable("PUrEyEZBVx5FJ7UEz2y/OAbMLDaUNKp4DCeFdwd82Bs="))
    }

    @Test func placeholderAndJunkAreNot() {
        #expect(!UpdateKey.isUsable(nil))
        #expect(!UpdateKey.isUsable(""))
        #expect(!UpdateKey.isUsable("REPLACE_WITH_PUBLIC_KEY_FROM_GENERATE_KEYS"))
        // Valid base64, wrong length: a DSA key or a truncated paste.
        #expect(!UpdateKey.isUsable(Data(repeating: 7, count: 31).base64EncodedString()))
        #expect(!UpdateKey.isUsable(Data(repeating: 7, count: 64).base64EncodedString()))
    }
}
