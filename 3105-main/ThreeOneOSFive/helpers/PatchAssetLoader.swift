import Foundation

enum PatchAssetLoader {
    static func url(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: definition.resourceName, withExtension: "3105")
    }

    static func exists(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> Bool {
        url(for: definition, bundle: bundle) != nil
    }
}
