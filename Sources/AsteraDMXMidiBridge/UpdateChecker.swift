import AX1Core
import Foundation

enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/jonpikereally/AsteraDMXMidiBridge/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/jonpikereally/AsteraDMXMidiBridge/releases/latest")!

    enum CheckResult: Equatable, Sendable {
        case current(latest: String)
        case available(version: String, download: URL?)
        case noRelease
    }

    static func check(currentVersion: String) async throws -> CheckResult {
        try Task.checkCancellation()
        guard let installed = ReleaseVersion(currentVersion) else { throw CheckError.invalidInstalledVersion }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AsteraDMXMidiBridge", forHTTPHeaderField: "User-Agent")

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request, delegate: GitHubRedirects())
        } catch {
            try Task.checkCancellation()
            switch (error as? URLError)?.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw CheckError.timeout
            default: throw CheckError.network
            }
        }
        try Task.checkCancellation()
        return try evaluate(data: result.0, response: result.1, installed: installed)
    }

    private static func evaluate(data: Data, response: URLResponse, installed: ReleaseVersion) throws -> CheckResult {
        guard let response = response as? HTTPURLResponse else { throw CheckError.unexpectedResponse(nil) }
        switch response.statusCode {
        case 200:
            break
        case 404:
            return .noRelease
        case 429:
            throw CheckError.rateLimited
        case 403 where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            || response.value(forHTTPHeaderField: "Retry-After") != nil:
            throw CheckError.rateLimited
        default:
            throw CheckError.unexpectedResponse(response.statusCode)
        }

        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease, let latest = ReleaseVersion(release.tagName) else {
            throw CheckError.invalidRelease
        }
        guard installed < latest else { return .current(latest: latest.text) }
        let download = AppUpdate.downloadURL(assets: (release.assets ?? []).map { (name: $0.name, url: $0.browserDownloadURL) })
        return .available(version: latest.text, download: download)
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private final class GitHubRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, url.scheme == "https", url.host == "api.github.com",
                  url.port == nil || url.port == 443, url.user == nil, url.password == nil else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    private enum CheckError: LocalizedError {
        case invalidInstalledVersion, network, timeout, rateLimited, unexpectedResponse(Int?), invalidRelease

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion:
                return "AX1-401 · This app build has an invalid version number."
            case .network:
                return "AX1-402 · Couldn’t reach GitHub to check for updates."
            case .timeout:
                return "AX1-403 · The update check took too long. Try again."
            case .rateLimited:
                return "AX1-404 · GitHub’s request limit was reached. Try again later."
            case .unexpectedResponse(let status):
                let detail = status.map { " (HTTP \($0))" } ?? ""
                return "AX1-405 · GitHub returned an unexpected response\(detail)."
            case .invalidRelease:
                return "AX1-406 · GitHub returned invalid release information."
            }
        }
    }
}
