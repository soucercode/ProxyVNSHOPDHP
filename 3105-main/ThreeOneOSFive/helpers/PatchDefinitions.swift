import Foundation

enum LocalGameVariant: String, CaseIterable, Identifiable {
    case freeFire = "com.dts.freefireth"
    case freeFireMax = "com.dts.freefiremax"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freeFire: return "Free Fire"
        case .freeFireMax: return "Free Fire Max"
        }
    }

    var iconAssetName: String {
        switch self {
        case .freeFire: return "FreeFire"
        case .freeFireMax: return "FreeFireMax"
        }
    }
}

enum LocalPatchFeature: String, CaseIterable, Identifiable {
    case aimBody = "Proxy Aim Body"
    case aimNeckV1 = "Proxy Aim Neck V1"
    case aimNeckV2 = "Proxy Aim Neck V2"
    case magicV4 = "Magic V4"
    case aimDrag = "Proxy Aim Drag"
    case location = "Định Vị"
    var id: String { rawValue }
}

struct LocalPatchDefinition: Identifiable {
    let id: String
    let feature: LocalPatchFeature
    let game: LocalGameVariant
    let resourceName: String
}

enum LocalPatchDefinitions {
    static let all: [LocalPatchDefinition] = [
        .init(id: "ffth.body", feature: .aimBody, game: .freeFire, resourceName: "Aim Body FFTH"),
        .init(id: "ffmax.body", feature: .aimBody, game: .freeFireMax, resourceName: "Aim Body FFMAX"),
        .init(id: "ffth.v1", feature: .aimNeckV1, game: .freeFire, resourceName: "Aim Neck V1 FFTH"),
        .init(id: "ffmax.v1", feature: .aimNeckV1, game: .freeFireMax, resourceName: "Aim Neck V1 FFMAX"),
        .init(id: "ffth.v2", feature: .aimNeckV2, game: .freeFire, resourceName: "Aim Neck V2 FFTH"),
        .init(id: "ffmax.v2", feature: .aimNeckV2, game: .freeFireMax, resourceName: "Aim Neck V2 FFMAX"),
        .init(id: "ffth.magic", feature: .magicV4, game: .freeFire, resourceName: "Magic V4 FFTH"),
        .init(id: "ffmax.magic", feature: .magicV4, game: .freeFireMax, resourceName: "Magic V4 FFMAX")
    ]

    static func definition(for feature: LocalPatchFeature, game: LocalGameVariant) -> LocalPatchDefinition? {
        all.first { $0.feature == feature && $0.game == game }
    }
}
