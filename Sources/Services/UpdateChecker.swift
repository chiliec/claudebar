import Foundation

struct UpdateChecker {
    static let repo = "chiliec/claudebar"
    static let currentVersion = "0.0.1"

    struct Release: Codable {
        let tagName: String
        let htmlUrl: String
    }

    static func checkForUpdate() async -> (version: String, url: String)? {
        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(Release.self, from: data) else { return nil }

        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        if compareVersions(latestVersion, isNewerThan: currentVersion) {
            return (latestVersion, release.htmlUrl)
        }
        return nil
    }

    static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}
