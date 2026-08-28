import Foundation

// MARK: - Dữ liệu patch nhúng (tạm thời để trống)
let Aim_Body_FFTH_3105: [UInt8] = []
let Aim_Body_FFTH_3105_len = 0

let Aim_Body_FFMAX_3105: [UInt8] = []
let Aim_Body_FFMAX_3105_len = 0

let Aim_Neck_V1_FFTH_3105: [UInt8] = []
let Aim_Neck_V1_FFTH_3105_len = 0

let Aim_Neck_V1_FFMAX_3105: [UInt8] = []
let Aim_Neck_V1_FFMAX_3105_len = 0

let Aim_Neck_V2_FFTH_3105: [UInt8] = []
let Aim_Neck_V2_FFTH_3105_len = 0

let Aim_Neck_V2_FFMAX_3105: [UInt8] = []
let Aim_Neck_V2_FFMAX_3105_len = 0

let Magic_V4_FFTH_3105: [UInt8] = []
let Magic_V4_FFTH_3105_len = 0

let Magic_V4_FFMAX_3105: [UInt8] = []
let Magic_V4_FFMAX_3105_len = 0

enum EmbeddedPatchLoader {
    static func data(for feature: LocalPatchFeature, game: LocalGameVariant) -> Data? {
        switch (game, feature) {
        case (.freeFire, .aimBody):
            return Data(bytes: Aim_Body_FFTH_3105, count: Aim_Body_FFTH_3105_len)
        case (.freeFireMax, .aimBody):
            return Data(bytes: Aim_Body_FFMAX_3105, count: Aim_Body_FFMAX_3105_len)
        case (.freeFire, .aimNeckV1):
            return Data(bytes: Aim_Neck_V1_FFTH_3105, count: Aim_Neck_V1_FFTH_3105_len)
        case (.freeFireMax, .aimNeckV1):
            return Data(bytes: Aim_Neck_V1_FFMAX_3105, count: Aim_Neck_V1_FFMAX_3105_len)
        case (.freeFire, .aimNeckV2):
            return Data(bytes: Aim_Neck_V2_FFTH_3105, count: Aim_Neck_V2_FFTH_3105_len)
        case (.freeFireMax, .aimNeckV2):
            return Data(bytes: Aim_Neck_V2_FFMAX_3105, count: Aim_Neck_V2_FFMAX_3105_len)
        case (.freeFire, .magicV4):
            return Data(bytes: Magic_V4_FFTH_3105, count: Magic_V4_FFTH_3105_len)
        case (.freeFireMax, .magicV4):
            return Data(bytes: Magic_V4_FFMAX_3105, count: Magic_V4_FFMAX_3105_len)
        default:
            return nil
        }
    }
}

enum PatchAssetLoader {
    static func loadPatchData(for definition: LocalPatchDefinition) -> Data? {
        guard let game = LocalGameVariant(rawValue: definition.game.rawValue) else { return nil }
        return EmbeddedPatchLoader.data(for: definition.feature, game: game)
    }

    static func exists(for definition: LocalPatchDefinition) -> Bool {
        return loadPatchData(for: definition) != nil
    }

    static func availableFeatures(for game: LocalGameVariant) -> Set<LocalPatchFeature> {
        Set(LocalPatchFeature.allCases.filter { feature in
            guard let definition = LocalPatchDefinitions.definition(for: feature, game: game) else {
                return false
            }
            return exists(for: definition)
        })
    }
}
