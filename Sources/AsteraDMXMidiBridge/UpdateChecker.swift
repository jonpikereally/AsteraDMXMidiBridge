import Foundation

enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/jonpikereally/AsteraDMXMidiBridge/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/jonpikereally/AsteraDMXMidiBridge/releases/latest")!

    enum CheckResult: Equatable, Sendable {
        case current(latest: String)
        case available(version: String)
        case noRelease
    }

    static func check(currentVersion: String) async throws -> CheckResult {
        try Task.checkCancellation()
        guard let installed = Version(currentVersion) else { throw CheckError.invalidInstalledVersion }

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

    private static func evaluate(data: Data, response: URLResponse, installed: Version) throws -> CheckResult {
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
              !release.draft, !release.prerelease, let latest = Version(release.tagName) else {
            throw CheckError.invalidRelease
        }
        return installed < latest ? .available(version: latest.text) : .current(latest: latest.text)
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }

    private struct Version: Comparable {
        let numbers: [Int]

        init?(_ tag: String) {
            let version = (tag.first == "v" || tag.first == "V") ? tag.dropFirst() : tag[...]
            let parts = version.split(separator: "+", omittingEmptySubsequences: false)
            guard let main = parts.first, parts.count <= 2 else { return nil }
            if let build = parts.dropFirst().first {
                let identifiers = build.split(separator: ".", omittingEmptySubsequences: false)
                guard !identifiers.isEmpty, identifiers.allSatisfy({ identifier in
                    !identifier.isEmpty && identifier.utf8.allSatisfy { byte in
                        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
                    }
                }) else { return nil }
            }

            let components = main.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(components.count) else { return nil }
            let numbers = components.compactMap { component -> Int? in
                guard !component.isEmpty, component.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return Int(component)
            }
            guard numbers.count == components.count else { return nil }
            self.numbers = numbers + Array(repeating: 0, count: 3 - numbers.count)
        }

        var text: String { numbers.map(String.init).joined(separator: ".") }

        static func < (lhs: Version, rhs: Version) -> Bool {
            lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
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
