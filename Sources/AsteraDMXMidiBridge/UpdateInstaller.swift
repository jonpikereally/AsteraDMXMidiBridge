import AX1Core
import Foundation

/// Downloads a release's app ZIP from GitHub, checks it, swaps it in place of the running app
/// and relaunches. Nothing on disk changes until the new bundle has passed every check.
enum UpdateInstaller {
    /// The running app bundle, if it is a packaged copy this user can replace.
    static func installedApp() throws -> URL {
        let app = Bundle.main.bundleURL.standardizedFileURL
        guard app.pathExtension == "app", Bundle.main.bundleIdentifier == AppUpdate.bundleIdentifier,
              !app.path.contains("/AppTranslocation/") else { throw InstallError.notInstalled }
        let files = FileManager.default
        guard files.isWritableFile(atPath: app.deletingLastPathComponent().path),
              files.isWritableFile(atPath: app.path) else { throw InstallError.notWritable }
        return app
    }

    /// Installs `version` from `download` over the running app and returns the app's location.
    static func install(version: String, from download: URL, installed: String) async throws -> URL {
        guard let expected = ReleaseVersion(version), let current = ReleaseVersion(installed) else {
            throw InstallError.rejected("its version can’t be read")
        }
        let app = try installedApp()
        let files = FileManager.default
        let work: URL
        do {
            work = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        } catch {
            throw InstallError.notWritable
        }
        defer { try? files.removeItem(at: work) }

        let zip = try await fetch(download, into: work)
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard (try? await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])) == 0 else {
            throw InstallError.unpack
        }
        let contents = (try? files.contentsOfDirectory(atPath: unpacked.path))?
            .filter { !$0.hasPrefix(".") && $0 != "__MACOSX" } ?? []
        guard contents == [AppUpdate.appName] else { throw InstallError.unpack }
        let newApp = unpacked.appendingPathComponent(AppUpdate.appName, isDirectory: true)

        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw InstallError.rejected("its Info.plist can’t be read")
        }
        if let problem = AppUpdate.bundleProblem(info: info, expected: expected, installed: current) {
            throw InstallError.rejected(problem)
        }
        guard (try? await run("/usr/bin/codesign", ["--verify", "--strict", "--deep", newApp.path])) == 0 else {
            throw InstallError.rejected("its code signature is invalid")
        }

        try Task.checkCancellation()
        do {
            _ = try files.replaceItemAt(app, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            throw InstallError.replace
        }
        return app
    }

    /// Opens the app at `app` once this process has quit.
    static func relaunch(_ app: URL, version: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "i=0; while /bin/kill -0 \"$1\" 2>/dev/null && [ $i -lt 300 ]; do /bin/sleep 0.2; i=$((i+1)); done; exec /usr/bin/open \"$2\"",
            "relaunch", String(ProcessInfo.processInfo.processIdentifier), app.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw InstallError.relaunch(version) }
    }

    private static func fetch(_ url: URL, into work: URL) async throws -> URL {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("AsteraDMXMidiBridge", forHTTPHeaderField: "User-Agent")

        let result: (URL, URLResponse)
        do {
            result = try await session.download(for: request, delegate: DownloadRedirects())
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw InstallError.download
        }
        try Task.checkCancellation()
        guard (result.1 as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: result.0)
            throw InstallError.download
        }
        let zip = work.appendingPathComponent(AppUpdate.assetName)
        do {
            try FileManager.default.moveItem(at: result.0, to: zip)
        } catch {
            throw InstallError.download
        }
        return zip
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private final class DownloadRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, AppUpdate.allowsDownloadRedirect(to: url) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }

    enum InstallError: LocalizedError {
        case noDownload, notInstalled, notWritable, download, unpack, rejected(String), replace, relaunch(String)

        var errorDescription: String? {
            switch self {
            case .noDownload:
                return "AX1-408 · This release has no app download. Click View release to download it."
            case .notInstalled:
                return "AX1-409 · This copy can’t update itself. Move AsteraDMXMidiBridge to Applications, open it from there and try again."
            case .notWritable:
                return "AX1-410 · You can’t write to the app’s folder, so the update can’t replace it. Use View release instead."
            case .download:
                return "AX1-411 · The update couldn’t be downloaded from GitHub. Check your connection and try again."
            case .unpack:
                return "AX1-412 · The downloaded update couldn’t be unpacked. Try again, or use View release."
            case .rejected(let reason):
                return "AX1-413 · The downloaded update was rejected because \(reason). Nothing was changed."
            case .replace:
                return "AX1-414 · The app couldn’t be replaced. Your current version is unchanged. Use View release instead."
            case .relaunch(let version):
                return "AX1-415 · Version \(version) is installed, but the app couldn’t restart itself. Quit and open it again."
            }
        }
    }
}
