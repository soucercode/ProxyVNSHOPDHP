import Foundation
import UIKit
import Darwin
import Combine

// MARK: - Global logger
class AppLog: ObservableObject {
    static let shared = AppLog()
    @Published var entries: [String] = []
    func append(_ msg: String) {
        DispatchQueue.main.async { self.entries.append(msg) }
        print("[CheatiOSVip] \(msg)")
    }
}
func log(_ msg: String) { AppLog.shared.append(msg) }

// MARK: - App Info
enum AppInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
    static var doubleVersion: Double {
        let v = versionTuple; return Double(v.major) + Double(v.minor) / 10.0
    }
    static var osBuild: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: value)
    }
    static var machineName: String {
        var s = utsname(); uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { id, e in
            guard let v = e.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }
    static var displayMachineName: String {
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machineName
#else
        return machineName
#endif
    }
    static var hardwareDisplayName: String {
        switch displayMachineName {
        case "iPhone8,1": return "iPhone 6s"
        case "iPhone8,2": return "iPhone 6s Plus"
        case "iPhone8,4": return "iPhone SE (1st gen)"
        case "iPhone9,1", "iPhone9,3": return "iPhone 7"
        case "iPhone9,2", "iPhone9,4": return "iPhone 7 Plus"
        case "iPhone10,1", "iPhone10,4": return "iPhone 8"
        case "iPhone10,2", "iPhone10,5": return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6": return "iPhone X"
        case "iPhone11,2": return "iPhone XS"
        case "iPhone11,4", "iPhone11,6": return "iPhone XS Max"
        case "iPhone11,8": return "iPhone XR"
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        case "iPhone12,8": return "iPhone SE (2nd gen)"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,6": return "iPhone SE (3rd gen)"
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        case "iPhone17,5": return "iPhone 16e"

        // iPad mini
        case "iPad11,1", "iPad11,2": return "iPad mini (5th gen)"
        case "iPad14,1", "iPad14,2": return "iPad mini (6th gen)"

        // iPad Air
        case "iPad11,3", "iPad11,4": return "iPad Air (3rd gen)"
        case "iPad13,1", "iPad13,2": return "iPad Air (4th gen)"
        case "iPad13,16", "iPad13,17": return "iPad Air (5th gen)"
        case "iPad14,8", "iPad14,9": return "iPad Air 11\" (M2)"
        case "iPad14,10", "iPad14,11": return "iPad Air 13\" (M2)"

        // iPad (base)
        case "iPad11,6", "iPad11,7": return "iPad (8th gen)"
        case "iPad12,1", "iPad12,2": return "iPad (9th gen)"
        case "iPad13,18", "iPad13,19": return "iPad (10th gen)"

        // iPad Pro
        case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": return "iPad Pro 11\" (1st gen)"
        case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": return "iPad Pro 12.9\" (3rd gen)"
        case "iPad8,9", "iPad8,10": return "iPad Pro 11\" (2nd gen)"
        case "iPad8,11", "iPad8,12": return "iPad Pro 12.9\" (4th gen)"
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro 11\" (3rd gen)"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro 12.9\" (5th gen)"
        case "iPad14,3", "iPad14,4": return "iPad Pro 11\" (4th gen)"
        case "iPad14,5", "iPad14,6": return "iPad Pro 12.9\" (6th gen)"
        case "iPad16,3", "iPad16,4": return "iPad Pro 11\" (M4)"
        case "iPad16,5", "iPad16,6": return "iPad Pro 13\" (M4)"

        default: return displayMachineName
        }
    }
    static var isHomeButton: Bool {
        let sel = NSSelectorFromString("_hasHomeButton")
        return UIDevice.responds(to: sel) && (UIDevice.perform(sel)?.takeUnretainedValue() as? Bool ?? false)
    }
}

// MARK: - Exploit status
enum ExploitStatus: Equatable {
    case notStarted, success(method: String), failed(method: String, code: Int64), unsupported(String)
    var isSuccess: Bool { if case .success = self { return true }; return false }
    var displayText: String {
        switch self {
        case .notStarted: return "Not attempted"
        case .success(let m): return "OK via \(m)"
        case .failed(let m, let c): return "FAILED \(m) (\(c))"
        case .unsupported(let m): return "Unsupported: \(m)"
        }
    }
}

enum AppPaths {
    static var backups: String {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let b = u.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b.path
    }

    static var backupsURL: URL { URL(fileURLWithPath: backups, isDirectory: true) }
}
