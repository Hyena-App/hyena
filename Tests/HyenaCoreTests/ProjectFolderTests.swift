import XCTest
@testable import HyenaCore

final class ProjectFolderTests: XCTestCase {
    func testDiscoversFoldersHoldingSeveralProjects() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("HyenaHome-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        func make(_ path: String, marker: String? = nil) throws {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if let marker { try Data().write(to: url.appendingPathComponent(marker)) }
        }
        try make("code/api", marker: "Cargo.toml")
        try make("code/web", marker: "package.json")
        try make("Documents/GitHub/app", marker: "Package.swift")
        try make("Documents/GitHub/site/.git")
        try make("Documents/Notes/drafts")                 // not projects
        try make("one-project/app", marker: "go.mod")       // only one project
        try make("Library/Caches/a", marker: "package.json")
        try make("Library/Caches/b", marker: "package.json")

        let found = Set(ProjectFolders.discover(home: home).map(\.lastPathComponent))
        XCTAssertEqual(found, ["code", "GitHub"])
    }
}
