import CryptoKit
import Foundation

struct RemotePatchSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let version: String
    let fileName: String
    let sizeBytes: Int64
    let sha256: String
    let createdAt: String
    let gameId: String?
}

struct RemoteGameSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String
    let bannerColor: String
    let iconPath: String?
    let createdAt: String

    var iconURL: URL? {
        guard let iconPath else { return nil }
        return PatchHubService.baseURL.appendingPathComponent(String(iconPath.dropFirst()))
    }
}

enum PatchHubError: Error {
    case invalidResponse
    case checksumMismatch
}

enum PatchHubService {
    static let baseURL = URL(string: "https://patches.cheatiosvip.net")!

    static func fetchGames() async throws -> [RemoteGameSummary] {
        let url = baseURL.appendingPathComponent("api/games")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PatchHubError.invalidResponse
        }
        struct Envelope: Decodable { let games: [RemoteGameSummary] }
        return try JSONDecoder().decode(Envelope.self, from: data).games
    }

    static func fetchPatches() async throws -> [RemotePatchSummary] {
        let url = baseURL.appendingPathComponent("api/patches")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PatchHubError.invalidResponse
        }
        struct Envelope: Decodable { let patches: [RemotePatchSummary] }
        return try JSONDecoder().decode(Envelope.self, from: data).patches
    }

    static func downloadPatch(_ summary: RemotePatchSummary) async throws -> URL {
        let url = baseURL.appendingPathComponent("api/patches/\(summary.id)/download")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PatchHubError.invalidResponse
        }
        guard try digest(of: tempURL) == summary.sha256.lowercased() else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PatchHubError.checksumMismatch
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("3105")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private static func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }
}
