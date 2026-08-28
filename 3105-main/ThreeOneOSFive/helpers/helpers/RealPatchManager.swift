import Foundation

enum RealPatchManager {
    private static let fm = FileManager.default
    
    private static func writeLog(_ message: String) {
        guard let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return
        }
        let logPath = (documentsPath as NSString).appendingPathComponent("patch_debug.log")
        let timestamp = Date().description
        let logEntry = "[\(timestamp)] \(message)\n"
        
        var existing = ""
        if let old = try? String(contentsOfFile: logPath, encoding: .utf8) {
            existing = old
        }
        let fullLog = existing + logEntry
        try? fullLog.write(toFile: logPath, atomically: true, encoding: .utf8)
        print(logEntry)
    }
    
    static func getContainerPath(bundleID: String) -> String? {
        writeLog("🔍 getContainerPath: \(bundleID)")
        var error: NSString?
        guard let path = MCMActivateContainerPath(2, bundleID, false, &error) else {
            writeLog("❌ MCM failed: \(error ?? "unknown")")
            return nil
        }
        writeLog("✅ Container: \(path)")
        return path
    }
    
    static func applyPatchToSingleGame(
        definition: PatchDefinition,
        gameBundleID: String,
        isOn: Bool
    ) -> Bool {
        writeLog("========================================")
        writeLog("📦 \(definition.featureName) -> \(gameBundleID), isOn=\(isOn)")
        
        guard let containerPath = getContainerPath(bundleID: gameBundleID) else {
            writeLog("❌ KHÔNG CÓ CONTAINER")
            return false
        }
        
        let fullTargetPath = (containerPath as NSString).appendingPathComponent(definition.targetPath)
        let backupPath = fullTargetPath + ".backup"
        writeLog("📁 Target: \(fullTargetPath)")
        
        let targetExists = fm.fileExists(atPath: fullTargetPath)
        writeLog("📄 File đích tồn tại: \(targetExists)")
        
        guard let (project, _) = try? PatchAssetLoader.load(
            definition: definition,
            gameBundleID: gameBundleID
        ) else {
            writeLog("❌ Không load được .3105 cho \(gameBundleID)")
            return false
        }
        
        guard let rule = project.rules.first else {
            writeLog("❌ KHÔNG CÓ RULE")
            return false
        }
        
        writeLog("📦 replacementData size: \(rule.replacementData.count) bytes")
        
        if isOn {
            writeLog("🟢 BẬT PATCH - GHI ĐÈ FILE ĐÍCH")
            
            guard !rule.replacementData.isEmpty else {
                writeLog("❌ replacementData RỖNG")
                return false
            }
            
            if targetExists && !fm.fileExists(atPath: backupPath) {
                do {
                    try fm.copyItem(atPath: fullTargetPath, toPath: backupPath)
                    writeLog("✅ Backup OK")
                } catch {
                    writeLog("❌ Backup FAIL: \(error)")
                    return false
                }
            }
            
            do {
                try rule.replacementData.write(to: URL(fileURLWithPath: fullTargetPath), options: .atomic)
                writeLog("✅ PATCH ĐÃ GHI ĐÈ: \(fullTargetPath)")
                
                let written = try? Data(contentsOf: URL(fileURLWithPath: fullTargetPath))
                if written == rule.replacementData {
                    writeLog("✅ VERIFY OK - THÀNH CÔNG")
                    return true
                } else {
                    writeLog("❌ VERIFY FAIL")
                    return false
                }
            } catch {
                writeLog("❌ GHI PATCH FAIL: \(error)")
                return false
            }
        } else {
            writeLog("🔴 TẮT PATCH - KHÔI PHỤC")
            
            guard fm.fileExists(atPath: backupPath) else {
                writeLog("⚠️ KHÔNG CÓ BACKUP")
                return false
            }
            
            do {
                try fm.copyItem(atPath: backupPath, toPath: fullTargetPath)
                try fm.removeItem(atPath: backupPath)
                writeLog("✅ RESTORED")
                return true
            } catch {
                writeLog("❌ RESTORE FAIL: \(error)")
                return false
            }
        }
    }
    
    static func applyPatchFromDefinition(
        definition: PatchDefinition,
        gameBundleID: String,
        isOn: Bool
    ) -> Bool {
        writeLog("========================================")
        writeLog("🚀 \(definition.featureName) -> \(gameBundleID), isOn=\(isOn)")
        
        guard gameBundleID == "com.dts.freefireth" || gameBundleID == "com.dts.freefiremax" else {
            writeLog("❌ GAME KHÔNG HỖ TRỢ")
            return false
        }
        
        let result = applyPatchToSingleGame(
            definition: definition,
            gameBundleID: gameBundleID,
            isOn: isOn
        )
        
        writeLog("📊 Kết quả: \(result ? "✅ THÀNH CÔNG" : "❌ THẤT BẠI")")
        return result
    }
}
