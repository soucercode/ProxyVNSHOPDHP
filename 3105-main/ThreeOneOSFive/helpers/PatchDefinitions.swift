import Foundation

struct PatchDefinition: Identifiable {
    let id: String
    let featureName: String
    let assetNameFFTH: String
    let assetNameFFMAX: String
    let targetPath: String
}

enum PatchDefinitions {
    static let all: [PatchDefinition] = [
        PatchDefinition(
            id: "aim_body",
            featureName: "Proxy Aim Body",
            assetNameFFTH: "AimBodyFFTH",
            assetNameFFMAX: "AimBodyFFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "aim_neck_v1",
            featureName: "Proxy Aim Neck V1",
            assetNameFFTH: "AimNeckV1FFTH",
            assetNameFFMAX: "AimNeckV1FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "aim_neck_v2",
            featureName: "Proxy Aim Neck V2",
            assetNameFFTH: "AimNeckV2FFTH",
            assetNameFFMAX: "AimNeckV2FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "magic_v4",
            featureName: "Magic V4",
            assetNameFFTH: "MagicV4FFTH",
            assetNameFFMAX: "MagicV4FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        )
    ]
    
    static func forFeatureName(_ name: String) -> PatchDefinition? {
        all.first { $0.featureName == name }
    }
}
