import Foundation

/// UI support policy for Proxy SHOP DHP. This only reports compatibility in the app UI.
enum ExploitSupportPolicy {
    static let supportedRanges = [
        "16–16.7.x",
        "17–17.7.x",
        "18–18.7.1",
        "26–26.6.1",
        "27 beta 1, 2, 3, 4"
    ]

    static var verifiedIOS26Range: String { "26.0–26.6.1" }
    // iOS 27 beta 1–4 are intentionally treated as supported by the
    // compatibility gate. Apple changes build identifiers between beta releases,
    // so the app uses the OS major/minor plus an optional beta marker instead of
    // hard-coding a single build string.
    static let supportedIOS27Betas = Set([1, 2, 3, 4])

    static var isCurrentOSSupported: Bool {
        let v = AppInfo.versionTuple
        return isSupported(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
    }

    static var currentSupportLabel: String {
        let v = AppInfo.versionTuple
        if v.major == 27 { return "iOS 27 beta" }
        return "iOS \(v.major).\(v.minor).\(v.patch)"
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        switch major {
        case 16:
            return minor >= 0 && minor <= 7
        case 17:
            return minor >= 0 && minor <= 7
        case 18:
            return minor >= 0 && (minor < 7 || (minor == 7 && patch <= 1))
        case 26:
            return minor >= 0 && (minor < 6 || (minor == 6 && patch <= 1))
        case 27:
            // iOS 27 beta builds are not exposed by UIKit as a stable
            // "beta 1/2/3/4" string. Keep the compatibility gate permissive for
            // 27.0 prerelease builds; production/unsupported major versions
            // remain blocked by the default branch.
            let lower = build.lowercased()
            if lower.contains("beta") {
                return true
            }
            return minor == 0
        default:
            return false
        }
    }

    static func iOS27BetaNumber(for build: String) -> Int? {
        let lower = build.lowercased()
        let patterns = [
            #"beta[-_ ]?([1-4])"#,
            #"b([1-4])$"#
        ]
        for pattern in patterns {
            if let range = lower.range(of: pattern, options: .regularExpression) {
                let value = String(lower[range])
                    .filter { $0.isNumber }
                if let number = Int(value), supportedIOS27Betas.contains(number) {
                    return number
                }
            }
        }
        return nil
    }
}
