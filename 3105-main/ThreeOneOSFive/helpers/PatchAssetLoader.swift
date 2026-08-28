import Foundation

enum PatchAssetLoader {
    static func load(
        definition: PatchDefinition,
        gameBundleID: String
    ) throws -> (project: PatchProject, data: Data) {
        
        let assetName: String
        if gameBundleID == "com.dts.freefireth" {
            assetName = definition.assetNameFFTH
        } else if gameBundleID == "com.dts.freefiremax" {
            assetName = definition.assetNameFFMAX
        } else {
            throw NSError(
                domain: "PatchAssetLoader",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Game không được hỗ trợ: \(gameBundleID)"]
            )
        }
        
        // Tìm file .3105 trong bundle
        guard let url = Bundle.main.url(
            forResource: assetName,
            withExtension: "3105"
        ) else {
            // Thử tìm trong thư mục Patches/ nếu không thấy
            guard let urlInPatches = Bundle.main.url(
                forResource: assetName,
                withExtension: "3105",
                subdirectory: "Patches"
            ) else {
                throw NSError(
                    domain: "PatchAssetLoader",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy \(assetName).3105"]
                )
            }
            let data = try Data(contentsOf: urlInPatches)
            let decoded = try PatchPackageCodec.decode(data, password: nil)
            return (decoded.project, data)
        }
        
        let data = try Data(contentsOf: url)
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        return (decoded.project, data)
    }
}
