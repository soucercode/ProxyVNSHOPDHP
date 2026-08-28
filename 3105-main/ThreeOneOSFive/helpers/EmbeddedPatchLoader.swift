import Foundation

// MARK: - Dữ liệu patch nhúng (sẽ được thay thế bằng xxd)
// Sau khi chạy xxd, copy các mảng byte vào đây

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
