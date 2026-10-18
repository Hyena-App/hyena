import XCTest
@testable import HyenaCore

final class AppReleaseTests: XCTestCase {
    func testComparesVersions() {
        let cases: [(String, String, Bool)] = [
            ("0.3.1", "0.3.0", true), ("0.10.0", "0.9.9", true), ("1.0", "0.9.9", true), ("0.3.0", "0.3.0", false),
            ("1.0", "1.0.0", false), ("0.2.0", "0.3.0", false), ("0.4.0-beta", "0.3.9", true),
        ]
        for (candidate, current, newer) in cases {
            XCTAssertEqual(AppRelease.isNewer(candidate, than: current), newer, "\(candidate) vs \(current)")
        }
    }

    func testParsesTheLatestReleaseAndPrefersTheVersionedDMG() throws {
        let json = #"""
        {"tag_name":"v0.3.0","draft":false,"prerelease":false,
         "html_url":"https://github.com/Hyena-App/hyena/releases/tag/v0.3.0","body":"Safety guardrails",
         "assets":[{"name":"Hyena.dmg","browser_download_url":"https://github.com/x/Hyena.dmg"},
                   {"name":"Hyena-0.3.0.dmg","browser_download_url":"https://github.com/x/Hyena-0.3.0.dmg"}]}
        """#
        let release = try XCTUnwrap(AppRelease.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "0.3.0")
        XCTAssertEqual(release.dmgURL?.lastPathComponent, "Hyena-0.3.0.dmg")
        XCTAssertEqual(release.notes, "Safety guardrails")
        XCTAssertNil(AppRelease.parse(Data(#"{"tag_name":"v9","prerelease":true,"html_url":"https://x.test"}"#.utf8)))
    }
}
