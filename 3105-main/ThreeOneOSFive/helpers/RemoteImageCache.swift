import CryptoKit
import Foundation
import UIKit

/// Persists downloaded remote images (game icons) to disk so they still show after the first
/// successful load, even with no network on later launches. Deliberately not the standard
/// URLCache-backed behavior: a plain URLRequest with no explicit cache policy fails outright
/// when offline instead of falling back to a cached response, which is exactly the gap here.
enum RemoteImageCache {
    private static let directory: URL = {
        let base = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func localFileURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    static func cachedImage(for remoteURL: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: localFileURL(for: remoteURL)) else { return nil }
        return UIImage(data: data)
    }

    static func fetchAndCache(_ remoteURL: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: remoteURL),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let image = UIImage(data: data)
        else {
            return nil
        }
        try? data.write(to: localFileURL(for: remoteURL), options: .atomic)
        return image
    }
}
