import Foundation

/// The anonymous shopper ID sent as `anon_id`.
///
/// Stored in `UserDefaults`, not the Keychain: Keychain items survive an uninstall,
/// which would turn an anonymous ID into a persistent device identifier.
public enum SSCAnonID {
    public static let defaultsKey = "com.boldmetrics.ssc.anonId"

    /// The host's ID when it is a UUID, otherwise the stored ID (created on first use).
    /// Always lower-case, because the page lower-cases it too.
    public static func resolve(hostId: String? = nil, defaults: UserDefaults = .standard) -> String {
        if let hostId, let uuid = UUID(uuidString: hostId.trimmingCharacters(in: .whitespaces)) {
            return uuid.uuidString.lowercased()
        }
        return stored(defaults: defaults)
    }

    /// The ID kept in `defaults`, created on first call.
    public static func stored(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), let uuid = UUID(uuidString: existing) {
            return uuid.uuidString.lowercased()
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }

    /// Forgets the stored ID (for a "reset" in the host's privacy settings).
    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
