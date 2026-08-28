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
            assetNameFFTH: "Aim Body FFTH",
            assetNameFFMAX: "Aim Body FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "aim_neck_v1",
            featureName: "Proxy Aim Neck V1",
            assetNameFFTH: "Aim Neck V1 FFTH",
            assetNameFFMAX: "Aim Neck V1 FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "aim_neck_v2",
            featureName: "Proxy Aim Neck V2",
            assetNameFFTH: "Aim Neck V2 FFTH",
            assetNameFFMAX: "Aim Neck V2 FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        ),
        PatchDefinition(
            id: "magic_v4",
            featureName: "Magic V4",
            assetNameFFTH: "Magic V4 FFTH",
            assetNameFFMAX: "Magic V4 FFMAX",
            targetPath: "Documents/contentcache/Compulsory/ios/gameassetbundles/cache_res.CfnFf59sr1SbsqQ6JqTKsEusjKs~3D"
        )
    ]
    
    static func forFeatureName(_ name: String) -> PatchDefinition? {
        all.first { $0.featureName == name }
    }
}
