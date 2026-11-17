import Foundation
import XCTest
import AX1Core

final class AppUpdateTests: XCTestCase {
    func testReleaseVersionParsesTagsAndComparesNumerically() throws {
        XCTAssertEqual(ReleaseVersion("v1.3")?.text, "1.3.0")
        XCTAssertEqual(ReleaseVersion("1.4.0+5")?.text, "1.4.0")
        XCTAssertNil(ReleaseVersion("1.4.0-beta"))
        XCTAssertNil(ReleaseVersion("1..0"))
        XCTAssertNil(ReleaseVersion("1.2.3.4"))
        let v130 = try XCTUnwrap(ReleaseVersion("1.3.0"))
        XCTAssertLessThan(v130, try XCTUnwrap(ReleaseVersion("v1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.2.9")), v130)
        XCTAssertEqual(v130, ReleaseVersion("v1.3"))
    }

    func testDownloadURLOnlyAcceptsThisProjectsAppZip() {
        let good = "https://github.com/jonpikereally/AsteraDMXMidiBridge/releases/download/v1.4.0/AsteraDMXMidiBridge.zip"
        XCTAssertEqual(AppUpdate.downloadURL(assets: [(name: "notes.txt", url: "https://github.com/x"),
                                                      (name: "AsteraDMXMidiBridge.zip", url: good)])?.absoluteString, good)
        XCTAssertNil(AppUpdate.downloadURL(assets: []))
        XCTAssertNil(AppUpdate.downloadURL(assets: [(name: "AsteraDMXMidiBridge.zip",
            url: "http://github.com/jonpikereally/AsteraDMXMidiBridge/releases/download/v1.4.0/AsteraDMXMidiBridge.zip")]))
        XCTAssertNil(AppUpdate.downloadURL(assets: [(name: "AsteraDMXMidiBridge.zip",
            url: "https://example.com/jonpikereally/AsteraDMXMidiBridge/releases/download/v1.4.0/AsteraDMXMidiBridge.zip")]))
        XCTAssertNil(AppUpdate.downloadURL(assets: [(name: "AsteraDMXMidiBridge.zip",
            url: "https://github.com/someone/Other/releases/download/v1.4.0/AsteraDMXMidiBridge.zip")]))
    }

    func testDownloadRedirectsStayOnGitHubOverHTTPS() throws {
        for allowed in ["https://github.com/a", "https://objects.githubusercontent.com/a",
                        "https://release-assets.githubusercontent.com/a?sig=1"] {
            XCTAssertTrue(AppUpdate.allowsDownloadRedirect(to: try XCTUnwrap(URL(string: allowed))), allowed)
        }
        for refused in ["http://objects.githubusercontent.com/a", "https://githubusercontent.com.evil.example/a",
                        "https://evilgithubusercontent.com/a", "https://github.com:8443/a", "https://u:p@github.com/a"] {
            XCTAssertFalse(AppUpdate.allowsDownloadRedirect(to: try XCTUnwrap(URL(string: refused))), refused)
        }
    }

    func testBundleProblemRequiresSameAppAndExpectedNewerVersion() throws {
        let installed = try XCTUnwrap(ReleaseVersion("1.4.0"))
        let expected = try XCTUnwrap(ReleaseVersion("1.5.0"))
        let good: [String: Any] = ["CFBundleIdentifier": "com.jonpike.ax1bridge",
                                   "CFBundleShortVersionString": "1.5.0",
                                   "CFBundleExecutable": "AsteraDMXMidiBridge"]
        XCTAssertNil(AppUpdate.bundleProblem(info: good, expected: expected, installed: installed))

        var info = good
        info["CFBundleIdentifier"] = "com.example.other"
        XCTAssertNotNil(AppUpdate.bundleProblem(info: info, expected: expected, installed: installed))
        info = good
        info["CFBundleShortVersionString"] = "1.4.1"
        XCTAssertNotNil(AppUpdate.bundleProblem(info: info, expected: expected, installed: installed))
        info = good
        info["CFBundleShortVersionString"] = nil
        XCTAssertNotNil(AppUpdate.bundleProblem(info: info, expected: expected, installed: installed))
        info = good
        info["CFBundleExecutable"] = "Other"
        XCTAssertNotNil(AppUpdate.bundleProblem(info: info, expected: expected, installed: installed))
        XCTAssertNotNil(AppUpdate.bundleProblem(info: good, expected: installed, installed: installed))
    }
}
