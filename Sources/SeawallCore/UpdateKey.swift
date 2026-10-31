import Foundation

/// Sparkle's public EdDSA key from Info.plist (`SUPublicEDKey`). Sparkle refuses to start
/// with a key that isn't one, and says so in an alert, so a build still carrying the
/// placeholder runs with updates off instead.
public enum UpdateKey {
    /// An Ed25519 public key is 32 bytes; `generate_keys` prints it as 44 characters of base64.
    public static func isUsable(_ key: String?) -> Bool {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }
}
