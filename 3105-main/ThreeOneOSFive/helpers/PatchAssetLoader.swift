import Foundation

/// Resolves patch resources that are bundled with this app.
/// This loader only inspects the app bundle; it does not access another app's container or modify another process.
enum PatchAssetLoader {
    static func url(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: definition.resourceName, withExtension: "3105") {
            return url
        }

        // Also support projects that keep the resources under Patches/ after packaging.
        if let patchesURL = bundle.url(forResource: "Patches", withExtension: nil) {
            let candidate = patchesURL.appendingPathComponent(definition.resourceName + ".3105")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func exists(for definition: LocalPatchDefinition, bundle: Bundle = .main) -> Bool {
        url(for: definition, bundle: bundle) != nil
    }

    static func availableFeatures(for game: LocalGameVariant, bundle: Bundle = .main) -> Set<LocalPatchFeature> {
        Set(LocalPatchFeature.allCases.filter { feature in
            guard let definition = LocalPatchDefinitions.definition(for: feature, game: game) else {
                return false
            }
            return exists(for: definition, bundle: bundle)
        })
    }
}
