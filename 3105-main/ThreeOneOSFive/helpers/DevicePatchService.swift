import CryptoKit
import Foundation

/// Safe demo patch service.
///
/// This build never resolves or writes to another app's container.  All patch data is
/// written under this app's own Application Support directory:
///   Application Support/ProxySHOPDHP/DemoGameData/<bundleID>/...
///
/// The UI therefore exercises the complete "select file -> apply patch -> verify -> success"
/// flow without modifying Free Fire's real sandbox.
enum DevicePatchService {
    private struct DemoReceipt: Codable {
        let projectID: UUID
        let timestamp: Date
        let files: [DemoReceiptFile]
    }

    private struct DemoReceiptFile: Codable {
        let bundleID: String
        let relativePath: String
        let backupName: String?
        let originalExisted: Bool
    }

    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ProxySHOPDHP/DemoGameData", isDirectory: true)
    }

    private static var receiptRoot: URL {
        root.appendingPathComponent("Receipts", isDirectory: true)
    }

    private static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
    }

    private static func safeBundleID(_ value: String) throws -> String {
        try PatchPathValidator.canonicalBundleIdentifier(value)
    }

    private static func safeRelativePath(_ value: String) throws -> String {
        try PatchPathValidator.canonicalRelativePath(value)
    }

    private static func targetURL(bundleID: String, relativePath: String) throws -> URL {
        let id = try safeBundleID(bundleID)
        let path = try safeRelativePath(relativePath)
        let gameRoot = root.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        let target = gameRoot.appendingPathComponent(path, isDirectory: false).standardizedFileURL
        guard target.path.hasPrefix(gameRoot.path + "/") else {
            throw PatchPackageError.unsafeTargetPath
        }
        return target
    }

    private static func backupURL(projectID: UUID, index: Int) -> URL {
        receiptRoot.appendingPathComponent("\(projectID.uuidString)-\(index).bak")
    }

    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        try ensureDirectories()
        var receiptFiles: [DemoReceiptFile] = []

        for (index, rule) in project.rules.enumerated() {
            guard rule.hasReplacement else { throw PatchPackageError.invalidProject }
            let target = try targetURL(bundleID: rule.bundleID, relativePath: rule.relativePath)
            let fm = FileManager.default
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)

            let existed = fm.fileExists(atPath: target.path)
            var backupName: String?
            if existed {
                let backup = backupURL(projectID: project.id, index: index)
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: target, to: backup)
                backupName = backup.lastPathComponent
            }

            try rule.replacementData.write(to: target, options: .atomic)
            guard fm.fileExists(atPath: target.path) else { throw PatchPackageError.applyFailed }

            let written = try Data(contentsOf: target)
            guard written == rule.replacementData else { throw PatchPackageError.applyFailed }
            receiptFiles.append(DemoReceiptFile(
                bundleID: rule.bundleID,
                relativePath: rule.relativePath,
                backupName: backupName,
                originalExisted: existed
            ))
        }

        let demoReceipt = DemoReceipt(projectID: project.id, timestamp: Date(), files: receiptFiles)
        let journal = receiptRoot.appendingPathComponent("\(project.id.uuidString).json")
        let data = try JSONEncoder().encode(demoReceipt)
        try data.write(to: journal, options: .atomic)

        return PatchTransactionReceipt(id: project.id, projectID: project.id, journalURL: journal)
    }

    /// Applies a bundled patch payload to this app's private demo workspace.
    /// This keeps the patch flow self-contained without writing into another app's sandbox.
    static func applyBundledDemoPatch(resourceName: String, featureName: String) throws -> PatchTransactionReceipt {
        try ensureDirectories()
        _ = featureName

        guard let sourceURL = Bundle.main.url(forResource: resourceName, withExtension: nil) else {
            throw PatchPackageError.invalidProject
        }

        let projectID = UUID()
        let demoBundleID = "com.shopdhp.proxyshopdhp.demo"
        let relativePath = "Patches/\(resourceName)"
        let target = try targetURL(bundleID: demoBundleID, relativePath: relativePath)
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backup = fm.fileExists(atPath: target.path)
            ? backupURL(projectID: projectID, index: 0)
            : nil
        if let backup {
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: target, to: backup)
        }

        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.copyItem(at: sourceURL, to: target)

        guard fm.fileExists(atPath: target.path),
              try Data(contentsOf: target) == Data(contentsOf: sourceURL) else {
            throw PatchPackageError.applyFailed
        }

        let receiptFiles = [
            DemoReceiptFile(
                bundleID: demoBundleID,
                relativePath: relativePath,
                backupName: backup?.lastPathComponent,
                originalExisted: backup != nil
            )
        ]
        let receipt = DemoReceipt(projectID: projectID, timestamp: Date(), files: receiptFiles)
        let journal = receiptRoot.appendingPathComponent("\(projectID.uuidString).json")
        try JSONEncoder().encode(receipt).write(to: journal, options: .atomic)

        return PatchTransactionReceipt(id: projectID, projectID: projectID, journalURL: journal)
    }

    static func restore(receipt: PatchTransactionReceipt) throws {
        guard FileManager.default.fileExists(atPath: receipt.journalURL.path) else {
            throw PatchPackageError.restoreFailed
        }
        let data = try Data(contentsOf: receipt.journalURL)
        let demoReceipt = try JSONDecoder().decode(DemoReceipt.self, from: data)
        let fm = FileManager.default

        for file in demoReceipt.files {
            let target = try targetURL(bundleID: file.bundleID, relativePath: file.relativePath)
            if let backupName = file.backupName {
                let backup = receiptRoot.appendingPathComponent(backupName)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: backup, to: target)
            } else {
                try? fm.removeItem(at: target)
            }
        }

        try? fm.removeItem(at: receipt.journalURL)
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        let journal = receiptRoot.appendingPathComponent("\(projectID.uuidString).json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return nil }
        return PatchTransactionReceipt(id: projectID, projectID: projectID, journalURL: journal)
    }

    static func setRuleState(_ isOn: Bool, rule: PatchRule) throws {
        try ensureDirectories()
        let target = try targetURL(bundleID: rule.bundleID, relativePath: rule.relativePath)
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        if isOn {
            try rule.replacementData.write(to: target, options: .atomic)
        } else if let original = rule.originalData {
            try original.write(to: target, options: .atomic)
        } else {
            throw PatchPackageError.applyFailed
        }

        let expected = isOn ? rule.replacementData : (rule.originalData ?? Data())
        guard (try? Data(contentsOf: target)) == expected else {
            throw PatchPackageError.applyFailed
        }
    }

    static func currentRuleState(for rule: PatchRule) -> Bool? {
        guard let target = try? targetURL(bundleID: rule.bundleID, relativePath: rule.relativePath),
              let data = try? Data(contentsOf: target) else { return false }
        return data == rule.replacementData
    }

    /// Used by the demo UI to display where the simulated patch was written.
    static func demoStorageLocation() -> URL {
        root
    }
}
